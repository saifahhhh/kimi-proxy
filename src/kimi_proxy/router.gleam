//// Orchestration — the heart of the system (spec §6.6).
////
//// Classify a task, assemble the relevant memory context under a token budget,
//// dispatch to the right backend, and persist what should be remembered. All
//// control decisions are made here in Gleam, never by an LLM (spec §1 golden
//// rule).

import birl
import gleam/list
import gleam/result
import gleam/string
import kimi_proxy/cache
import kimi_proxy/config.{type Config}
import kimi_proxy/context
import kimi_proxy/memory.{type Note}
import kimi_proxy/provider.{type LlmError, Coder, Planner}
import kimi_proxy/task_context
import kimi_proxy/train
import kimi_proxy/types.{
  type ContextBlock, type Intent, type Task, type Turn, Auto, Coding,
  DirectModel, ForceRole, Planning, Question, Task,
}

const planning_keywords = ["design", "architect", "plan", "structure", "spec"]

const coding_keywords = [
  "write", "code", "implement", "refactor", "fix", "bug", "function",
]

// Correction detection is a flag alongside the intent, not a new Intent — a
// turn can be both a correction and a fresh planning/coding request (spec §20.1).
// A false positive only adds an instruction the model is told it may ignore.
const correction_keywords = [
  "wrong", "actually", "instead", "don't do that", "do not do that",
  "stop doing", "incorrect", "mistake", "not what i asked", "should have",
  // Thai — the team corrects in Thai; the original English-only list left the
  // whole capture hook asleep for real usage. Same false-positive contract:
  // a wrong trigger only appends an instruction the model may ignore.
  "ไม่ใช่", "ผิดแล้ว", "ไม่ถูกต้อง", "ที่จริงแล้ว", "จริงๆแล้ว", "จริง ๆ แล้ว",
  "เข้าใจผิด", "อย่าทำแบบนั้น", "เลิกทำ", "ไม่ได้ขอ", "เอาใหม่", "แก้ใหม่", "ทำใหม่",
]

// --- explicit remember (สั่งให้จำ) -------------------------------------------
// A prompt starting with a remember directive is persisted straight into the
// vault by the proxy — deterministic, instant, no LLM call (golden rule:
// control stays in Gleam). The note text is exactly what the user typed.

const remember_prefixes = ["จำ:", "จำไว้:", "remember:"]

// IMPORTANT: ask for the plan as plain markdown and explicitly forbid writing
// files / using tools. Mentioning a filename here made the Claude CLI try its
// Write tool (emitting a "please approve permission" preamble). The proxy itself
// persists the result to tasks/current.md (router.remember_plan).
const planning_instruction = "Reply with a phased markdown plan only (sections: Goal, Plan (phased), Constraints, Done checklist). Do not write or edit any files. Do not call any tools — return the plan text only.\n\nAfter the plan, also emit a machine-executable handoff for the coder agent, wrapped exactly between these markers, nothing else on those lines:\n\n<<<HANDOFF_START>>>\nobjective: <one sentence — the outcome>\nfirst_step: <the exact first action the coder takes>\nfiles: <concrete files/paths to touch, comma-separated, or 'unknown'>\nsteps:\n- <imperative step> => <how the coder verifies it is done>\nconstraints:\n- <must / never rules for this work>\nout_of_scope:\n- <things the coder must NOT do now>\n<<<HANDOFF_END>>>\n\nThe handoff must be executable without reading the plan: name concrete files, commands, and checks. The proxy stores it and shows it to the coder — do not mention the markers anywhere else."

// --- correction capture (spec §20) ------------------------------------------

const decision_start = "<<<DECISION_START>>>"

const decision_end = "<<<DECISION_END>>>"

// --- planner → coder handoff (the anti-drift channel) ------------------------
// The Planner emits a machine-executable handoff block alongside the plan (one
// LLM call — no extra latency). The proxy persists it and the coder receives it
// as a priority-1 [HANDOFF] section that overrides the prose PLAN, so the coder
// executes steps instead of re-interpreting a human-oriented document.

const handoff_start = "<<<HANDOFF_START>>>"

const handoff_end = "<<<HANDOFF_END>>>"

// How much of the prior assistant answer to quote back as correction context.
// Sized in graphemes and kept small on purpose: it is appended after
// context.fit, so it must never be able to blow the budget (spec §20.3).
const prior_answer_limit = 1500

// Self-improvement instruction (correction capture): the router appends this
// to a role's prompt only when a rule-based classifier detects the user is
// correcting a prior answer — the decision to persist anything is never left
// to the model (golden rule: control stays in Gleam).
const correction_instruction = "The user's message appears to correct something "
  <> "you (or an earlier session) previously did. After answering their "
  <> "current request, also produce a decision note so future sessions do "
  <> "not repeat the mistake.\n\n"
  <> "Only emit a note if the user actually stated a correction — never "
  <> "invent one. If unsure, skip it.\n\n"
  <> "Wrap it exactly between these markers, nothing else on those lines:\n\n"
  <> "<<<DECISION_START>>>\n"
  <> "title: <3-6 word title>\n"
  <> "tags: [<2-4 lowercase single-word tags>]\n"
  <> "keywords: <comma-separated search terms>\n"
  <> "summary: <one sentence: what was wrong, what to do instead>\n\n"
  <> "## What went wrong\n"
  <> "<1-2 factual sentences, no blame>\n\n"
  <> "## Rule going forward\n"
  <> "<an imperative instruction, e.g. \"Always X\" / \"Never Y\">\n"
  <> "<<<DECISION_END>>>\n\n"
  <> "Do not write or edit files, do not call tools — return text only, the "
  <> "proxy persists it. Keep it under 120 words, written for a future "
  <> "reader with zero memory of this conversation. Emit one block per "
  <> "distinct correction."

/// A handled task: the reply plus the mode facts a client may display —
/// which intent the router classified, which role ran, and which backend
/// actually served (CLI vs API fallback).
pub type Handled {
  Handled(content: String, intent: String, role: String, via: String)
}

/// Orchestrate a task end to end (spec §6.6 algorithm).
pub fn handle(cfg: Config, task: Task) -> Result(Handled, LlmError) {
  case task.mode {
    // DirectModel bypasses memory + pipeline entirely (spec §9).
    DirectModel(model) ->
      provider.run_model(cfg, model, task.user_prompt)
      |> result.map(fn(ans) {
        Handled(ans.content, "direct", "direct", ans.via)
      })
    _ ->
      case remember_body(task.user_prompt) {
        Ok(body) -> Ok(handle_remember(cfg, body))
        Error(Nil) -> {
          let index = cache.resolve_index(cfg)
          let task = Task(..task, intent: classify(task))
          case task.intent {
            Planning -> handle_planning(cfg, index, task)
            _ -> handle_coding(cfg, index, task)
          }
        }
      }
  }
}

/// The text after a remember directive ("จำ: …" / "remember: …"), or Error
/// when the prompt is not a remember command. Pure — public for tests.
pub fn remember_body(prompt: String) -> Result(String, Nil) {
  let trimmed = string.trim(prompt)
  let low = string.lowercase(trimmed)
  remember_prefixes
  |> list.find_map(fn(prefix) {
    case string.starts_with(low, prefix) {
      True ->
        Ok(string.trim(string.drop_start(trimmed, string.length(prefix))))
      False -> Error(Nil)
    }
  })
}

/// Save an explicit remember note into `notes/` (title = first line; the
/// filename reuses train.note_path, so Thai titles keep Thai filenames and
/// path traversal stays impossible). Replies with where it landed — the whole
/// turn never touches an LLM.
fn handle_remember(cfg: Config, body: String) -> Handled {
  let reply = fn(text) { Handled(text, "remember", "proxy", "vault") }
  case body, cfg.enable_memory_write {
    "", _ -> reply("nothing to remember — ใช้: จำ: <สิ่งที่อยากให้จำ>")
    _, False ->
      reply("vault writes are disabled (ENABLE_MEMORY_WRITE=false) — not saved")
    _, True -> {
      let title = first_line(body)
      case train.note_path("notes", title) {
        Error(msg) -> reply("could not save: " <> msg)
        Ok(rel) -> {
          let content =
            "---\ntitle: "
            <> title
            <> "\nupdated: "
            <> birl.to_naive_date_string(birl.now())
            <> "\n---\n\n"
            <> string.trim(body)
            <> "\n"
          case memory.write_note(cfg, rel, content) {
            Error(e) -> reply("could not save: " <> e)
            Ok(_) -> {
              let _ = memory.rebuild_index(cfg)
              log_session(cfg, "[REMEMBER] " <> rel)
              reply("✓ จำแล้ว → " <> rel <> " (มีผลทันทีทุก request ถัดไป)")
            }
          }
        }
      }
    }
  }
}

fn intent_name(intent: Intent) -> String {
  case intent {
    Planning -> "planning"
    Coding -> "coding"
    Question -> "question"
  }
}

/// Rule-based intent classifier — no LLM (spec §6.6).
pub fn classify(task: Task) -> Intent {
  case task.mode {
    ForceRole(Planner) -> Planning
    ForceRole(Coder) -> Coding
    DirectModel(_) -> Question
    Auto -> classify_prompt(task.user_prompt)
  }
}

fn classify_prompt(prompt: String) -> Intent {
  let low = string.lowercase(prompt)
  case contains_any(low, planning_keywords) {
    True -> Planning
    False ->
      case contains_any(low, coding_keywords) {
        True -> Coding
        False -> Question
      }
  }
}

/// Planning phase: produce a phased plan with the Planner and persist it as the
/// current task. Ends here — the user reviews, then asks to code (spec §9).
fn handle_planning(
  cfg: Config,
  index: memory.MemoryIndex,
  task: Task,
) -> Result(Handled, LlmError) {
  let notes = read_notes(cfg, memory.select_relevant(index, task, 6))
  let blocks =
    merge_blocks(
      task_context.load_blocks(task.task_root),
      context.build_blocks(notes, task),
    )
  let ctx = context.fit(blocks, cfg.planner_context_budget)
  let plan_prompt =
    context.render(ctx, task)
    <> "\n\n"
    <> planning_instruction
    <> correction_suffix(task)
  use ans <- result.try(provider.run_role(cfg, Planner, plan_prompt))
  let plan = capture_decisions(cfg, task, ans.content)
  let #(plan, handoff) = split_handoff(plan)
  remember_plan(cfg, task, plan)
  remember_handoff(cfg, task, handoff)
  Ok(Handled(plan, intent_name(task.intent), "planner", ans.via))
}

/// Coding / Question phase: answer with the Coder using memory context. Coding
/// turns are logged to the session; Sonnet is NOT invoked here (spec §15.4).
fn handle_coding(
  cfg: Config,
  index: memory.MemoryIndex,
  task: Task,
) -> Result(Handled, LlmError) {
  let notes = read_notes(cfg, memory.select_relevant(index, task, 8))
  let blocks =
    merge_blocks(
      task_context.load_blocks(task.task_root),
      context.build_blocks(notes, task),
    )
  let ctx = context.fit(blocks, cfg.coder_context_budget)
  use ans <- result.try(provider.run_role(
    cfg,
    Coder,
    context.render(ctx, task) <> correction_suffix(task),
  ))
  let answer = capture_decisions(cfg, task, ans.content)
  case task.intent == Coding && cfg.enable_memory_write {
    True -> log_session(cfg, "[CODE] " <> first_line(task.user_prompt))
    False -> Nil
  }
  Ok(Handled(answer, intent_name(task.intent), "coder", ans.via))
}

/// Persist a plan where the coder will find it (best-effort: a memory write
/// failure never fails the response — spec §12). With an oo7 task the plan is
/// THREAD-SCOPED — `<task_root>/PLAN.md` next to TASK.md, so parallel tasks
/// stop clobbering one global slot; without a task it stays the vault's
/// `tasks/current.md` as before (1 task = 1 thread of memory).
fn remember_plan(cfg: Config, task: Task, plan: String) -> Nil {
  case cfg.enable_memory_write {
    False -> Nil
    True -> {
      case task.task_root != "" {
        True -> {
          let _ = task_context.write_plan(task.task_root, to_current_md(plan))
          Nil
        }
        False -> {
          let _ =
            memory.write_note(cfg, "tasks/current.md", to_current_md(plan))
          let _ = memory.rebuild_index(cfg)
          Nil
        }
      }
      log_session(cfg, "[PLAN] " <> first_line(task.user_prompt))
    }
  }
}

/// Task-scoped blocks shadow their vault twins: when the task folder carries
/// its own PLAN / HANDOFF, the vault's global `tasks/current.md` /
/// `tasks/handoff.md` (possibly another thread's) are dropped from the
/// context, so threads can never contaminate each other.
fn merge_blocks(
  task_blocks: List(ContextBlock),
  note_blocks: List(ContextBlock),
) -> List(ContextBlock) {
  let shadowed =
    ["PLAN", "HANDOFF"]
    |> list.filter(fn(label) {
      list.any(task_blocks, fn(b) { b.label == label })
    })
  list.append(
    task_blocks,
    list.filter(note_blocks, fn(b) { !list.contains(shadowed, b.label) }),
  )
}

fn log_session(cfg: Config, line: String) -> Nil {
  let _ = memory.append_session(cfg, line)
  Nil
}

// ---------------------------------------------------------------------------
// Correction capture (spec §20)
// ---------------------------------------------------------------------------

/// Rule-based correction detector — same shape as the intent classifier, no
/// LLM (spec §20.1). Checked as a flag alongside the intent: the turn's normal
/// planning/coding handling still runs either way.
pub fn is_correction(prompt: String) -> Bool {
  contains_any(string.lowercase(prompt), correction_keywords)
}

/// The prompt fragment appended when the turn is flagged as a correction:
/// the capture instruction plus, when the request carried one, the last
/// assistant turn — the vault alone does not contain the specific prior
/// answer being corrected (spec §20.3).
fn correction_suffix(task: Task) -> String {
  case is_correction(task.user_prompt) {
    False -> ""
    True ->
      "\n\n" <> correction_instruction <> prior_answer_fragment(task.history)
  }
}

fn prior_answer_fragment(history: List(Turn)) -> String {
  history
  |> list.filter(fn(t) { t.role == "assistant" })
  |> list.last
  |> result.map(fn(t) {
    "\n\n[PREVIOUS ANSWER]\nThe answer being corrected was:\n"
    <> clip(t.content, prior_answer_limit)
  })
  |> result.unwrap("")
}

/// Post-process a flagged turn's reply: persist any decision blocks to
/// `decisions/` and strip the markers so they never reach the user. Best
/// effort throughout — a malformed or missing block, or a failed write, never
/// fails the response (spec §20.5). Unflagged turns pass through untouched, so
/// marker-like text a user quoted themselves is never eaten.
fn capture_decisions(cfg: Config, task: Task, reply: String) -> String {
  case is_correction(task.user_prompt) {
    False -> reply
    True -> {
      let #(clean, blocks) = extract_decisions(reply)
      case blocks != [] && cfg.enable_memory_write {
        True -> {
          list.each(blocks, write_decision(cfg, _))
          let _ = memory.rebuild_index(cfg)
          Nil
        }
        False -> Nil
      }
      clean
    }
  }
}

/// Split a reply into (user-facing text, decision blocks). Pure. A start
/// marker without its end marker is malformed model output: the dangling tail
/// is dropped rather than shown, so markers never leak (spec §20.4).
pub fn extract_decisions(reply: String) -> #(String, List(String)) {
  extract_blocks(reply, decision_start, decision_end)
}

/// Split a reply into (clean text, marker-delimited blocks) for any marker
/// pair. Pure; shared by decision capture and the planner→coder handoff.
/// Dangling-start behaviour matches extract_decisions above.
pub fn extract_blocks(
  reply: String,
  start: String,
  end: String,
) -> #(String, List(String)) {
  case string.split_once(reply, start) {
    Error(Nil) -> #(reply, [])
    Ok(#(before, rest)) ->
      case string.split_once(rest, end) {
        Error(Nil) -> #(string.trim_end(before), [])
        Ok(#(block, after)) -> {
          let #(clean_after, more) = extract_blocks(after, start, end)
          let clean = case string.trim(clean_after) {
            "" -> string.trim_end(before)
            tail -> string.trim_end(before) <> "\n\n" <> tail
          }
          case string.trim(block) {
            "" -> #(clean, more)
            b -> #(clean, [b, ..more])
          }
        }
      }
  }
}

/// Pull the handoff block out of a planner reply: (clean plan, handoff or "").
/// When the model emits several blocks the last one wins (it reflects the
/// final state of the plan). Pure — public for tests.
pub fn split_handoff(reply: String) -> #(String, String) {
  let #(clean, blocks) = extract_blocks(reply, handoff_start, handoff_end)
  case list.last(blocks) {
    Ok(block) -> #(clean, block)
    Error(Nil) -> #(clean, "")
  }
}

/// Persist the planner's handoff where the coder's context loader will find
/// it: `<task_root>/HANDOFF.md` when the request carries an oo7 task (the
/// handoff then lives next to TASK.md, scoped to that task), else the vault's
/// `tasks/handoff.md`. Best-effort, same contract as remember_plan — and a
/// missing block simply leaves the previous handoff in place.
fn remember_handoff(cfg: Config, task: Task, handoff: String) -> Nil {
  case handoff == "" || !cfg.enable_memory_write {
    True -> Nil
    False -> {
      let content = "# HANDOFF — planner → coder\n\n" <> handoff <> "\n"
      case task.task_root != "" {
        True ->
          case task_context.write_handoff(task.task_root, content) {
            Ok(_) ->
              log_session(cfg, "[HANDOFF] " <> task.task_root <> "/HANDOFF.md")
            Error(_) -> Nil
          }
        False ->
          case memory.write_note(cfg, "tasks/handoff.md", content) {
            Ok(_) -> {
              let _ = memory.rebuild_index(cfg)
              log_session(cfg, "[HANDOFF] tasks/handoff.md")
            }
            Error(_) -> Nil
          }
      }
    }
  }
}

fn write_decision(cfg: Config, block: String) -> Nil {
  let date = birl.to_naive_date_string(birl.now())
  let #(rel_path, content) = decision_note(block, date)
  case memory.write_note(cfg, rel_path, content) {
    Ok(_) -> log_session(cfg, "[DECISION] " <> rel_path)
    Error(_) -> Nil
  }
}

/// Turn a raw decision block into a `decisions/<date>-<slug>.md` note (spec
/// §20.2): the block's metadata lines become frontmatter (plus `updated:`) and
/// the rest becomes the body. Total — a block with no recognisable metadata is
/// still written, with the whole block as body and a fallback title.
fn decision_note(block: String, date: String) -> #(String, String) {
  let #(header, body) = split_decision_header(block)
  let title = case header_value(header, "title") {
    "" -> "correction"
    t -> t
  }
  let fm = case header {
    "" -> "title: " <> title
    h -> h
  }
  let content =
    "---\n"
    <> fm
    <> "\nupdated: "
    <> date
    <> "\n---\n\n"
    <> string.trim(body)
    <> "\n"
  #("decisions/" <> date <> "-" <> slugify(title) <> ".md", content)
}

/// Split a block into its metadata header (the lines before the first blank
/// line, only when they actually carry a `title:`) and the markdown body.
fn split_decision_header(block: String) -> #(String, String) {
  case string.split_once(block, "\n\n") {
    Ok(#(h, b)) ->
      case string.contains(string.lowercase(h), "title:") {
        True -> #(string.trim(h), b)
        False -> #("", block)
      }
    Error(Nil) -> #("", block)
  }
}

fn header_value(header: String, key: String) -> String {
  header
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.split_once(line, ":") {
      Ok(#(k, v)) ->
        case string.lowercase(string.trim(k)) == key {
          True -> Ok(string.trim(v))
          False -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
  |> list.first
  |> result.unwrap("")
}

/// Lowercase, keep [a-z0-9] and dash the rest, collapse runs. Non-latin
/// titles collapse to nothing and fall back, so the filename is always safe.
fn slugify(s: String) -> String {
  let slug =
    s
    |> string.lowercase
    |> string.to_graphemes
    |> list.map(fn(g) {
      case string.contains("abcdefghijklmnopqrstuvwxyz0123456789", g) {
        True -> g
        False -> "-"
      }
    })
    |> string.concat
    |> collapse_dashes
    |> trim_dashes
  case slug {
    "" -> "correction"
    _ -> slug
  }
}

fn collapse_dashes(s: String) -> String {
  case string.contains(s, "--") {
    True -> collapse_dashes(string.replace(s, "--", "-"))
    False -> s
  }
}

fn trim_dashes(s: String) -> String {
  let s = case string.starts_with(s, "-") {
    True -> string.drop_start(s, 1)
    False -> s
  }
  case string.ends_with(s, "-") {
    True -> string.drop_end(s, 1)
    False -> s
  }
}

fn clip(s: String, max: Int) -> String {
  case string.length(s) > max {
    True -> string.slice(s, 0, max) <> "…"
    False -> s
  }
}

/// Read the selected notes, dropping any that can't be read (spec §12: a bad
/// note never breaks the request).
fn read_notes(cfg: Config, metas: List(memory.NoteMeta)) -> List(Note) {
  list.filter_map(metas, fn(m) {
    case memory.read_note(cfg, m.path) {
      Ok(note) -> Ok(note)
      Error(_) -> Error(Nil)
    }
  })
}

fn contains_any(haystack: String, needles: List(String)) -> Bool {
  list.any(needles, fn(n) { string.contains(haystack, n) })
}

fn first_line(s: String) -> String {
  case string.split(s, "\n") {
    [first, ..] -> first
    [] -> s
  }
}

/// If the planner already returned frontmatter, keep it; otherwise wrap with a
/// minimal frontmatter header (spec §19.5).
fn to_current_md(plan: String) -> String {
  case string.starts_with(string.trim_start(plan), "---") {
    True -> plan
    False ->
      "---\ntitle: Current task\nupdated: "
      <> birl.to_naive_date_string(birl.now())
      <> "\n---\n\n"
      <> plan
  }
}
