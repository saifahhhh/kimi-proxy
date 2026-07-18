import gleam/json
import gleam/result
import gleam/string
import gleeunit/should
import kimi_proxy/train.{TrainRequest}

// ---------------------------------------------------------------------------
// slug / note_path — filenames stay inside the vault, no traversal
// ---------------------------------------------------------------------------

pub fn slug_basic_test() {
  train.slug("Design Tokens Login") |> should.equal("design-tokens-login")
}

pub fn slug_keeps_thai_test() {
  train.slug("วิธีใช้ Figma") |> should.equal("วิธีใช้-figma")
}

pub fn slug_kills_traversal_test() {
  // `.` `/` `\` are all slugged to dashes, so `../../etc/passwd` cannot
  // escape the vault.
  train.slug("../../etc/passwd") |> should.equal("etc-passwd")
}

pub fn slug_collapses_and_trims_test() {
  train.slug("  -- hello    world --  ") |> should.equal("hello-world")
}

pub fn slug_drops_underscore_prefix_test() {
  // `_`-prefixed files are excluded from the index, so `_` is slugged away.
  train.slug("_secret") |> should.equal("secret")
}

pub fn note_path_ok_test() {
  train.note_path("decisions", "Bug NM1 Fix")
  |> should.equal(Ok("decisions/bug-nm1-fix.md"))
}

pub fn note_path_default_folder_ok_test() {
  train.note_path("notes", "hello")
  |> should.equal(Ok("notes/hello.md"))
}

pub fn note_path_rejects_unknown_folder_test() {
  train.note_path("sessions", "hello") |> result.is_error |> should.be_true
  train.note_path("../outside", "hello") |> result.is_error |> should.be_true
}

pub fn note_path_rejects_empty_title_test() {
  train.note_path("notes", "///...///") |> result.is_error |> should.be_true
  train.note_path("notes", "") |> result.is_error |> should.be_true
}

// ---------------------------------------------------------------------------
// render_note — frontmatter that memory.parse_frontmatter round-trips
// ---------------------------------------------------------------------------

pub fn render_note_test() {
  let req =
    TrainRequest(
      folder: "notes",
      title: "Design Tokens",
      tags: ["design", " login "],
      keywords: ["token", ""],
      content: "  # Tokens\nprimary: #2f6fed  ",
    )
  train.render_note(req, "2026-07-11")
  |> should.equal(
    "---\n"
    <> "title: Design Tokens\n"
    <> "tags: [design, login]\n"
    <> "keywords: [token]\n"
    <> "updated: 2026-07-11\n"
    <> "---\n\n"
    <> "# Tokens\nprimary: #2f6fed\n",
  )
}

// ---------------------------------------------------------------------------
// request decoding — required vs defaulted fields
// ---------------------------------------------------------------------------

pub fn decoder_full_body_test() {
  let body =
    "{\"folder\": \"project\", \"title\": \"t\", \"tags\": [\"a\"],"
    <> " \"keywords\": [\"k\"], \"content\": \"c\"}"
  json.parse(body, train.request_decoder())
  |> should.equal(
    Ok(TrainRequest(
      folder: "project",
      title: "t",
      tags: ["a"],
      keywords: ["k"],
      content: "c",
    )),
  )
}

pub fn decoder_defaults_test() {
  json.parse("{\"title\": \"t\", \"content\": \"c\"}", train.request_decoder())
  |> should.equal(
    Ok(TrainRequest(
      folder: "notes",
      title: "t",
      tags: [],
      keywords: [],
      content: "c",
    )),
  )
}

pub fn decoder_missing_title_is_error_test() {
  json.parse("{\"content\": \"c\"}", train.request_decoder())
  |> result.is_error
  |> should.be_true
}

// ---------------------------------------------------------------------------
// responses and page
// ---------------------------------------------------------------------------

pub fn trained_response_test() {
  train.trained("notes/hello.md", 19)
  |> json.to_string
  |> should.equal("{\"ok\":true,\"path\":\"notes/hello.md\",\"notes\":19}")
}

pub fn fail_response_test() {
  train.fail("boom")
  |> json.to_string
  |> should.equal("{\"ok\":false,\"error\":\"boom\"}")
}

pub fn page_shows_count_and_form_test() {
  let html = train.page(18)
  html |> string.contains(">18</strong>") |> should.be_true
  html |> string.contains("id='f'") |> should.be_true
  html |> string.contains("fetch('/train'") |> should.be_true
}
