import gleam/list
import gleam/string
import gleeunit/should
import kimi_proxy/context
import kimi_proxy/memory
import kimi_proxy/tokens
import kimi_proxy/types.{AssembledContext, ContextBlock}

fn coding_task(prompt: String) -> types.Task {
  types.Task(
    mode: types.Auto,
    intent: types.Coding,
    user_prompt: prompt,
    history: [],
    task_root: "",
  )
}

fn note(path: String, body: String) -> memory.Note {
  memory.Note(meta: memory.NoteMeta(path, "", [], [], "", ""), body: body)
}

// --- build_blocks ----------------------------------------------------------

pub fn build_blocks_labels_and_priorities_test() {
  let notes = [
    note("tasks/current.md", "the plan"),
    note("project/conventions.md", "snake_case"),
    note("project/architecture.md", "beam"),
    note("decisions/2026-05-29-auth.md", "jwt rotation"),
    note("project/glossary.md", "terms"),
  ]
  let blocks = context.build_blocks(notes, coding_task("write code"))

  let assert Ok(user) = list.find(blocks, fn(b) { b.label == "USER" })
  user.priority |> should.equal(1)
  user.content |> should.equal("write code")
  user.est_tokens |> should.equal(tokens.estimate("write code"))

  let assert Ok(plan) = list.find(blocks, fn(b) { b.label == "PLAN" })
  plan.priority |> should.equal(1)

  let assert Ok(conv) = list.find(blocks, fn(b) { b.label == "CONVENTIONS" })
  conv.priority |> should.equal(2)

  let assert Ok(arch) = list.find(blocks, fn(b) { b.label == "ARCHITECTURE" })
  arch.priority |> should.equal(2)

  list.any(blocks, fn(b) {
    string.starts_with(b.label, "DECISION") && b.priority == 3
  })
  |> should.be_true

  list.any(blocks, fn(b) {
    string.starts_with(b.label, "REFERENCE") && b.priority == 4
  })
  |> should.be_true
}

// --- fit -------------------------------------------------------------------

pub fn fit_keeps_within_budget_and_orders_test() {
  // original order deliberately shuffled to exercise the (priority, order) sort
  let blocks = [
    ContextBlock("CONVENTIONS", "c", 2, 50),
    ContextBlock("DECISION:x", "d", 3, 30),
    ContextBlock("USER", "u", 1, 20),
    ContextBlock("PLAN", "p", 1, 50),
    ContextBlock("ARCHITECTURE", "a", 2, 60),
  ]
  let ctx = context.fit(blocks, 120)
  // sorted: USER(20), PLAN(50), CONVENTIONS(50), ARCHITECTURE(60), DECISION(30)
  // accumulate to 120: USER+PLAN+CONVENTIONS; ARCHITECTURE and DECISION dropped
  list.map(ctx.blocks, fn(b) { b.label })
  |> should.equal(["USER", "PLAN", "CONVENTIONS"])
  ctx.total_tokens |> should.equal(120)
  ctx.dropped |> should.equal(["ARCHITECTURE", "DECISION:x"])
}

pub fn fit_always_keeps_user_even_over_budget_test() {
  let blocks = [
    ContextBlock("USER", "big", 1, 500),
    ContextBlock("PLAN", "p", 1, 10),
  ]
  let ctx = context.fit(blocks, 100)
  list.map(ctx.blocks, fn(b) { b.label }) |> should.equal(["USER"])
  ctx.total_tokens |> should.equal(500)
  ctx.dropped |> should.equal(["PLAN"])
}

// --- render ----------------------------------------------------------------

/// The coder system line (handoff-aware) — kept in one place for the exact
/// render assertions below.
const coder_system = "[SYSTEM]\nYou are the coder. When a HANDOFF section is"
  <> " present, execute it exactly — do its first_step first, complete the"
  <> " steps in order, verify each step's done-check, and respect its"
  <> " constraints and out_of_scope; the PLAN is background and the HANDOFF"
  <> " wins on any conflict. Without a HANDOFF, follow the PLAN. Always follow"
  <> " CONVENTIONS."

pub fn render_orders_sections_and_skips_empty_test() {
  let ctx =
    AssembledContext(
      blocks: [
        ContextBlock("USER", "do X", 1, 0),
        ContextBlock("CONVENTIONS", "snake_case", 2, 0),
        ContextBlock("ARCHITECTURE", "beam", 2, 0),
        ContextBlock("PLAN", "step 1", 1, 0),
        ContextBlock("DECISION:auth", "jwt", 3, 0),
      ],
      total_tokens: 0,
      dropped: [],
    )
  let out = context.render(ctx, coding_task("do X"))
  let expected =
    coder_system
    <> "\n\n"
    <> "[CONVENTIONS]\nsnake_case\n\n"
    <> "[ARCHITECTURE]\nbeam\n\n"
    <> "[PLAN]\nstep 1\n\n"
    <> "[RELEVANT DECISIONS]\njwt\n\n"
    <> "[USER]\ndo X"
  out |> should.equal(expected)
}

pub fn render_task_sections_in_order_test() {
  // oo7 task blocks slot in around the vault sections: AGENTS with the rules
  // up top, TASK beside PLAN, TASKREF documents before generic REFERENCE.
  let ctx =
    AssembledContext(
      blocks: [
        ContextBlock("USER", "do X", 1, 0),
        ContextBlock("TASK", "fix login", 1, 0),
        ContextBlock("AGENTS", "no force push", 2, 0),
        ContextBlock("CONVENTIONS", "snake_case", 2, 0),
        ContextBlock("TASKREF:design", "the design", 3, 0),
        ContextBlock("REFERENCE:glossary", "terms", 4, 0),
      ],
      total_tokens: 0,
      dropped: [],
    )
  let out = context.render(ctx, coding_task("do X"))
  let expected =
    coder_system
    <> "\n\n"
    <> "[AGENTS]\nno force push\n\n"
    <> "[CONVENTIONS]\nsnake_case\n\n"
    <> "[TASK]\nfix login\n\n"
    <> "[TASK FILES]\nthe design\n\n"
    <> "[REFERENCE]\nterms\n\n"
    <> "[USER]\ndo X"
  out |> should.equal(expected)
}

pub fn render_handoff_between_plan_and_decisions_test() {
  let ctx =
    AssembledContext(
      blocks: [
        ContextBlock("USER", "do X", 1, 0),
        ContextBlock("PLAN", "the plan", 1, 0),
        ContextBlock("HANDOFF", "first_step: open a.py", 1, 0),
        ContextBlock("DECISION:auth", "jwt", 3, 0),
      ],
      total_tokens: 0,
      dropped: [],
    )
  let out = context.render(ctx, coding_task("do X"))
  let expected =
    coder_system
    <> "\n\n"
    <> "[PLAN]\nthe plan\n\n"
    <> "[HANDOFF]\nfirst_step: open a.py\n\n"
    <> "[RELEVANT DECISIONS]\njwt\n\n"
    <> "[USER]\ndo X"
  out |> should.equal(expected)
}

pub fn render_planner_role_test() {
  let task =
    types.Task(
      mode: types.Auto,
      intent: types.Planning,
      user_prompt: "design it",
      history: [],
      task_root: "",
    )
  let ctx =
    AssembledContext(
      blocks: [ContextBlock("USER", "design it", 1, 0)],
      total_tokens: 0,
      dropped: [],
    )
  let out = context.render(ctx, task)
  string.contains(out, "You are the planner.") |> should.be_true
  string.contains(out, "[USER]\ndesign it") |> should.be_true
}
