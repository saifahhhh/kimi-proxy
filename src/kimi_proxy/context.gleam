//// Context assembly (spec §6.4, §10).
////
//// Turns the notes selected for a task into labelled, size-estimated blocks,
//// fits them into a token budget (dropping the least important first while
//// always keeping the user prompt), and renders the survivors into the final
//// prompt string sent to a provider. Pure and deterministic — no IO, no LLM.
////
//// The `ContextBlock` / `AssembledContext` / `Task` types live in
//// `kimi_proxy/types` to avoid import cycles.

import gleam/int
import gleam/list
import gleam/order.{type Order, Eq}
import gleam/string
import kimi_proxy/memory.{type Note}
import kimi_proxy/tokens
import kimi_proxy/types.{
  type AssembledContext, type ContextBlock, type Task, AssembledContext,
  ContextBlock,
}

// ---------------------------------------------------------------------------
// Building blocks (spec §6.4 priority table)
// ---------------------------------------------------------------------------

/// Build context blocks from the selected notes plus the user prompt. Each note
/// becomes a labelled block with a priority derived from its path; the user
/// prompt becomes the priority-1 "USER" block (appended last so that, among
/// priority-1 blocks, the PLAN sorts ahead of it).
pub fn build_blocks(notes: List(Note), task: Task) -> List(ContextBlock) {
  let note_blocks = list.map(notes, note_to_block)
  list.append(note_blocks, [block("USER", task.user_prompt, 1)])
}

fn note_to_block(note: Note) -> ContextBlock {
  let #(label, priority) = classify(note.meta.path)
  block(label, note.body, priority)
}

/// Construct a block, trimming the content and estimating its token size.
fn block(label: String, content: String, priority: Int) -> ContextBlock {
  let trimmed = string.trim(content)
  ContextBlock(
    label: label,
    content: trimmed,
    priority: priority,
    est_tokens: tokens.estimate(trimmed),
  )
}

/// Map a note's path to its render label and fit priority (spec §6.4).
fn classify(path: String) -> #(String, Int) {
  case path {
    "tasks/current.md" -> #("PLAN", 1)
    "tasks/handoff.md" -> #("HANDOFF", 1)
    "project/conventions.md" -> #("CONVENTIONS", 2)
    "project/architecture.md" -> #("ARCHITECTURE", 2)
    _ ->
      case string.starts_with(path, "decisions/") {
        True -> #("DECISION:" <> slug(path), 3)
        False -> #("REFERENCE:" <> slug(path), 4)
      }
  }
}

fn slug(path: String) -> String {
  let base = case list.last(string.split(path, "/")) {
    Ok(b) -> b
    Error(Nil) -> path
  }
  case string.ends_with(base, ".md") {
    True -> string.drop_end(base, 3)
    False -> base
  }
}

// ---------------------------------------------------------------------------
// Fitting to budget (spec §10 — exact algorithm)
// ---------------------------------------------------------------------------

/// Fit blocks into `budget`: sort by (priority asc, original order asc) then
/// accumulate until adding the next block would exceed the budget, dropping the
/// rest by label. The "USER" block is always kept, even if it alone exceeds the
/// budget — we never throw here; the router logs that abnormal case (spec §10).
pub fn fit(blocks: List(ContextBlock), budget: Int) -> AssembledContext {
  let sorted =
    blocks
    |> list.index_map(fn(b, i) { #(i, b) })
    |> list.sort(by_priority_then_order)
    |> list.map(fn(pair) { pair.1 })

  let #(kept, total, dropped) =
    list.fold(sorted, #([], 0, []), fn(state, b) {
      let #(kept, total, dropped) = state
      case b.label == "USER" {
        True -> #([b, ..kept], total + b.est_tokens, dropped)
        False ->
          case total + b.est_tokens <= budget {
            True -> #([b, ..kept], total + b.est_tokens, dropped)
            False -> #(kept, total, [b.label, ..dropped])
          }
      }
    })

  AssembledContext(
    blocks: list.reverse(kept),
    total_tokens: total,
    dropped: list.reverse(dropped),
  )
}

fn by_priority_then_order(
  a: #(Int, ContextBlock),
  b: #(Int, ContextBlock),
) -> Order {
  let #(ia, ba) = a
  let #(ib, bb) = b
  case int.compare(ba.priority, bb.priority) {
    Eq -> int.compare(ia, ib)
    other -> other
  }
}

// ---------------------------------------------------------------------------
// Rendering (spec §6.4 format)
// ---------------------------------------------------------------------------

/// Render the assembled context into the final prompt string. Sections appear
/// in the fixed spec order and empty sections are skipped (spec §6.4).
pub fn render(ctx: AssembledContext, task: Task) -> String {
  let system =
    "[SYSTEM]\nYou are the "
    <> role_name(task)
    <> ". When a HANDOFF section is present, execute it exactly — do its"
    <> " first_step first, complete the steps in order, verify each step's"
    <> " done-check, and respect its constraints and out_of_scope; the PLAN is"
    <> " background and the HANDOFF wins on any conflict. Without a HANDOFF,"
    <> " follow the PLAN. Always follow CONVENTIONS."

  let sections =
    [
      section("AGENTS", exact(ctx.blocks, "AGENTS")),
      section("CONVENTIONS", exact(ctx.blocks, "CONVENTIONS")),
      section("ARCHITECTURE", exact(ctx.blocks, "ARCHITECTURE")),
      section("TASK", exact(ctx.blocks, "TASK")),
      section("PLAN", exact(ctx.blocks, "PLAN")),
      section("HANDOFF", exact(ctx.blocks, "HANDOFF")),
      section("RELEVANT DECISIONS", prefixed(ctx.blocks, "DECISION")),
      section("TASK FILES", prefixed(ctx.blocks, "TASKREF")),
      section("REFERENCE", prefixed(ctx.blocks, "REFERENCE")),
      section("USER", exact(ctx.blocks, "USER")),
    ]
    |> list.filter_map(fn(s) { s })

  [system, ..sections] |> string.join("\n\n")
}

/// Derive the addressed role from the task's intent (spec §9: Question routes to
/// the Coder, planning to the Planner).
fn role_name(task: Task) -> String {
  case task.intent {
    types.Planning -> "planner"
    types.Coding -> "coder"
    types.Question -> "coder"
  }
}

/// Build a `[HEADER]` section from its block contents, or `Error` when empty so
/// the caller can skip it.
fn section(header: String, contents: List(String)) -> Result(String, Nil) {
  case contents {
    [] -> Error(Nil)
    _ -> Ok("[" <> header <> "]\n" <> string.join(contents, "\n\n"))
  }
}

fn exact(blocks: List(ContextBlock), label: String) -> List(String) {
  blocks
  |> list.filter(fn(b) { b.label == label })
  |> list.map(fn(b) { b.content })
}

fn prefixed(blocks: List(ContextBlock), prefix: String) -> List(String) {
  blocks
  |> list.filter(fn(b) { string.starts_with(b.label, prefix) })
  |> list.map(fn(b) { b.content })
}
