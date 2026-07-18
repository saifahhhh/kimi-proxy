//// HTTP entry point (spec §1, §7, §8, §B.4): an OpenAI-compatible local proxy.
////
//// Boots a wisp+mist server and dispatches `POST /v1/chat/completions`,
//// `GET /v1/models`, `GET /health` and the Train button (`GET|POST /train`,
//// which feeds notes into the vault). All real work happens in `router.handle`
//// and `train`; this module is only request/response plumbing.
////
//// NOTE on gleam_otp (rule #4 / §A.6): we never import or use `gleam_otp`
//// ourselves and there are no actors in our code. `mist` — which the spec
//// mandates in §2 — pulls `gleam_otp` in transitively, as every BEAM HTTP server
//// must; that is unavoidable infrastructure, not application state.

import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/json
import kimi_proxy/config
import kimi_proxy/memory
import kimi_proxy/openai
import kimi_proxy/provider
import kimi_proxy/router
import kimi_proxy/routes
import kimi_proxy/train
import mist
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let assert Ok(cfg) = config.load()
  let secret = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(fn(req) { handle_request(req, cfg) }, secret)
    |> mist.new
    |> mist.bind(cfg.host)
    |> mist.port(cfg.port)
    |> mist.start

  process.sleep_forever()
}

/// The route table. Public so tests can drive it directly via `wisp/simulate`
/// without booting mist.
pub fn handle_request(req: Request, cfg: config.Config) -> Response {
  use <- wisp.log_request(req)
  case wisp.path_segments(req), req.method {
    ["v1", "chat", "completions"], Post -> completions(req, cfg)
    ["v1", "models"], Get -> models()
    ["train"], Get -> train_page(cfg)
    ["train"], Post -> train_submit(req, cfg)
    ["routes"], Get -> json_response(routes.report(cfg), 200)
    ["health"], _ -> wisp.ok()
    _, _ -> wisp.not_found()
  }
}

fn completions(req: Request, cfg: config.Config) -> Response {
  use body <- wisp.require_string_body(req)
  case json.parse(body, openai.request_decoder()) {
    Error(_) -> json_response(openai.error("invalid request body"), 422)
    Ok(chat_req) -> {
      let task = openai.to_task(chat_req)
      case router.handle(cfg, task) {
        Ok(handled) ->
          json_response(
            openai.completion(
              completion_id(),
              chat_req.model,
              handled.content,
              handled.intent,
              handled.role,
              handled.via,
            ),
            200,
          )
        Error(err) -> json_response(openai.error(provider.describe(err)), 503)
      }
    }
  }
}

/// The Train UI: a form that writes a note into the vault (see `train`).
fn train_page(cfg: config.Config) -> Response {
  wisp.html_response(train.page(memory.count_notes(cfg)), 200)
}

/// Handle a Train submission: validate, write the note atomically, rebuild
/// `_INDEX.md`, log to today's session, and report the fresh note count.
/// Honours `ENABLE_MEMORY_WRITE` the same way vault writes elsewhere do.
fn train_submit(req: Request, cfg: config.Config) -> Response {
  use body <- wisp.require_string_body(req)
  case cfg.enable_memory_write {
    False ->
      json_response(
        train.fail("vault writes are disabled (ENABLE_MEMORY_WRITE=false)"),
        403,
      )
    True ->
      case json.parse(body, train.request_decoder()) {
        Error(_) -> json_response(train.fail("invalid request body"), 422)
        Ok(tr) ->
          case train.note_path(tr.folder, tr.title) {
            Error(msg) -> json_response(train.fail(msg), 422)
            Ok(rel) ->
              case memory.write_note(cfg, rel, train.render_note(tr, train.today())) {
                Error(msg) -> json_response(train.fail(msg), 500)
                Ok(Nil) -> {
                  // Best-effort bookkeeping: a stale index or missing session
                  // line must not fail a successfully written note.
                  let _ = memory.rebuild_index(cfg)
                  let _ = memory.append_session(cfg, "TRAIN wrote " <> rel)
                  json_response(train.trained(rel, memory.count_notes(cfg)), 200)
                }
              }
          }
      }
  }
}

fn models() -> Response {
  json_response(
    openai.models_list([
      "auto", "plan", "code", "kimi-k3", "claude-opus-4-8", "gemini-3-pro",
      "gpt-5",
    ]),
    200,
  )
}

fn json_response(body: json.Json, status: Int) -> Response {
  wisp.json_response(json.to_string(body), status)
}

fn completion_id() -> String {
  "chatcmpl-" <> wisp.random_string(24)
}
