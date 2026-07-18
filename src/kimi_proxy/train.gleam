//// The Train button (vault feeding over HTTP).
////
//// "Training" this system is not gradient descent — the proxy is only as smart
//// as the vault, so training = writing a markdown note into it. The proxy
//// reads the vault fresh on every request, so a trained note takes effect
//// immediately, no restart. This module holds the pure, unit-testable pieces:
//// request decoding, slug/path derivation (with path-traversal guards), note
//// rendering, response JSON and the HTML page. HTTP wiring stays in
//// `kimi_proxy.gleam`, vault I/O stays in `memory.gleam`.

import birl
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

/// A decoded `POST /train` body: which vault folder the note belongs to, its
/// title (becomes the filename), optional tags/keywords used by relevance
/// selection, and the markdown body.
pub type TrainRequest {
  TrainRequest(
    folder: String,
    title: String,
    tags: List(String),
    keywords: List(String),
    content: String,
  )
}

/// Decoder for `POST /train` bodies. Only `title` and `content` are required;
/// `folder` defaults to `notes`, tags/keywords to empty.
pub fn request_decoder() -> decode.Decoder(TrainRequest) {
  use folder <- decode.optional_field("folder", "notes", decode.string)
  use title <- decode.field("title", decode.string)
  use tags <- decode.optional_field("tags", [], decode.list(decode.string))
  use keywords <- decode.optional_field(
    "keywords",
    [],
    decode.list(decode.string),
  )
  use content <- decode.field("content", decode.string)
  decode.success(TrainRequest(
    folder: folder,
    title: title,
    tags: tags,
    keywords: keywords,
    content: content,
  ))
}

/// Derive the vault-relative path for a note. The folder must be one of the
/// known vault sections and the slugged title must be non-empty, so a request
/// can never write outside the vault (`..`, `/` and friends are slugged away).
/// Writing the same title again overwrites — that is how a note gets updated.
pub fn note_path(folder: String, title: String) -> Result(String, String) {
  use folder <- result.try(valid_folder(folder))
  case slug(title) {
    "" -> Error("title must contain at least one usable character")
    s -> Ok(folder <> "/" <> s <> ".md")
  }
}

fn valid_folder(folder: String) -> Result(String, String) {
  case folder {
    "notes" | "project" | "decisions" | "tasks" -> Ok(folder)
    other ->
      Error(
        "folder must be one of notes/project/decisions/tasks, got: " <> other,
      )
  }
}

/// Turn a title into a filesystem-safe slug: lowercase, path-dangerous and
/// separator characters become dashes (killing `..` and `/` traversal), runs
/// of dashes collapse, edge dashes drop, length capped at 80. A leading `_`
/// is also slugged away because `memory.is_indexable` skips `_`-prefixed files.
pub fn slug(title: String) -> String {
  forbidden
  |> list.fold(string.lowercase(title), fn(acc, ch) {
    string.replace(acc, ch, "-")
  })
  |> collapse_dashes
  |> trim_dashes
  |> string.slice(0, 80)
}

const forbidden = [
  "/", "\\", ".", " ", "\t", "\n", "\r", "\"", "'", "?", "*", ":", ";", "<",
  ">", "|", "#", "[", "]", "{", "}", "(", ")", "!", "@", "$", "%", "^", "&",
  "=", "+", "`", "~", ",", "_",
]

fn collapse_dashes(s: String) -> String {
  case string.contains(s, "--") {
    True -> collapse_dashes(string.replace(s, "--", "-"))
    False -> s
  }
}

fn trim_dashes(s: String) -> String {
  s |> drop_leading_dashes |> string.reverse |> drop_leading_dashes
  |> string.reverse
}

fn drop_leading_dashes(s: String) -> String {
  case string.starts_with(s, "-") {
    True -> drop_leading_dashes(string.drop_start(s, 1))
    False -> s
  }
}

/// Render a note as markdown with the frontmatter `memory.parse_frontmatter`
/// expects (title / tags / keywords / updated). `updated` is injected so the
/// output is deterministic under test; the HTTP layer passes `today()`.
pub fn render_note(req: TrainRequest, updated: String) -> String {
  "---\n"
  <> "title: "
  <> string.trim(req.title)
  <> "\n"
  <> "tags: ["
  <> string.join(clean(req.tags), ", ")
  <> "]\n"
  <> "keywords: ["
  <> string.join(clean(req.keywords), ", ")
  <> "]\n"
  <> "updated: "
  <> updated
  <> "\n---\n\n"
  <> string.trim(req.content)
  <> "\n"
}

fn clean(xs: List(String)) -> List(String) {
  xs |> list.map(string.trim) |> list.filter(fn(x) { x != "" })
}

/// Today's date as YYYY-MM-DD for the `updated:` frontmatter field.
pub fn today() -> String {
  birl.to_naive_date_string(birl.now())
}

/// Success body for `POST /train`: where the note landed and the new count.
pub fn trained(path: String, notes: Int) -> Json {
  json.object([
    #("ok", json.bool(True)),
    #("path", json.string(path)),
    #("notes", json.int(notes)),
  ])
}

/// Failure body for `POST /train`.
pub fn fail(message: String) -> Json {
  json.object([
    #("ok", json.bool(False)),
    #("error", json.string(message)),
  ])
}

/// The Train page: a self-contained HTML form (inline CSS/JS, single-quoted
/// throughout so it embeds cleanly in a Gleam string) that POSTs JSON to
/// `/train` and shows the fresh note count.
pub fn page(note_count: Int) -> String {
  "<!doctype html>
<html lang='th'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>kimi_proxy — Train</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: -apple-system, 'Segoe UI', sans-serif;
         background: #0f1117; color: #e6e8ee; }
  main { max-width: 640px; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
  h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
  .sub { color: #9aa3b2; margin: 0 0 1rem; line-height: 1.5; }
  .count { background: #1a1f2b; border: 1px solid #2a3245; border-radius: 10px;
           padding: .75rem 1rem; margin: 0 0 1.5rem; }
  .count strong { color: #7cc4ff; font-size: 1.25rem; }
  label { display: block; margin: 0 0 1rem; font-size: .9rem; color: #b8c0cf; }
  input, select, textarea { display: block; width: 100%; margin-top: .35rem;
    padding: .6rem .75rem; border-radius: 8px; border: 1px solid #2a3245;
    background: #161a24; color: #e6e8ee; font-size: 1rem; font-family: inherit; }
  textarea { resize: vertical; min-height: 10rem; }
  button { width: 100%; padding: .8rem; border: 0; border-radius: 10px;
    background: #2f6fed; color: white; font-size: 1.05rem; font-weight: 600;
    cursor: pointer; }
  button:disabled { opacity: .6; cursor: wait; }
  #result { margin-top: 1rem; padding: .75rem 1rem; border-radius: 8px;
    display: none; line-height: 1.5; word-break: break-all; }
  #result.ok { display: block; background: #10281a; border: 1px solid #1f5c37;
    color: #7fe0a7; }
  #result.err { display: block; background: #2b1416; border: 1px solid #6b2a2e;
    color: #ff9ba1; }
</style>
</head>
<body>
<main>
  <h1>🧠 Train the vault</h1>
  <p class='sub'>สอน proxy ให้รู้เพิ่ม = เพิ่ม note ลง vault
     — บันทึกแล้วมีผลทันที ไม่ต้อง restart (proxy อ่านสดทุก request)</p>
  <p class='count'>ตอนนี้ vault มี <strong id='count'>"
  <> int.to_string(note_count)
  <> "</strong> notes</p>
  <form id='f'>
    <label>โฟลเดอร์
      <select id='folder'>
        <option value='notes'>notes — ความรู้ทั่วไป</option>
        <option value='project'>project — โหลดแทบทุก request (stack/conventions/design)</option>
        <option value='decisions'>decisions — โหลดเมื่อ keyword ตรง (ADR/flow/protocol)</option>
        <option value='tasks'>tasks — แผนงาน</option>
      </select>
    </label>
    <label>ชื่อ note (จะกลายเป็นชื่อไฟล์ — ชื่อซ้ำ = อัปเดตทับ)
      <input id='title' required placeholder='เช่น design-tokens-login'>
    </label>
    <label>tags (คั่นด้วย ,)
      <input id='tags' placeholder='design, login'>
    </label>
    <label>keywords (คั่นด้วย ,)
      <input id='keywords' placeholder='token, color, spacing'>
    </label>
    <label>เนื้อหา (markdown)
      <textarea id='content' required placeholder='สิ่งที่อยากให้ proxy รู้...'></textarea>
    </label>
    <button type='submit' id='btn'>🚀 Train</button>
  </form>
  <div id='result'></div>
</main>
<script>
  const form = document.getElementById('f');
  const csv = (s) => s.split(',').map((x) => x.trim()).filter(Boolean);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = document.getElementById('btn');
    const out = document.getElementById('result');
    btn.disabled = true;
    btn.textContent = 'Training...';
    try {
      const res = await fetch('/train', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          folder: document.getElementById('folder').value,
          title: document.getElementById('title').value,
          tags: csv(document.getElementById('tags').value),
          keywords: csv(document.getElementById('keywords').value),
          content: document.getElementById('content').value,
        }),
      });
      const data = await res.json();
      if (data.ok) {
        document.getElementById('count').textContent = data.notes;
        out.className = 'ok';
        out.textContent = 'เทรนแล้ว ✓ บันทึกที่ ' + data.path
          + ' — ตอนนี้ vault มี ' + data.notes
          + ' notes (มีผลทันที ไม่ต้อง restart)';
        form.reset();
      } else {
        out.className = 'err';
        out.textContent = 'ผิดพลาด: ' + data.error;
      }
    } catch (err) {
      out.className = 'err';
      out.textContent = 'ต่อ proxy ไม่ได้: ' + err;
    }
    btn.disabled = false;
    btn.textContent = '🚀 Train';
  });
</script>
</body>
</html>
"
}
