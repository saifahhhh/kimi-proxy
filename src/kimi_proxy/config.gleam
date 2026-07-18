//// Configuration loading for kimi_proxy.
////
//// Reads all settings from environment variables (with sensible defaults) once
//// at boot and hands a validated `Config` to the rest of the system. Pure apart
//// from reading env vars plus a single filesystem check that `VAULT_PATH`
//// points at a real directory. See spec §6.1 / §13.

import envoy
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// System configuration, loaded from the environment at boot (spec §4.5).
pub type Config {
  Config(
    host: String,
    port: Int,
    vault_path: String,
    dedalus_key: Result(String, Nil),
    coder_context_budget: Int,
    planner_context_budget: Int,
    enable_memory_write: Bool,
    sonnet_cli: List(String),
    kimi_cli: List(String),
    // Proactive usage throttle (spec §21): path to a plain-text 0-100 percent
    // written by an external updater, absent by default so the whole feature
    // is a no-op unless configured; and the percent at/above which the
    // subscription layer is skipped for a call.
    usage_file: Result(String, Nil),
    usage_throttle_pct: Int,
  )
}

/// Load and validate configuration from environment variables.
///
/// `VAULT_PATH` is required and must point at an existing directory; every other
/// setting has a default. Returns a human-readable `Error(String)` describing
/// the first problem found: missing vault, vault that is not a directory, or an
/// unparseable integer env var (e.g. `PORT`).
pub fn load() -> Result(Config, String) {
  use vault_path <- result.try(
    envoy.get("VAULT_PATH")
    |> result.replace_error("VAULT_PATH is required but is not set"),
  )

  use _ <- result.try(ensure_directory(vault_path))

  use port <- result.try(read_int("PORT", 8080))
  use coder_budget <- result.try(read_int("CODER_BUDGET", 120_000))
  use planner_budget <- result.try(read_int("PLANNER_BUDGET", 80_000))
  use usage_throttle_pct <- result.try(read_int("USAGE_THROTTLE_PCT", 90))

  Ok(Config(
    host: envoy.get("HOST") |> result.unwrap("127.0.0.1"),
    port: port,
    vault_path: vault_path,
    dedalus_key: envoy.get("DEDALUS_KEY"),
    coder_context_budget: coder_budget,
    planner_context_budget: planner_budget,
    enable_memory_write: read_bool("ENABLE_MEMORY_WRITE", True),
    // Planner default: Claude Code CLI in print mode, pinned to Opus 4.8
    // (`--model claude-opus-4-8`) so the proxy does not inherit whatever model
    // ~/.claude/settings.json happens to select. (The SONNET_CLI env/field name
    // predates the Opus pin and is kept for compat.) `--output-format text` keeps
    // stdout to the answer only. The prompt (appended last by provider.via_cli)
    // becomes `-p`'s value. We deliberately do NOT pass `--disallowedTools`
    // (it hung on real prompts here); instead the planning prompt itself tells
    // Claude to return text and not write files (see
    // router.planning_instruction) — the proxy owns vault writes. Verified.
    sonnet_cli: read_words("SONNET_CLI", [
      "claude", "--model", "claude-opus-4-8", "--output-format", "text", "-p",
    ]),
    // Coder default: invoke kimi-cli via `uvx` (the VS Code extension's bundled
    // launcher hard-codes a uv path that may be absent). `--quiet` =
    // print/non-interactive/final-message-only; the prompt is appended as the
    // final `-p` value by provider.via_cli.
    //
    // READ-ONLY by default (verified 2026-06-01): `--agent-file <readonly>` loads
    // an agent that excludes WriteFile/StrReplaceFile/Shell/Agent, so Kimi can
    // read the repo but cannot create/edit files (it kept injecting `pub fn add`
    // into our own source when run from the project dir). Capability-level guard,
    // not a prompt request. Override KIMI_CLI to re-enable writes for agent use.
    kimi_cli: read_words("KIMI_CLI", default_kimi_cli()),
    // Same absent-by-default pattern as dedalus_key: unset means the proxy
    // never consults usage and behaves exactly as before (spec §21).
    usage_file: envoy.get("USAGE_STATUS_FILE"),
    usage_throttle_pct: usage_throttle_pct,
  ))
}

/// Default Coder invocation: kimi-cli via uvx in read-only mode, pinned to
/// Kimi K3 via `--config-file` (kimi-cli has no `--model` flag; the config
/// file carries `default_model` plus the provider it needs — see
/// agents/kimi-k3.toml). Both files live next to the project; we resolve
/// their paths so the CLI finds them regardless of the proxy's working
/// directory.
fn default_kimi_cli() -> List(String) {
  let agent = readonly_agent_path()
  let model_config = kimi_config_path()
  [
    "uvx", "kimi-cli", "--agent-file", agent, "--config-file", model_config,
    "--quiet", "-p",
  ]
}

/// Absolute path to the read-only agent spec. Overridable via KIMI_AGENT_FILE;
/// otherwise defaults to `agents/readonly.agent.yaml` under the proxy project
/// (KIMI_PROXY_DIR), falling back to a project-relative path.
fn readonly_agent_path() -> String {
  case envoy.get("KIMI_AGENT_FILE") {
    Ok(p) -> p
    Error(Nil) -> {
      let base =
        envoy.get("KIMI_PROXY_DIR")
        |> result.unwrap(".")
      base <> "/agents/readonly.agent.yaml"
    }
  }
}

/// Absolute path to the kimi-cli config that pins the Coder model (K3).
/// Overridable via KIMI_CONFIG_FILE; otherwise defaults to
/// `agents/kimi-k3.toml` under the proxy project (KIMI_PROXY_DIR), falling
/// back to a project-relative path — same resolution as the agent file.
fn kimi_config_path() -> String {
  case envoy.get("KIMI_CONFIG_FILE") {
    Ok(p) -> p
    Error(Nil) -> {
      let base =
        envoy.get("KIMI_PROXY_DIR")
        |> result.unwrap(".")
      base <> "/agents/kimi-k3.toml"
    }
  }
}

/// Confirm `path` exists and is a directory. Per spec §6.1 a missing or
/// non-directory vault is a hard error — the whole memory subsystem needs it.
fn ensure_directory(path: String) -> Result(Nil, String) {
  case simplifile.is_directory(path) {
    Ok(True) -> Ok(Nil)
    Ok(False) -> Error("VAULT_PATH is not a directory: " <> path)
    Error(e) ->
      Error(
        "cannot access VAULT_PATH ("
        <> path
        <> "): "
        <> simplifile.describe_error(e),
      )
  }
}

/// Read an integer env var, falling back to `default` when unset or empty.
/// A present-but-unparseable value is an error (spec §6.1 edge case: PORT).
fn read_int(name: String, default: Int) -> Result(Int, String) {
  case envoy.get(name) {
    Error(Nil) -> Ok(default)
    Ok("") -> Ok(default)
    Ok(raw) ->
      int.parse(raw)
      |> result.replace_error(name <> " must be an integer, got: " <> raw)
  }
}

/// Read a boolean env var. Only explicit falsy/truthy words are recognised;
/// anything unrecognised (or unset) yields `default`. Keeps
/// `ENABLE_MEMORY_WRITE` default-on per spec §13.
fn read_bool(name: String, default: Bool) -> Bool {
  case envoy.get(name) {
    Error(Nil) -> default
    Ok(raw) ->
      case string.lowercase(raw) {
        "false" | "0" | "no" | "off" -> False
        "true" | "1" | "yes" | "on" -> True
        _ -> default
      }
  }
}

/// Read a space-separated env var into a word list, falling back to `default`
/// when unset or effectively empty. Used for SONNET_CLI / KIMI_CLI.
fn read_words(name: String, default: List(String)) -> List(String) {
  case envoy.get(name) {
    Error(Nil) -> default
    Ok(raw) ->
      case raw |> string.split(" ") |> list.filter(fn(w) { w != "" }) {
        [] -> default
        words -> words
      }
  }
}
