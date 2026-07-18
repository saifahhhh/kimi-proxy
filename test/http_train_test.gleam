//// Route-level tests for the Train endpoint: drive `handle_request` directly
//// with `wisp/simulate`, no mist server. The pure pieces are covered in
//// `train_test`; these prove the HTTP wiring (status codes, vault side
//// effects, the ENABLE_MEMORY_WRITE guard).

import gleam/http
import gleam/json
import gleam/string
import gleeunit/should
import kimi_proxy
import kimi_proxy/config.{Config}
import simplifile
import wisp/simulate

fn make_vault(name: String) -> String {
  let path = "build/test_tmp/" <> name
  let _ = simplifile.create_directory_all(path)
  path
}

fn test_config(vault: String) -> config.Config {
  Config(
    host: "127.0.0.1",
    port: 8080,
    vault_path: vault,
    dedalus_key: Error(Nil),
    coder_context_budget: 120_000,
    planner_context_budget: 80_000,
    enable_memory_write: True,
    sonnet_cli: ["claude"],
    kimi_cli: ["kimi"],
    usage_file: Error(Nil),
    usage_throttle_pct: 90,
  )
}

fn train_body(title: String, content: String) -> json.Json {
  json.object([
    #("folder", json.string("notes")),
    #("title", json.string(title)),
    #("tags", json.preprocessed_array([json.string("t1")])),
    #("content", json.string(content)),
  ])
}

pub fn get_train_page_shows_count_test() {
  let cfg = test_config(make_vault("train_http_get"))
  let res = kimi_proxy.handle_request(simulate.request(http.Get, "/train"), cfg)
  res.status |> should.equal(200)
  let body = simulate.read_body(res)
  body |> string.contains("Train the vault") |> should.be_true
  body |> string.contains("id='f'") |> should.be_true
}

pub fn post_train_writes_note_and_rebuilds_index_test() {
  let vault = make_vault("train_http_post")
  let cfg = test_config(vault)
  let res =
    kimi_proxy.handle_request(
      simulate.request(http.Post, "/train")
        |> simulate.json_body(train_body("Http Route Test", "hello from test")),
      cfg,
    )
  res.status |> should.equal(200)
  let body = simulate.read_body(res)
  body |> string.contains("\"ok\":true") |> should.be_true
  body |> string.contains("notes/http-route-test.md") |> should.be_true

  // side effects on disk: note written, index rebuilt, session logged
  let assert Ok(note) = simplifile.read(vault <> "/notes/http-route-test.md")
  note |> string.contains("hello from test") |> should.be_true
  note |> string.contains("title: Http Route Test") |> should.be_true
  let assert Ok(index) = simplifile.read(vault <> "/_INDEX.md")
  index |> string.contains("http-route-test") |> should.be_true
}

pub fn post_train_unknown_folder_is_422_test() {
  let cfg = test_config(make_vault("train_http_bad_folder"))
  let body =
    json.object([
      #("folder", json.string("sessions")),
      #("title", json.string("x")),
      #("content", json.string("y")),
    ])
  let res =
    kimi_proxy.handle_request(
      simulate.request(http.Post, "/train") |> simulate.json_body(body),
      cfg,
    )
  res.status |> should.equal(422)
}

pub fn post_train_invalid_json_is_422_test() {
  let cfg = test_config(make_vault("train_http_bad_json"))
  let res =
    kimi_proxy.handle_request(
      simulate.request(http.Post, "/train")
        |> simulate.string_body("not json at all"),
      cfg,
    )
  res.status |> should.equal(422)
}

pub fn post_train_disabled_writes_is_403_test() {
  let vault = make_vault("train_http_disabled")
  let cfg = Config(..test_config(vault), enable_memory_write: False)
  let res =
    kimi_proxy.handle_request(
      simulate.request(http.Post, "/train")
        |> simulate.json_body(train_body("Nope", "should not land")),
      cfg,
    )
  res.status |> should.equal(403)
  simplifile.read(vault <> "/notes/nope.md")
  |> should.equal(Error(simplifile.Enoent))
}

pub fn health_still_ok_test() {
  let cfg = test_config(make_vault("train_http_health"))
  kimi_proxy.handle_request(simulate.request(http.Get, "/health"), cfg).status
  |> should.equal(200)
}
