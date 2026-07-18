//// OpenAI wire format (spec §6.7, §8): decode incoming chat-completions
//// requests into a `Task`, and build the chat.completion / error / models-list
//// response JSON.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/result
import kimi_proxy/provider.{Coder, Planner}
import kimi_proxy/types.{
  type RouteMode, type Task, Auto, DirectModel, ForceRole, Question, Task, Turn,
}

/// A single OpenAI chat message on the wire.
pub type Message {
  Message(role: String, content: String)
}

/// A decoded chat-completions request (the subset we use). `task_root` is a
/// proxy extension: the absolute oo7 task folder the client detected, "" when
/// absent — standard OpenAI clients simply never send it.
pub type ChatRequest {
  ChatRequest(model: String, messages: List(Message), task_root: String)
}

/// Decoder for `POST /v1/chat/completions` request bodies (spec §8).
pub fn request_decoder() -> decode.Decoder(ChatRequest) {
  use model <- decode.field("model", decode.string)
  use messages <- decode.field("messages", decode.list(message_decoder()))
  use task_root <- decode.optional_field("task_root", "", decode.string)
  decode.success(ChatRequest(
    model: model,
    messages: messages,
    task_root: task_root,
  ))
}

fn message_decoder() -> decode.Decoder(Message) {
  use role <- decode.field("role", decode.string)
  use content <- decode.field("content", decode.string)
  decode.success(Message(role: role, content: content))
}

/// Map a decoded request to a `Task`: `model` becomes a `RouteMode`, the last
/// user message becomes the prompt, and all messages become history. The intent
/// is a placeholder — `router.handle` re-classifies it (spec §6.7).
pub fn to_task(req: ChatRequest) -> Task {
  Task(
    mode: model_to_route(req.model),
    intent: Question,
    user_prompt: last_user_content(req.messages),
    history: list.map(req.messages, fn(m) { Turn(m.role, m.content) }),
    task_root: req.task_root,
  )
}

fn model_to_route(model: String) -> RouteMode {
  case model {
    "auto" -> Auto
    "plan" | "design" | "opus" | "claude-opus-4-8" | "opus-4-8" ->
      ForceRole(Planner)
    "code" | "kimi" | "kimi-k3" -> ForceRole(Coder)
    other -> DirectModel(other)
  }
}

fn last_user_content(messages: List(Message)) -> String {
  messages
  |> list.filter(fn(m) { m.role == "user" })
  |> list.last
  |> result.map(fn(m) { m.content })
  |> result.unwrap("")
}

/// Build an OpenAI `chat.completion` response (spec §8), plus a `kimi_proxy`
/// extension object stating what actually ran — the classified intent, the
/// role, and the backend that served (CLI vs API fallback). Standard OpenAI
/// clients ignore unknown fields; ask.sh displays it.
pub fn completion(
  id: String,
  model: String,
  content: String,
  intent: String,
  role: String,
  via: String,
) -> Json {
  json.object([
    #("id", json.string(id)),
    #("object", json.string("chat.completion")),
    #("model", json.string(model)),
    #(
      "kimi_proxy",
      json.object([
        #("intent", json.string(intent)),
        #("role", json.string(role)),
        #("via", json.string(via)),
      ]),
    ),
    #(
      "choices",
      json.preprocessed_array([
        json.object([
          #("index", json.int(0)),
          #(
            "message",
            json.object([
              #("role", json.string("assistant")),
              #("content", json.string(content)),
            ]),
          ),
          #("finish_reason", json.string("stop")),
        ]),
      ]),
    ),
    #(
      "usage",
      json.object([
        #("prompt_tokens", json.int(0)),
        #("completion_tokens", json.int(0)),
        #("total_tokens", json.int(0)),
      ]),
    ),
  ])
}

/// Build an OpenAI-style error body (spec §8).
pub fn error(message: String) -> Json {
  json.object([
    #(
      "error",
      json.object([
        #("message", json.string(message)),
        #("type", json.string("invalid_request_error")),
      ]),
    ),
  ])
}

/// Build a `GET /v1/models` list response (spec §8).
pub fn models_list(ids: List(String)) -> Json {
  json.object([
    #("object", json.string("list")),
    #(
      "data",
      json.preprocessed_array(
        list.map(ids, fn(id) {
          json.object([
            #("id", json.string(id)),
            #("object", json.string("model")),
          ])
        }),
      ),
    ),
  ])
}
