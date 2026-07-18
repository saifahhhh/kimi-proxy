//// Live oo7 task context (proxy extension).
////
//// When a request carries a `task_root` — the absolute path of an oo7 task
//// folder, detected client-side by walking up to the nearest TASK.md — this
//// module reads that folder's markdown files fresh from disk on every request
//// and turns them into context blocks. Nothing is synced or cached: the files
//// stay owned by oo7 and are always current.
////
//// Priorities mirror the vault scheme in `context.classify`:
////   TASK.md   -> "TASK"           priority 1  (the current unit of work)
////   AGENTS.md -> "AGENTS"         priority 2  (the rules, like CONVENTIONS)
////   *.md      -> "TASKREF:<slug>" priority 3  (supporting documents)
////
//// Scan rules, matched to the real oo7 task layout:
////   - skip dot entries (`.agents/`, `.git/`)
////   - never descend into a directory containing `.git` (a repo worktree —
////     its markdown belongs to that repo, not to the task)
////   - follow directory symlinks (a task's `roles` links to the shared
////     roles/), bounded by a depth cap so a symlink loop cannot hang us
////   - skip CLAUDE.md / GEMINI.md anywhere (oo7 keeps them as symlinks to
////     AGENTS.md, so reading them would inject the same rules twice)
////
//// All reads are best-effort: an unreadable file is skipped, never an error —
//// same contract as the vault (spec §12).

import gleam/list
import gleam/result
import gleam/string
import kimi_proxy/tokens
import kimi_proxy/types.{type ContextBlock, ContextBlock}
import simplifile

/// Filenames never picked up by the recursive scan: the first three are loaded
/// separately with their own labels, the rest are their oo7 symlink twins.
const scan_excluded = [
  "TASK.md", "AGENTS.md", "HANDOFF.md", "CLAUDE.md", "GEMINI.md",
]

/// How deep the scan may recurse below the task root. Real tasks are 3-4
/// levels deep; the cap only exists so a symlink loop terminates.
const max_depth = 6

/// Read a task folder's markdown into context blocks. Returns [] when
/// `task_root` is empty or has no TASK.md (the marker that makes a folder a
/// task) — so a bogus path degrades to the plain no-task behaviour.
pub fn load_blocks(task_root: String) -> List(ContextBlock) {
  case task_root != "" && is_file(task_root <> "/TASK.md") {
    False -> []
    True ->
      list.flatten([
        read_block(task_root, "TASK.md", "TASK", 1),
        // the planner→coder handoff written by router.remember_handoff —
        // priority 1 like the plan: it is the operative instruction set
        read_block(task_root, "HANDOFF.md", "HANDOFF", 1),
        read_block(task_root, "AGENTS.md", "AGENTS", 2),
        list.flat_map(scan(task_root, "", max_depth), fn(rel) {
          read_block(task_root, rel, "TASKREF:" <> slug(rel), 3)
        }),
      ])
  }
}

/// Read one file into a single-block list, or [] when missing/empty.
fn read_block(
  root: String,
  rel: String,
  label: String,
  priority: Int,
) -> List(ContextBlock) {
  case simplifile.read(from: root <> "/" <> rel) {
    Error(_) -> []
    Ok(raw) -> {
      let trimmed = string.trim(raw)
      case trimmed {
        "" -> []
        _ -> [
          ContextBlock(
            label: label,
            content: trimmed,
            priority: priority,
            est_tokens: tokens.estimate(trimmed),
          ),
        ]
      }
    }
  }
}

/// Relative paths of the task's supporting .md files, honouring the scan
/// rules above. Entries are sorted per directory, so the result is
/// deterministic for a given tree.
fn scan(root: String, prefix: String, depth: Int) -> List(String) {
  let dir = join(root, prefix)
  case depth <= 0, simplifile.read_directory(at: dir) {
    True, _ | _, Error(_) -> []
    False, Ok(names) ->
      names
      |> list.sort(string.compare)
      |> list.flat_map(fn(name) {
        let rel = join_rel(prefix, name)
        let path = root <> "/" <> rel
        case string.starts_with(name, ".") {
          True -> []
          False ->
            case is_dir(path) {
              True ->
                case exists(path <> "/.git") {
                  True -> []
                  False -> scan(root, rel, depth - 1)
                }
              False ->
                case
                  string.ends_with(name, ".md")
                  && !list.contains(scan_excluded, name)
                {
                  True -> [rel]
                  False -> []
                }
            }
        }
      })
  }
}

fn join(root: String, prefix: String) -> String {
  case prefix {
    "" -> root
    _ -> root <> "/" <> prefix
  }
}

fn join_rel(prefix: String, name: String) -> String {
  case prefix {
    "" -> name
    _ -> prefix <> "/" <> name
  }
}

fn is_file(path: String) -> Bool {
  case simplifile.is_file(path) {
    Ok(True) -> True
    _ -> False
  }
}

fn is_dir(path: String) -> Bool {
  case simplifile.is_directory(path) {
    Ok(True) -> True
    _ -> False
  }
}

/// True when anything (file or directory) exists at `path` — used for the
/// `.git` worktree marker, which oo7 worktrees carry as a plain file.
fn exists(path: String) -> Bool {
  case simplifile.file_info(path) {
    Ok(_) -> True
    Error(_) -> False
  }
}

/// Write the proxy-owned `HANDOFF.md` into an oo7 task folder (atomic
/// tmp+rename, like memory.write_note). Refuses when the folder is not a task
/// (no TASK.md) so a bogus task_root can never scatter files.
pub fn write_handoff(task_root: String, content: String) -> Result(Nil, String) {
  case task_root != "" && is_file(task_root <> "/TASK.md") {
    False -> Error("not an oo7 task folder: " <> task_root)
    True -> {
      let full = task_root <> "/HANDOFF.md"
      let tmp = full <> ".tmp"
      case simplifile.write(to: tmp, contents: content) {
        Error(e) -> Error(simplifile.describe_error(e))
        Ok(_) ->
          simplifile.rename(at: tmp, to: full)
          |> result.map_error(simplifile.describe_error)
      }
    }
  }
}

/// `docs/a/setup-guide.md` -> `setup-guide` (same rule as context.slug).
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
