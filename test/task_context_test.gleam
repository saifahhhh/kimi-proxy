import gleam/list
import gleam/string
import gleeunit/should
import kimi_proxy/task_context
import simplifile

/// Build a fake oo7 task folder under build/test_tmp/ mirroring the real
/// layout: TASK.md + AGENTS.md (+ CLAUDE.md twin), supporting docs, a hidden
/// dir, and a worktree marked by a `.git` file whose markdown must not leak.
fn tmp_task(name: String) -> String {
  let root = "build/test_tmp/task_" <> name
  let _ = simplifile.delete(root)
  let assert Ok(_) = simplifile.create_directory_all(root <> "/docs/specs")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/.agents")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/fi-backend")
  let assert Ok(_) = simplifile.write(root <> "/TASK.md", "# the task body")
  let assert Ok(_) = simplifile.write(root <> "/AGENTS.md", "# the rules")
  let assert Ok(_) = simplifile.write(root <> "/CLAUDE.md", "# the rules")
  let assert Ok(_) = simplifile.write(root <> "/DESIGN.md", "# the design")
  let assert Ok(_) =
    simplifile.write(root <> "/docs/specs/plan-a.md", "# spec a")
  let assert Ok(_) = simplifile.write(root <> "/.agents/hidden.md", "# hidden")
  let assert Ok(_) =
    simplifile.write(root <> "/fi-backend/.git", "gitdir: elsewhere")
  let assert Ok(_) =
    simplifile.write(root <> "/fi-backend/README.md", "# repo readme")
  root
}

fn labels(root: String) -> List(String) {
  task_context.load_blocks(root) |> list.map(fn(b) { b.label })
}

pub fn load_blocks_labels_and_priorities_test() {
  let blocks = task_context.load_blocks(tmp_task("basic"))

  let assert Ok(task) = list.find(blocks, fn(b) { b.label == "TASK" })
  task.priority |> should.equal(1)
  task.content |> should.equal("# the task body")

  let assert Ok(agents) = list.find(blocks, fn(b) { b.label == "AGENTS" })
  agents.priority |> should.equal(2)

  let assert Ok(design) =
    list.find(blocks, fn(b) { b.label == "TASKREF:DESIGN" })
  design.priority |> should.equal(3)
  design.content |> should.equal("# the design")

  list.any(blocks, fn(b) { b.label == "TASKREF:plan-a" }) |> should.be_true
}

pub fn load_blocks_skips_twins_hidden_and_worktrees_test() {
  let labels = labels(tmp_task("skips"))
  // CLAUDE.md is a symlink twin of AGENTS.md → exactly one AGENTS block, no ref
  list.filter(labels, fn(l) { l == "AGENTS" }) |> list.length |> should.equal(1)
  list.any(labels, fn(l) { string.contains(l, "CLAUDE") }) |> should.be_false
  // .agents/ is hidden, fi-backend/ carries a .git marker → both invisible
  list.any(labels, fn(l) { string.contains(l, "hidden") }) |> should.be_false
  list.any(labels, fn(l) { string.contains(l, "README") }) |> should.be_false
}

pub fn load_blocks_follows_directory_symlinks_test() {
  let root = tmp_task("symlink")
  let shared = "build/test_tmp/task_symlink_shared_roles"
  let _ = simplifile.delete(shared)
  let assert Ok(_) = simplifile.create_directory_all(shared)
  let assert Ok(_) = simplifile.write(shared <> "/TEAMLEAD.md", "# team lead")
  // a task's roles/ is a symlink to the shared ../../roles — must be followed
  let assert Ok(_) =
    simplifile.create_symlink("../task_symlink_shared_roles", root <> "/roles")
  labels(root)
  |> list.any(fn(l) { l == "TASKREF:TEAMLEAD" })
  |> should.be_true
}

pub fn load_blocks_handoff_priority_one_no_taskref_test() {
  let root = tmp_task("handoff")
  let assert Ok(_) = simplifile.write(root <> "/HANDOFF.md", "objective: o")
  let blocks = task_context.load_blocks(root)
  let assert Ok(handoff) = list.find(blocks, fn(b) { b.label == "HANDOFF" })
  handoff.priority |> should.equal(1)
  handoff.content |> should.equal("objective: o")
  // loaded once, with its own label — never doubled as a TASKREF document
  list.any(blocks, fn(b) { b.label == "TASKREF:HANDOFF" }) |> should.be_false
}

pub fn write_handoff_roundtrip_test() {
  let root = tmp_task("handoff_write")
  let assert Ok(_) =
    task_context.write_handoff(root, "# HANDOFF\n\nobjective: ship it\n")
  let assert Ok(content) = simplifile.read(root <> "/HANDOFF.md")
  string.contains(content, "objective: ship it") |> should.be_true
}

pub fn write_handoff_refuses_non_task_dir_test() {
  let root = "build/test_tmp/task_handoff_bogus"
  let _ = simplifile.delete(root)
  let assert Ok(_) = simplifile.create_directory_all(root)
  // no TASK.md marker → refuse, and never create the file
  task_context.write_handoff(root, "x") |> should.be_error
  simplifile.is_file(root <> "/HANDOFF.md") |> should.equal(Ok(False))
}

pub fn load_blocks_empty_root_test() {
  task_context.load_blocks("") |> should.equal([])
}

pub fn load_blocks_without_task_md_marker_test() {
  let root = "build/test_tmp/task_nomarker"
  let _ = simplifile.delete(root)
  let assert Ok(_) = simplifile.create_directory_all(root)
  let assert Ok(_) = simplifile.write(root <> "/DESIGN.md", "# design")
  // no TASK.md → not a task folder → nothing is injected
  task_context.load_blocks(root) |> should.equal([])
}
