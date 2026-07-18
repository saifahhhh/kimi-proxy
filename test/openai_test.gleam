import gleam/json
import gleam/string
import gleeunit/should
import kimi_proxy/openai.{type Message, ChatRequest, Message}
import kimi_proxy/provider.{Coder, Planner}
import kimi_proxy/types.{Auto, DirectModel, ForceRole}

// --- to_task: model -> RouteMode (spec §6.7) -------------------------------

fn req(model: String, messages: List(Message)) -> openai.ChatRequest {
  ChatRequest(model: model, messages: messages, task_root: "")
}

pub fn to_task_auto_test() {
  let t = openai.to_task(req("auto", [Message("user", "hi")]))
  t.mode |> should.equal(Auto)
  t.user_prompt |> should.equal("hi")
}

pub fn to_task_plan_forces_planner_test() {
  openai.to_task(req("plan", [Message("user", "x")])).mode
  |> should.equal(ForceRole(Planner))
}

pub fn to_task_code_forces_coder_test() {
  openai.to_task(req("kimi", [Message("user", "x")])).mode
  |> should.equal(ForceRole(Coder))
}

pub fn to_task_unknown_is_direct_model_test() {
  openai.to_task(req("gemini-3-pro", [Message("user", "x")])).mode
  |> should.equal(DirectModel("gemini-3-pro"))
}

pub fn to_task_uses_last_user_message_test() {
  let r =
    req("auto", [
      Message("user", "first"),
      Message("assistant", "reply"),
      Message("user", "second"),
    ])
  openai.to_task(r).user_prompt |> should.equal("second")
}

// --- task_root (oo7 task context extension) --------------------------------

pub fn to_task_threads_task_root_test() {
  let r =
    ChatRequest("code", [Message("user", "x")], task_root: "/tmp/0001-demo")
  openai.to_task(r).task_root |> should.equal("/tmp/0001-demo")
}

pub fn decode_request_with_task_root_test() {
  let body =
    "{\"model\": \"code\", \"task_root\": \"/tmp/0001-demo\","
    <> " \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}]}"
  let assert Ok(r) = json.parse(body, openai.request_decoder())
  r.model |> should.equal("code")
  r.task_root |> should.equal("/tmp/0001-demo")
  r.messages |> should.equal([Message("user", "hi")])
}

pub fn decode_request_without_task_root_defaults_empty_test() {
  let body =
    "{\"model\": \"auto\","
    <> " \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}]}"
  let assert Ok(r) = json.parse(body, openai.request_decoder())
  r.task_root |> should.equal("")
}

// --- response builders (spec §8) -------------------------------------------

pub fn completion_has_openai_shape_test() {
  let s =
    json.to_string(openai.completion(
      "id1",
      "auto",
      "hello world",
      "planning",
      "planner",
      "CLI claude",
    ))
  string.contains(s, "chat.completion") |> should.be_true
  string.contains(s, "hello world") |> should.be_true
  string.contains(s, "assistant") |> should.be_true
  // the kimi_proxy extension states what actually ran
  string.contains(s, "\"kimi_proxy\"") |> should.be_true
  string.contains(s, "\"intent\":\"planning\"") |> should.be_true
  string.contains(s, "\"via\":\"CLI claude\"") |> should.be_true
}

pub fn models_list_test() {
  let s = json.to_string(openai.models_list(["auto", "code"]))
  string.contains(s, "\"list\"") |> should.be_true
  string.contains(s, "auto") |> should.be_true
}
