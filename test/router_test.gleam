import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import kimi_proxy/config.{type Config, Config}
import kimi_proxy/provider.{Coder, Planner}
import kimi_proxy/router
import kimi_proxy/types.{
  type RouteMode, type Task, Auto, Coding, DirectModel, ForceRole, Planning,
  Question, Task,
}
import simplifile

fn tmp_cfg(name: String, kimi: List(String), sonnet: List(String)) -> Config {
  let vault = "build/test_tmp/router_" <> name
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
    sonnet_cli: sonnet,
    kimi_cli: kimi,
    usage_file: Error(Nil),
    usage_throttle_pct: 90,
  )
}

fn task_with(mode: RouteMode, prompt: String) -> Task {
  Task(
    mode: mode,
    intent: Question,
    user_prompt: prompt,
    history: [],
    task_root: "",
  )
}

/// A task carrying an oo7 task-root path, as ask.sh sends it.
fn task_in(mode: RouteMode, prompt: String, root: String) -> Task {
  Task(..task_with(mode, prompt), task_root: root)
}

// --- classify (rule-based, no LLM) -----------------------------------------

pub fn classify_force_role_test() {
  router.classify(task_with(ForceRole(Planner), "x")) |> should.equal(Planning)
  router.classify(task_with(ForceRole(Coder), "x")) |> should.equal(Coding)
}

pub fn classify_auto_planning_test() {
  router.classify(task_with(Auto, "help design the system"))
  |> should.equal(Planning)
  router.classify(task_with(Auto, "let's design the api"))
  |> should.equal(Planning)
}

pub fn classify_auto_coding_test() {
  router.classify(task_with(Auto, "write a login function"))
  |> should.equal(Coding)
  router.classify(task_with(Auto, "please fix the bug")) |> should.equal(Coding)
}

pub fn classify_auto_question_test() {
  router.classify(task_with(Auto, "how are you today"))
  |> should.equal(Question)
}

// --- handle (e2e: temp vault + mock CLI via /bin/sh -c) --------------------

pub fn handle_coding_returns_answer_and_logs_test() {
  let cfg =
    tmp_cfg("code", ["/bin/sh", "-c", "echo CODER_OUTPUT"], [
      "/bin/sh",
      "-c",
      "echo PLAN",
    ])
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_with(Auto, "write a login function"))
  string.contains(out, "CODER_OUTPUT") |> should.be_true

  // [CODE] is appended to today's session log
  let assert Ok(files) =
    simplifile.read_directory(cfg.vault_path <> "/sessions")
  let assert [f] = files
  let assert Ok(log) = simplifile.read(cfg.vault_path <> "/sessions/" <> f)
  string.contains(log, "[CODE]") |> should.be_true
}

pub fn handle_planning_writes_current_md_test() {
  let cfg =
    tmp_cfg("plan", ["/bin/sh", "-c", "echo CODE"], [
      "/bin/sh",
      "-c",
      "echo PLANNED_BY_SONNET",
    ])
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_with(ForceRole(Planner), "design auth"))
  string.contains(out, "PLANNED_BY_SONNET") |> should.be_true

  let assert Ok(content) =
    simplifile.read(cfg.vault_path <> "/tasks/current.md")
  string.contains(content, "PLANNED_BY_SONNET") |> should.be_true
}

pub fn handle_directmodel_bypasses_vault_test() {
  let cfg =
    tmp_cfg("direct", ["/bin/sh", "-c", "echo X"], ["/bin/sh", "-c", "echo Y"])
  // no DEDALUS_KEY -> run_model fails -> Error; the vault is never touched
  router.handle(cfg, task_with(DirectModel("gemini-3-pro"), "hi"))
  |> result.is_error
  |> should.be_true
  simplifile.read(cfg.vault_path <> "/tasks/current.md")
  |> result.is_error
  |> should.be_true
}

// --- oo7 task context injection ---------------------------------------------

/// A fake oo7 task folder with the marker TASK.md + rules + one document.
fn tmp_task_dir(name: String) -> String {
  let root = "build/test_tmp/router_task_" <> name
  let _ = simplifile.delete(root)
  let assert Ok(_) = simplifile.create_directory_all(root)
  let assert Ok(_) =
    simplifile.write(root <> "/TASK.md", "goal: FIX_THE_LOGIN_LOOP")
  let assert Ok(_) =
    simplifile.write(root <> "/AGENTS.md", "rule: NEVER_FORCE_PUSH_SHARED")
  let assert Ok(_) =
    simplifile.write(root <> "/DESIGN.md", "design: USE_STATE_MACHINE")
  root
}

// The mock CLI echoes the prompt it receives ($0 — via_cli appends the prompt
// as the argument after `-c <script>`), so the assertion sees the full
// rendered context exactly as a real model would.
const echo_prompt = ["/bin/sh", "-c", "echo \"$0\""]

pub fn handle_coding_injects_task_context_test() {
  let cfg = tmp_cfg("taskctx", echo_prompt, echo_prompt)
  let root = tmp_task_dir("code")
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_in(Auto, "write a login function", root))
  string.contains(out, "[TASK]") |> should.be_true
  string.contains(out, "FIX_THE_LOGIN_LOOP") |> should.be_true
  string.contains(out, "[AGENTS]") |> should.be_true
  string.contains(out, "NEVER_FORCE_PUSH_SHARED") |> should.be_true
  string.contains(out, "[TASK FILES]") |> should.be_true
  string.contains(out, "USE_STATE_MACHINE") |> should.be_true
}

pub fn handle_planning_injects_task_context_test() {
  let cfg = tmp_cfg("taskctx_plan", echo_prompt, echo_prompt)
  let root = tmp_task_dir("plan")
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_in(ForceRole(Planner), "design the fix", root))
  string.contains(out, "FIX_THE_LOGIN_LOOP") |> should.be_true
  string.contains(out, "NEVER_FORCE_PUSH_SHARED") |> should.be_true
}

pub fn handle_without_task_root_stays_plain_test() {
  let cfg = tmp_cfg("taskctx_none", echo_prompt, echo_prompt)
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_with(Auto, "write a login function"))
  string.contains(out, "[TASK]") |> should.be_false
  string.contains(out, "[AGENTS]") |> should.be_false
}

pub fn handle_bogus_task_root_degrades_gracefully_test() {
  let cfg = tmp_cfg("taskctx_bogus", echo_prompt, echo_prompt)
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_in(Auto, "write code", "/no/such/dir"))
  string.contains(out, "[TASK]") |> should.be_false
}

// --- planner → coder handoff -------------------------------------------------

const h_start = "<<<HANDOFF_START>>>"

const h_end = "<<<HANDOFF_END>>>"

/// A planner reply: the human-readable plan, then the machine handoff block.
fn plan_with_handoff() -> String {
  "The plan: do X in two phases.\n\n"
  <> h_start
  <> "\nobjective: ship X\nfirst_step: open a.py\nsteps:\n- edit a.py => tests pass\n"
  <> h_end
}

pub fn split_handoff_pure_test() {
  let #(clean, handoff) = router.split_handoff(plan_with_handoff())
  clean |> should.equal("The plan: do X in two phases.")
  string.contains(handoff, "objective: ship X") |> should.be_true
  string.contains(handoff, h_start) |> should.be_false
  router.split_handoff("no block here") |> should.equal(#("no block here", ""))
}

pub fn handle_planning_writes_handoff_into_task_root_test() {
  let cfg =
    tmp_cfg("handoff_task", ["/bin/sh", "-c", "echo CODE"], [
      "/bin/sh",
      "-c",
      "echo \"" <> plan_with_handoff() <> "\"",
    ])
  let root = tmp_task_dir("handoff")
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_in(ForceRole(Planner), "design X", root))

  // markers never reach the user; the plan text does
  string.contains(out, h_start) |> should.be_false
  string.contains(out, "The plan: do X in two phases.") |> should.be_true

  // HANDOFF.md landed next to the task's TASK.md, carrying the block
  let assert Ok(handoff) = simplifile.read(root <> "/HANDOFF.md")
  string.contains(handoff, "objective: ship X") |> should.be_true

  // the plan is thread-scoped: PLAN.md next to TASK.md, marker-free — and
  // the vault's global tasks/current.md slot is left untouched
  let assert Ok(plan_doc) = simplifile.read(root <> "/PLAN.md")
  string.contains(plan_doc, "The plan: do X in two phases.") |> should.be_true
  string.contains(plan_doc, h_start) |> should.be_false
  simplifile.read(cfg.vault_path <> "/tasks/current.md")
  |> result.is_error
  |> should.be_true
}

pub fn handle_planning_handoff_vault_fallback_test() {
  // no task_root → the handoff still lands, in the vault's tasks/handoff.md
  let cfg =
    tmp_cfg("handoff_vault", ["/bin/sh", "-c", "echo CODE"], [
      "/bin/sh",
      "-c",
      "echo \"" <> plan_with_handoff() <> "\"",
    ])
  let assert Ok(_) =
    router.handle(cfg, task_with(ForceRole(Planner), "design X"))
  let assert Ok(handoff) =
    simplifile.read(cfg.vault_path <> "/tasks/handoff.md")
  string.contains(handoff, "objective: ship X") |> should.be_true
}

pub fn handle_coding_receives_handoff_section_test() {
  // a coding turn in a task folder with a HANDOFF.md gets a [HANDOFF] section
  let cfg = tmp_cfg("handoff_code", echo_prompt, echo_prompt)
  let root = tmp_task_dir("handoff_code")
  let assert Ok(_) =
    simplifile.write(root <> "/HANDOFF.md", "first_step: OPEN_A_PY")
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_in(Auto, "write the code", root))
  string.contains(out, "[HANDOFF]") |> should.be_true
  string.contains(out, "OPEN_A_PY") |> should.be_true
}

// --- explicit remember (จำ:) + thread-scoped memory --------------------------

pub fn remember_body_detects_directives_test() {
  router.remember_body("จำ: ใช้ bcrypt เสมอ")
  |> should.equal(Ok("ใช้ bcrypt เสมอ"))
  router.remember_body("  Remember: always use uv  ")
  |> should.equal(Ok("always use uv"))
  router.remember_body("write a login function") |> should.equal(Error(Nil))
}

pub fn handle_remember_writes_note_without_llm_test() {
  let cfg =
    tmp_cfg("remember", ["/bin/sh", "-c", "echo CODER_RAN"], [
      "/bin/sh",
      "-c",
      "echo PLANNER_RAN",
    ])
  let assert Ok(router.Handled(out, intent, _, _)) =
    router.handle(cfg, task_with(Auto, "จำ: ทีมใช้ pnpm เท่านั้น ห้าม npm"))
  intent |> should.equal("remember")
  string.contains(out, "notes/") |> should.be_true
  // no LLM was consulted — the proxy answered by itself
  string.contains(out, "CODER_RAN") |> should.be_false
  string.contains(out, "PLANNER_RAN") |> should.be_false
  // the note holds exactly what was said, and the index was rebuilt
  let assert Ok([file]) = simplifile.read_directory(cfg.vault_path <> "/notes")
  let assert Ok(note) = simplifile.read(cfg.vault_path <> "/notes/" <> file)
  string.contains(note, "ทีมใช้ pnpm เท่านั้น ห้าม npm") |> should.be_true
  let assert Ok(index) = simplifile.read(cfg.vault_path <> "/_INDEX.md")
  string.contains(index, "notes/") |> should.be_true
}

pub fn handle_remember_empty_body_saves_nothing_test() {
  let cfg =
    tmp_cfg("remember_empty", ["/bin/sh", "-c", "echo X"], [
      "/bin/sh",
      "-c",
      "echo Y",
    ])
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_with(Auto, "จำ:"))
  string.contains(out, "nothing to remember") |> should.be_true
  simplifile.read_directory(cfg.vault_path <> "/notes")
  |> result.is_error
  |> should.be_true
}

pub fn is_correction_detects_thai_test() {
  router.is_correction("ไม่ใช่ ต้องใช้ bcrypt") |> should.be_true
  router.is_correction("ผิดแล้ว แก้ใหม่ทั้งไฟล์") |> should.be_true
  router.is_correction("เข้าใจผิดนะ อันนี้คือ Svelte 5") |> should.be_true
  router.is_correction("เขียนฟังก์ชัน login ให้หน่อย") |> should.be_false
}

pub fn handle_coding_task_plan_shadows_vault_plan_test() {
  // a task-scoped PLAN.md wins; the vault's global current.md (possibly
  // another thread's plan) must not leak into this thread's context
  let cfg = tmp_cfg("plan_shadow", echo_prompt, echo_prompt)
  let root = tmp_task_dir("plan_shadow")
  let assert Ok(_) = simplifile.write(root <> "/PLAN.md", "TASK_SCOPED_PLAN")
  let assert Ok(_) =
    simplifile.create_directory_all(cfg.vault_path <> "/tasks")
  let assert Ok(_) =
    simplifile.write(cfg.vault_path <> "/tasks/current.md", "GLOBAL_PLAN")
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_in(Auto, "write the code", root))
  string.contains(out, "TASK_SCOPED_PLAN") |> should.be_true
  string.contains(out, "GLOBAL_PLAN") |> should.be_false
}

pub fn handle_planning_without_block_leaves_no_handoff_test() {
  // planner that emits no block: nothing written, nothing broken
  let cfg =
    tmp_cfg("handoff_none", ["/bin/sh", "-c", "echo CODE"], [
      "/bin/sh",
      "-c",
      "echo JUST_A_PLAN",
    ])
  let root = tmp_task_dir("handoff_none")
  let assert Ok(_) =
    router.handle(cfg, task_in(ForceRole(Planner), "design X", root))
  simplifile.is_file(root <> "/HANDOFF.md") |> should.equal(Ok(False))
}

// --- correction capture (spec §20) ------------------------------------------

const start_marker = "<<<DECISION_START>>>"

const end_marker = "<<<DECISION_END>>>"

/// A well-formed reply: visible answer, then one decision block.
fn reply_with_block() -> String {
  "Use bcrypt for the hash.\n\n"
  <> start_marker
  <> "\ntitle: Use bcrypt not md5\n"
  <> "tags: [auth, hashing]\n"
  <> "keywords: bcrypt, md5, password\n"
  <> "summary: md5 was used for passwords; bcrypt is required\n\n"
  <> "## What went wrong\nPasswords were hashed with md5.\n\n"
  <> "## Rule going forward\nAlways hash passwords with bcrypt.\n"
  <> end_marker
}

// -- is_correction (rule-based, no LLM) --

pub fn is_correction_detects_keywords_test() {
  router.is_correction("no, that's wrong — use bcrypt") |> should.be_true
  router.is_correction("Actually, the API returns a list") |> should.be_true
  router.is_correction("use uv instead of pip") |> should.be_true
  router.is_correction("stop doing that in every reply") |> should.be_true
  router.is_correction("don't do that again") |> should.be_true
}

pub fn is_correction_negative_test() {
  router.is_correction("write a login function") |> should.be_false
  router.is_correction("help design the system") |> should.be_false
  router.is_correction("how are you today") |> should.be_false
}

// -- extract_decisions (pure) --

pub fn extract_decisions_strips_and_returns_block_test() {
  let #(clean, blocks) = router.extract_decisions(reply_with_block())
  clean |> should.equal("Use bcrypt for the hash.")
  let assert [block] = blocks
  string.contains(block, "title: Use bcrypt not md5") |> should.be_true
  string.contains(block, "Rule going forward") |> should.be_true
  string.contains(block, start_marker) |> should.be_false
}

pub fn extract_decisions_no_markers_passthrough_test() {
  router.extract_decisions("plain answer, no block")
  |> should.equal(#("plain answer, no block", []))
}

pub fn extract_decisions_dangling_start_never_leaks_test() {
  // an unterminated block is malformed model output: drop the tail, no block
  let #(clean, blocks) =
    router.extract_decisions(
      "the answer\n\n" <> start_marker <> "\ntitle: half a block",
    )
  clean |> should.equal("the answer")
  blocks |> should.equal([])
}

pub fn extract_decisions_text_after_block_is_kept_test() {
  let #(clean, blocks) =
    router.extract_decisions(
      "before\n\n"
      <> start_marker
      <> "\ntitle: t\n\nbody\n"
      <> end_marker
      <> "\n\nafter",
    )
  clean |> should.equal("before\n\nafter")
  blocks |> list.length |> should.equal(1)
}

// -- handle e2e: correction turns write a decisions/ note --

pub fn handle_coding_correction_writes_decision_note_test() {
  let cfg =
    tmp_cfg(
      "corr_code",
      ["/bin/sh", "-c", "echo \"" <> reply_with_block() <> "\""],
      ["/bin/sh", "-c", "echo PLAN"],
    )
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(
      cfg,
      task_with(Auto, "that's wrong, use bcrypt instead of md5"),
    )

  // the user-facing answer survives; the markers never leak
  string.contains(out, "Use bcrypt for the hash.") |> should.be_true
  string.contains(out, start_marker) |> should.be_false
  string.contains(out, end_marker) |> should.be_false

  // the note landed under decisions/ with frontmatter + body
  let assert Ok([file]) =
    simplifile.read_directory(cfg.vault_path <> "/decisions")
  string.contains(file, "use-bcrypt-not-md5") |> should.be_true
  let assert Ok(note) = simplifile.read(cfg.vault_path <> "/decisions/" <> file)
  string.starts_with(note, "---\n") |> should.be_true
  string.contains(note, "title: Use bcrypt not md5") |> should.be_true
  string.contains(note, "updated: ") |> should.be_true
  string.contains(note, "Always hash passwords with bcrypt.") |> should.be_true

  // the index was rebuilt and now lists the decision
  let assert Ok(index) = simplifile.read(cfg.vault_path <> "/_INDEX.md")
  string.contains(index, "use-bcrypt-not-md5") |> should.be_true
}

pub fn handle_planning_correction_strips_markers_from_plan_test() {
  let plan_reply =
    "Revised plan: bcrypt everywhere.\n\n"
    <> start_marker
    <> "\ntitle: Plan assumed md5\n\n## What went wrong\nmd5.\n\n"
    <> "## Rule going forward\nPlan for bcrypt.\n"
    <> end_marker
  let cfg =
    tmp_cfg("corr_plan", ["/bin/sh", "-c", "echo CODE"], [
      "/bin/sh",
      "-c",
      "echo \"" <> plan_reply <> "\"",
    ])
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(
      cfg,
      task_with(Auto, "actually that design is wrong, redo the auth plan"),
    )
  string.contains(out, start_marker) |> should.be_false

  // tasks/current.md gets the cleaned plan, never the raw markers
  let assert Ok(current) =
    simplifile.read(cfg.vault_path <> "/tasks/current.md")
  string.contains(current, "Revised plan: bcrypt everywhere.")
  |> should.be_true
  string.contains(current, start_marker) |> should.be_false

  // and the decision note exists
  let assert Ok([_]) = simplifile.read_directory(cfg.vault_path <> "/decisions")
}

pub fn handle_normal_prompt_never_writes_decision_test() {
  let cfg =
    tmp_cfg("corr_none", ["/bin/sh", "-c", "echo PLAIN_ANSWER"], [
      "/bin/sh",
      "-c",
      "echo PLAN",
    ])
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_with(Auto, "write a login function"))
  string.contains(out, "PLAIN_ANSWER") |> should.be_true
  // no correction flag -> no decisions/ directory is ever created
  simplifile.read_directory(cfg.vault_path <> "/decisions")
  |> result.is_error
  |> should.be_true
}

pub fn handle_correction_without_block_still_answers_test() {
  // flagged turn, but the model chose not to emit a note: answer unchanged,
  // nothing written — a missing block never fails the response
  let cfg =
    tmp_cfg("corr_noblock", ["/bin/sh", "-c", "echo JUST_THE_FIX"], [
      "/bin/sh",
      "-c",
      "echo PLAN",
    ])
  let assert Ok(router.Handled(out, _, _, _)) =
    router.handle(cfg, task_with(Auto, "that's wrong, fix the hash"))
  string.contains(out, "JUST_THE_FIX") |> should.be_true
  simplifile.read_directory(cfg.vault_path <> "/decisions")
  |> result.is_error
  |> should.be_true
}
