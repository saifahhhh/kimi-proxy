import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import kimi_proxy/config.{type Config, Config}
import kimi_proxy/memory
import kimi_proxy/types
import simplifile

// --- helpers ---------------------------------------------------------------

fn tmp_cfg(name: String) -> Config {
  let vault = "build/test_tmp/mem_" <> name
  // start from a clean slate so reruns are deterministic
  let _ = simplifile.delete(vault)
  let _ = simplifile.create_directory_all(vault)
  Config(
    host: "127.0.0.1",
    port: 8080,
    vault_path: vault,
    dedalus_key: Error(Nil),
    coder_context_budget: 120_000,
    planner_context_budget: 80_000,
    enable_memory_write: True,
    sonnet_cli: ["claude", "-p"],
    kimi_cli: ["kimi-code", "--quiet"],
    usage_file: Error(Nil),
    usage_throttle_pct: 90,
  )
}

fn task(prompt: String) -> types.Task {
  types.Task(
    mode: types.Auto,
    intent: types.Question,
    user_prompt: prompt,
    history: [],
    task_root: "",
  )
}

// --- parse_frontmatter -----------------------------------------------------

pub fn parse_frontmatter_full_test() {
  let raw =
    "---\n"
    <> "title: Auth flow\n"
    <> "tags: [auth, jwt, security]\n"
    <> "keywords: login, token, session\n"
    <> "updated: 2026-05-29\n"
    <> "summary: JWT rotation with argon2\n"
    <> "---\n"
    <> "# Auth\nbody text here\n"
  let m = memory.parse_frontmatter(raw, "decisions/auth.md")
  m.path |> should.equal("decisions/auth.md")
  m.title |> should.equal("Auth flow")
  m.tags |> should.equal(["auth", "jwt", "security"])
  m.keywords |> should.equal(["login", "token", "session"])
  m.updated |> should.equal("2026-05-29")
  m.summary |> should.equal("JWT rotation with argon2")
}

pub fn parse_frontmatter_none_defaults_test() {
  let raw = "# Heading One\nsome body\n"
  let m = memory.parse_frontmatter(raw, "project/glossary.md")
  m.title |> should.equal("glossary")
  m.tags |> should.equal([])
  m.keywords |> should.equal([])
  m.updated |> should.equal("")
  // summary derived from the first heading
  m.summary |> should.equal("Heading One")
}

pub fn parse_frontmatter_multiline_list_test() {
  let raw = "---\ntitle: T\ntags:\n  - alpha\n  - beta\n---\nbody\n"
  let m = memory.parse_frontmatter(raw, "x.md")
  m.tags |> should.equal(["alpha", "beta"])
}

pub fn summary_falls_back_to_body_text_test() {
  let raw = "just some plain body text without a heading"
  let m = memory.parse_frontmatter(raw, "n.md")
  m.summary |> should.equal("just some plain body text without a heading")
}

// --- select_relevant -------------------------------------------------------

pub fn select_relevant_always_includes_current_test() {
  let index =
    memory.MemoryIndex([
      memory.NoteMeta("tasks/current.md", "Current", [], [], "", "plan"),
      memory.NoteMeta("decisions/x.md", "X", ["foo"], [], "", "s"),
    ])
  let selected = memory.select_relevant(index, task("totally unrelated zzz"), 5)
  list.any(selected, fn(m) { m.path == "tasks/current.md" })
  |> should.be_true
}

pub fn select_relevant_always_includes_handoff_test() {
  let index =
    memory.MemoryIndex([
      memory.NoteMeta("tasks/handoff.md", "Handoff", [], [], "", "steps"),
      memory.NoteMeta("decisions/x.md", "X", ["foo"], [], "", "s"),
    ])
  let selected = memory.select_relevant(index, task("totally unrelated zzz"), 5)
  list.any(selected, fn(m) { m.path == "tasks/handoff.md" })
  |> should.be_true
}

pub fn select_relevant_ranks_by_tag_test() {
  let index =
    memory.MemoryIndex([
      memory.NoteMeta("decisions/auth.md", "Auth", ["auth", "jwt"], [], "", "s"),
      memory.NoteMeta("decisions/db.md", "DB", ["database"], [], "", "s"),
      memory.NoteMeta("project/architecture.md", "Arch", [], [], "", "s"),
    ])
  let paths =
    memory.select_relevant(index, task("how does auth jwt login work"), 5)
    |> list.map(fn(m) { m.path })
  // auth note matches two tags (score 6); architecture wins on its +5 bonus;
  // db has no matching tag/keyword (score 0) and is dropped.
  list.contains(paths, "decisions/auth.md") |> should.be_true
  list.contains(paths, "project/architecture.md") |> should.be_true
  list.contains(paths, "decisions/db.md") |> should.be_false
}

// --- write_note ------------------------------------------------------------

pub fn write_note_atomic_creates_dirs_test() {
  let cfg = tmp_cfg("write")
  let assert Ok(_) = memory.write_note(cfg, "tasks/current.md", "hello plan")

  let assert Ok(content) =
    simplifile.read(cfg.vault_path <> "/tasks/current.md")
  content |> should.equal("hello plan")

  // the temp file must have been renamed away
  simplifile.read(cfg.vault_path <> "/tasks/current.md.tmp")
  |> result.is_error
  |> should.be_true
}

// --- append_session --------------------------------------------------------

pub fn append_session_appends_test() {
  let cfg = tmp_cfg("session")
  let assert Ok(_) = memory.append_session(cfg, "[CODE] first")
  let assert Ok(_) = memory.append_session(cfg, "[PLAN] second")

  let assert Ok(files) =
    simplifile.read_directory(cfg.vault_path <> "/sessions")
  list.length(files) |> should.equal(1)
  let assert [fname] = files
  let assert Ok(content) =
    simplifile.read(cfg.vault_path <> "/sessions/" <> fname)
  string.contains(content, "[CODE] first") |> should.be_true
  string.contains(content, "[PLAN] second") |> should.be_true
}

// --- load_index ------------------------------------------------------------

pub fn load_index_parses_handwritten_test() {
  let cfg = tmp_cfg("loadidx")
  let idx =
    "# Memory Index\n\n## project\n"
    <> "- [[project/architecture]] #stack #core — the stack\n"
    <> "## decisions\n"
    <> "- [[decisions/2026-05-29-auth]] #auth #jwt — jwt rotation\n"
  let assert Ok(_) =
    simplifile.write(to: cfg.vault_path <> "/_INDEX.md", contents: idx)

  let assert Ok(memory.MemoryIndex(notes)) = memory.load_index(cfg)
  list.length(notes) |> should.equal(2)
  let assert Ok(arch) =
    list.find(notes, fn(m) { m.path == "project/architecture.md" })
  arch.tags |> should.equal(["stack", "core"])
  arch.summary |> should.equal("the stack")
}

// --- rebuild_index round-trip ---------------------------------------------

pub fn rebuild_index_roundtrips_test() {
  let cfg = tmp_cfg("index")
  let assert Ok(_) =
    memory.write_note(
      cfg,
      "project/architecture.md",
      "---\ntitle: Arch\ntags: [stack, core]\nsummary: the stack\n---\n# Arch\n",
    )
  let assert Ok(_) =
    memory.write_note(
      cfg,
      "decisions/2026-05-29-auth.md",
      "---\ntitle: Auth\ntags: [auth, jwt]\nsummary: jwt rotation\n---\nbody\n",
    )
  // these must be excluded from the index
  let assert Ok(_) =
    memory.write_note(
      cfg,
      "decisions/_TEMPLATE.md",
      "---\ntitle: T\n---\ntmpl\n",
    )
  let assert Ok(_) = memory.append_session(cfg, "[CODE] noise")

  let assert Ok(_) = memory.rebuild_index(cfg)

  let assert Ok(memory.MemoryIndex(notes)) = memory.load_index(cfg)
  let paths = list.map(notes, fn(m) { m.path })
  list.contains(paths, "project/architecture.md") |> should.be_true
  list.contains(paths, "decisions/2026-05-29-auth.md") |> should.be_true
  list.contains(paths, "decisions/_TEMPLATE.md") |> should.be_false
  list.any(paths, fn(p) { string.starts_with(p, "sessions/") })
  |> should.be_false

  // tags + summary survive the scan -> render -> parse round-trip
  let assert Ok(auth) =
    list.find(notes, fn(m) { m.path == "decisions/2026-05-29-auth.md" })
  auth.tags |> should.equal(["auth", "jwt"])
  auth.summary |> should.equal("jwt rotation")
}
