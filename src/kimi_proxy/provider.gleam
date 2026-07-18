//// Backend provider: dispatch a prompt to a role's fallback chain (spec §6.5).
////
//// Each role maps to an ordered chain of backends: the subscription CLI first
//// (cheaper, uses the user's plan) then the Dedalus API as a paid fallback. A
//// layer "fails" — and we move to the next — when the CLI is missing, exits
//// non-zero, or returns a quota/rate-limit message in stdout (spec §12, §15).
////
//// IMPORTANT: this module must NOT import `memory` or `router`, or it would form
//// a provider → memory → router → provider import cycle. So the spec §6.5 idea
//// of `append_session`-logging a quota fallback is left to the orchestration
//// layer (router, Phase 5); here we only detect quota and fall back.

import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import kimi_proxy/config.{type Config}
import shellout
import simplifile

// ---------------------------------------------------------------------------
// Types (spec §4.1)
// ---------------------------------------------------------------------------

/// A role in the system (not a concrete model name).
pub type Role {
  Planner
  Coder
}

/// One backend layer in a role's fallback chain.
pub type Mode {
  Subscription(cli: String, args: List(String))
  Api(dedalus_model: String)
}

/// A successful reply plus which backend actually produced it — so responses
/// can say who did the work (subscription CLI vs the API fallback).
pub type Answer {
  Answer(content: String, via: String)
}

/// Errors raised by the provider layer.
pub type LlmError {
  AllBackendsFailed(role: Role)
  QuotaExhausted(cli: String)
  /// The subscription layer was skipped proactively because reported usage is
  /// at/above the throttle threshold (spec §21). Same fallback path as
  /// `QuotaExhausted`, but before spending a CLI call.
  Throttled(cli: String)
  UnknownModel(name: String)
  CliError(code: Int, stderr: String)
  ApiError(reason: String)
}

/// Dedalus is OpenAI-compatible. The exact endpoint is not pinned by the spec;
/// this default can be edited for the single-user v2 deployment. It is never
/// exercised by the test suite (tests run without a DEDALUS_KEY).
const dedalus_url = "https://api.dedaluslabs.ai/v1/chat/completions"

const quota_signals = [
  "quota", "rate limit", "limit reached", "usage limit", "upgrade your plan",
  "too many requests",
]

// ---------------------------------------------------------------------------
// Public API (spec §6.5)
// ---------------------------------------------------------------------------

/// Run a role through its fallback chain (subscription CLI → API). Returns the
/// first backend's successful `Answer` (content + which backend served it), or
/// `AllBackendsFailed` if every layer fails.
pub fn run_role(
  cfg: Config,
  role: Role,
  prompt: String,
) -> Result(Answer, LlmError) {
  run_chain(cfg, role, chain_for(cfg, role), prompt)
}

/// Run a specific model by name straight through the API (used for DirectModel,
/// e.g. "gemini-3-pro"). Bypasses the subscription chain.
pub fn run_model(
  cfg: Config,
  model: String,
  prompt: String,
) -> Result(Answer, LlmError) {
  via_api(cfg, model, prompt)
  |> result.map(Answer(_, "API " <> model))
}

/// Human-readable description of an error (used for HTTP 503 bodies, spec §8).
pub fn describe(err: LlmError) -> String {
  case err {
    AllBackendsFailed(role) -> "all backends failed for " <> role_name(role)
    QuotaExhausted(cli) -> "quota exhausted on " <> cli
    Throttled(cli) -> "subscription throttled on " <> cli <> " (usage at limit)"
    UnknownModel(name) -> "unknown model: " <> name
    CliError(code, stderr) ->
      "CLI exited " <> int.to_string(code) <> ": " <> stderr
    ApiError(reason) -> "API error: " <> reason
  }
}

/// True if `output` contains any known quota / rate-limit signal (spec §6.5).
/// Public so the quota patterns can be unit-tested directly.
pub fn is_quota_error(output: String) -> Bool {
  let low = string.lowercase(output)
  list.any(quota_signals, fn(s) { string.contains(low, s) })
}

/// Read the externally-maintained usage percent (spec §21.2): a plain-text
/// integer 0-100 at `cfg.usage_file`, written by an updater outside this
/// codebase. `Error(Nil)` on anything unexpected — unconfigured, missing file,
/// unparseable or out-of-range content — which callers treat as "unknown,
/// proceed normally". Must never fail a request.
pub fn read_usage(cfg: Config) -> Result(Int, Nil) {
  use path <- result.try(cfg.usage_file)
  use raw <- result.try(
    simplifile.read(from: path) |> result.replace_error(Nil),
  )
  use pct <- result.try(
    int.parse(string.trim(raw)) |> result.replace_error(Nil),
  )
  case pct >= 0 && pct <= 100 {
    True -> Ok(pct)
    False -> Error(Nil)
  }
}

/// Proactive pacing check (spec §21.3): throttle only on a readable usage
/// value at/above the threshold. Unknown usage never throttles.
fn throttled(cfg: Config) -> Bool {
  case read_usage(cfg) {
    Ok(pct) -> pct >= cfg.usage_throttle_pct
    Error(Nil) -> False
  }
}

// ---------------------------------------------------------------------------
// Chain assembly + dispatch
// ---------------------------------------------------------------------------

fn role_name(role: Role) -> String {
  case role {
    Planner -> "planner"
    Coder -> "coder"
  }
}

/// The Dedalus API model a role falls back to when its CLI fails (spec §6.5).
/// Public so the `/routes` report can state it.
pub fn api_fallback(role: Role) -> String {
  case role {
    Planner -> "anthropic/claude-opus-4-8"
    Coder -> "moonshot/kimi-k3"
  }
}

/// Build the fallback chain for a role: configured subscription CLI (if any),
/// then the role's Dedalus API model (spec §6.5).
fn chain_for(cfg: Config, role: Role) -> List(Mode) {
  case role {
    Planner -> with_sub(cfg.sonnet_cli, Api(api_fallback(Planner)))
    Coder -> with_sub(cfg.kimi_cli, Api(api_fallback(Coder)))
  }
}

fn with_sub(cli_words: List(String), api: Mode) -> List(Mode) {
  case cli_words {
    [cli, ..args] -> [Subscription(cli, args), api]
    [] -> [api]
  }
}

fn run_chain(
  cfg: Config,
  role: Role,
  modes: List(Mode),
  prompt: String,
) -> Result(Answer, LlmError) {
  case modes {
    [] -> Error(AllBackendsFailed(role))
    [mode, ..rest] ->
      case run_mode(cfg, mode, prompt) {
        Ok(out) -> Ok(Answer(out, describe_mode(mode)))
        Error(_) -> run_chain(cfg, role, rest, prompt)
      }
  }
}

/// Short human label for the backend that served a request.
fn describe_mode(mode: Mode) -> String {
  case mode {
    Subscription(cli, args) -> "CLI " <> cli_label(cli, args)
    Api(model) -> "API " <> model
  }
}

/// Name the real tool, not the runner: `uvx kimi-cli …` reads better as
/// `kimi-cli` than `uvx`.
fn cli_label(cli: String, args: List(String)) -> String {
  case cli, args {
    "uvx", [tool, ..] -> tool
    "npx", [tool, ..] -> tool
    _, _ -> cli
  }
}

fn run_mode(
  cfg: Config,
  mode: Mode,
  prompt: String,
) -> Result(String, LlmError) {
  case mode {
    // Proactive throttle guard (spec §21.3): lives here — not as a new Mode
    // and not in run_chain — so the chain recursion keeps today's shape and a
    // throttled subscription falls through to the next layer exactly like a
    // reactive quota failure. Never errors the request out on its own.
    Subscription(cli, args) ->
      case throttled(cfg) {
        True -> Error(Throttled(cli))
        False -> via_cli(cli, args, prompt)
      }
    Api(model) -> via_api(cfg, model, prompt)
  }
}

/// Run a subscription CLI with the prompt appended as the final argument, and
/// treat a quota message in stdout as a failure of this layer (spec §B.2).
fn via_cli(
  cli: String,
  args: List(String),
  prompt: String,
) -> Result(String, LlmError) {
  let full_args = list.append(args, [prompt])
  // Spawn through `sh` with stdin redirected from /dev/null. Both claude and
  // kimi CLIs poll a non-tty stdin for ~3s and then print a warning INTO
  // their output — which contaminated responses and, via remember(), the
  // vault itself. shellout has no stdin option, so a tiny sh wrapper does the
  // redirect; `"$0"` is the real CLI, `"$@"` its args. Also saves the 3s wait.
  case
    shellout.command(
      run: "sh",
      with: ["-c", "exec \"$0\" \"$@\" < /dev/null", cli, ..full_args],
      in: ".",
      opt: [],
    )
  {
    Ok(stdout) ->
      case is_quota_error(stdout) {
        True -> Error(QuotaExhausted(cli))
        False -> Ok(stdout)
      }
    Error(#(code, stderr)) -> Error(CliError(code, stderr))
  }
}

// ---------------------------------------------------------------------------
// Dedalus API (OpenAI-compatible). Untested path: needs DEDALUS_KEY, which the
// test suite never sets, so it never reaches the network during `gleam test`.
// ---------------------------------------------------------------------------

fn via_api(
  cfg: Config,
  model: String,
  prompt: String,
) -> Result(String, LlmError) {
  use key <- result.try(case cfg.dedalus_key {
    Ok(k) -> Ok(k)
    Error(Nil) -> Error(ApiError("DEDALUS_KEY not set"))
  })
  use base <- result.try(
    request.to(dedalus_url)
    |> result.replace_error(ApiError("invalid Dedalus URL")),
  )
  let body =
    json.object([
      #("model", json.string(model)),
      #(
        "messages",
        json.preprocessed_array([
          json.object([
            #("role", json.string("user")),
            #("content", json.string(prompt)),
          ]),
        ]),
      ),
    ])
    |> json.to_string
  let req =
    base
    |> request.set_method(http.Post)
    |> request.set_header("authorization", "Bearer " <> key)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)
  case httpc.send(req) {
    Ok(resp) -> parse_content(resp.body)
    Error(_) -> Error(ApiError("request to Dedalus failed"))
  }
}

fn parse_content(body: String) -> Result(String, LlmError) {
  case json.parse(body, response_decoder()) {
    Ok([first, ..]) -> Ok(first)
    Ok([]) -> Error(ApiError("Dedalus returned no choices"))
    Error(_) -> Error(ApiError("could not parse Dedalus response"))
  }
}

fn response_decoder() -> decode.Decoder(List(String)) {
  use choices <- decode.field("choices", decode.list(choice_decoder()))
  decode.success(choices)
}

fn choice_decoder() -> decode.Decoder(String) {
  use content <- decode.field("message", message_decoder())
  decode.success(content)
}

fn message_decoder() -> decode.Decoder(String) {
  use content <- decode.field("content", decode.string)
  decode.success(content)
}
