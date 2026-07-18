//// The `GET /routes` report: which concrete model (and effort) each role
//// actually resolves to, so clients like ask.sh can display the truth instead
//// of guessing. The planner's model/effort come from flags in its CLI words;
//// the coder's come from its `--config-file` TOML (kimi-cli has no --model
//// flag); both fall back to "cli-default" when nothing is pinned.

import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import kimi_proxy/config.{type Config}
import kimi_proxy/provider.{Coder, Planner}
import simplifile

/// Build the whole report: one entry per role.
pub fn report(cfg: Config) -> Json {
  json.object([
    #("plan", plan_report(cfg)),
    #("code", code_report(cfg)),
  ])
}

fn plan_report(cfg: Config) -> Json {
  role_json(
    cli_flag(cfg.sonnet_cli, "--model") |> result.unwrap("cli-default"),
    cli_flag(cfg.sonnet_cli, "--effort") |> result.unwrap("default"),
    head(cfg.sonnet_cli),
    provider.api_fallback(Planner),
  )
}

fn code_report(cfg: Config) -> Json {
  let #(model, effort) = kimi_model(cfg.kimi_cli)
  role_json(model, effort, head(cfg.kimi_cli), provider.api_fallback(Coder))
}

fn role_json(
  model: String,
  effort: String,
  via: String,
  fallback: String,
) -> Json {
  json.object([
    #("model", json.string(model)),
    #("effort", json.string(effort)),
    #("via", json.string(via)),
    #("fallback", json.string(fallback)),
  ])
}

fn head(words: List(String)) -> String {
  case words {
    [w, ..] -> w
    [] -> "api-only"
  }
}

/// The value following `flag` in a CLI word list, e.g.
/// `cli_flag(["claude", "--model", "x"], "--model") == Ok("x")`.
pub fn cli_flag(words: List(String), flag: String) -> Result(String, Nil) {
  case words {
    [] | [_] -> Error(Nil)
    [word, value, ..rest] ->
      case word == flag {
        True -> Ok(value)
        False -> cli_flag([value, ..rest], flag)
      }
  }
}

/// Resolve the Coder's pinned model + thinking mode from the TOML file named
/// by `--config-file`. Missing flag/file/keys degrade to defaults rather than
/// failing — this is a report, not a gate.
fn kimi_model(words: List(String)) -> #(String, String) {
  case cli_flag(words, "--config-file") {
    Error(Nil) -> #("cli-default", "default")
    Ok(path) ->
      case simplifile.read(path) {
        Error(_) -> #("cli-default", "default")
        Ok(raw) -> #(
          toml_scalar(raw, "default_model")
            |> result.map(strip_provider_prefix)
            |> result.unwrap("cli-default"),
          case toml_scalar(raw, "default_thinking") {
            Ok("true") -> "thinking on"
            _ -> "thinking off"
          },
        )
      }
  }
}

/// First `key = value` scalar in a TOML-ish text, quotes stripped. Enough for
/// the flat keys kimi-cli configs use — not a general TOML parser.
pub fn toml_scalar(raw: String, key: String) -> Result(String, Nil) {
  raw
  |> string.split("\n")
  |> list.find_map(fn(line) {
    case string.split_once(string.trim(line), "=") {
      Ok(#(k, v)) ->
        case string.trim(k) == key {
          True -> Ok(v |> string.trim |> string.replace("\"", ""))
          False -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
}

fn strip_provider_prefix(model: String) -> String {
  case string.split_once(model, "/") {
    Ok(#(_, rest)) -> rest
    Error(Nil) -> model
  }
}
