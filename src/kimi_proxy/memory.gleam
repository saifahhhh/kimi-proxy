//// Obsidian vault I/O and indexing (spec §6.3).
////
//// The persistence layer for the system's external "brain": it reads and writes
//// markdown notes, parses YAML-ish frontmatter, maintains the `_INDEX.md`
//// map-of-content, and selects the notes relevant to a task without reading
//// every file.
////
//// Logging policy: functions here surface problems through their `Result` error
//// strings and never log directly, so the module stays free of debug output
//// (spec §A.10). The router (Phase 5) decides what to log when it sees an error.
//// The pure helpers `parse_frontmatter` and `select_relevant` are total: they
//// fall back to sensible defaults rather than failing.

import birl
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq}
import gleam/result
import gleam/string
import kimi_proxy/config.{type Config}
import kimi_proxy/types.{type Task}
import simplifile

// ---------------------------------------------------------------------------
// Types (spec §4.3)
// ---------------------------------------------------------------------------

/// Metadata parsed from a note's frontmatter (or defaulted when absent).
pub type NoteMeta {
  NoteMeta(
    path: String,
    title: String,
    tags: List(String),
    keywords: List(String),
    updated: String,
    summary: String,
  )
}

/// A full note: metadata plus its markdown body (frontmatter stripped).
pub type Note {
  Note(meta: NoteMeta, body: String)
}

/// The whole-vault index: a list of note metadata.
pub type MemoryIndex {
  MemoryIndex(notes: List(NoteMeta))
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

/// Load the vault index by parsing `_INDEX.md` (spec §5.3). On any read failure
/// returns an `Error`; the caller (router) then falls back to `scan_vault`.
pub fn load_index(cfg: Config) -> Result(MemoryIndex, String) {
  case simplifile.read(from: cfg.vault_path <> "/_INDEX.md") {
    Ok(raw) -> Ok(MemoryIndex(parse_index(raw)))
    Error(e) -> Error("cannot read _INDEX.md: " <> simplifile.describe_error(e))
  }
}

/// Read a single note by its vault-relative path, parsing its frontmatter.
pub fn read_note(cfg: Config, rel_path: String) -> Result(Note, String) {
  case simplifile.read(from: cfg.vault_path <> "/" <> rel_path) {
    Ok(raw) ->
      Ok(Note(
        meta: parse_frontmatter(raw, rel_path),
        body: strip_frontmatter(raw),
      ))
    Error(e) ->
      Error(
        "cannot read note " <> rel_path <> ": " <> simplifile.describe_error(e),
      )
  }
}

/// Fallback index builder: recursively scan the vault, read each indexable note
/// and parse its frontmatter. Excludes `sessions/` logs and files whose name
/// starts with `_` (e.g. `_INDEX.md`, `_TEMPLATE.md`). Spec §6.3 / §7.4.
pub fn scan_vault(cfg: Config) -> Result(MemoryIndex, String) {
  case simplifile.get_files(in: cfg.vault_path) {
    Error(e) -> Error("cannot scan vault: " <> simplifile.describe_error(e))
    Ok(full_paths) ->
      Ok(MemoryIndex(
        full_paths
        |> list.map(to_rel(cfg.vault_path, _))
        |> list.filter(is_indexable)
        |> list.filter_map(fn(rel) {
          case simplifile.read(from: cfg.vault_path <> "/" <> rel) {
            Ok(raw) -> Ok(parse_frontmatter(raw, rel))
            Error(_) -> Error(Nil)
          }
        }),
      ))
  }
}

/// Count every markdown note in the vault (sessions and `_`-files included,
/// hidden directories like `.obsidian` excluded) — the number the Train page
/// reports. Total, returns 0 when the vault cannot be read.
pub fn count_notes(cfg: Config) -> Int {
  case simplifile.get_files(in: cfg.vault_path) {
    Error(_) -> 0
    Ok(files) ->
      files
      |> list.filter(fn(f) {
        string.ends_with(f, ".md") && !string.contains(f, "/.")
      })
      |> list.length
  }
}

// ---------------------------------------------------------------------------
// Frontmatter parsing (spec §5.2)
// ---------------------------------------------------------------------------

/// Parse frontmatter into `NoteMeta`. Total — never fails. When frontmatter is
/// absent or a field is missing, sensible defaults are used (title from the
/// filename, empty tags/keywords, summary derived from the body).
pub fn parse_frontmatter(raw: String, path: String) -> NoteMeta {
  let #(maybe_fm, body) = split_frontmatter(raw)
  let entries = case maybe_fm {
    Some(fm) -> parse_entries(fm)
    None -> []
  }
  let title = case scalar(entries, "title") {
    "" -> filename_no_ext(path)
    t -> t
  }
  let summary = case scalar(entries, "summary") {
    "" -> derive_summary(body)
    s -> s
  }
  NoteMeta(
    path: path,
    title: title,
    tags: list_field(entries, "tags"),
    keywords: list_field(entries, "keywords"),
    updated: scalar(entries, "updated"),
    summary: summary,
  )
}

/// Split raw content into optional frontmatter lines and the body. Frontmatter
/// is the block between the first pair of `---` delimiters at the top of file.
fn split_frontmatter(raw: String) -> #(Option(List(String)), String) {
  case string.split(raw, "\n") {
    [first, ..rest] ->
      case string.trim(first) == "---" {
        True ->
          case take_until_delim(rest, []) {
            Ok(#(fm, body_lines)) -> #(Some(fm), string.join(body_lines, "\n"))
            // unterminated frontmatter -> treat as if there were none
            Error(Nil) -> #(None, raw)
          }
        False -> #(None, raw)
      }
    [] -> #(None, raw)
  }
}

fn take_until_delim(
  lines: List(String),
  acc: List(String),
) -> Result(#(List(String), List(String)), Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] ->
      case string.trim(line) == "---" {
        True -> Ok(#(list.reverse(acc), rest))
        False -> take_until_delim(rest, [line, ..acc])
      }
  }
}

fn strip_frontmatter(raw: String) -> String {
  let #(_, body) = split_frontmatter(raw)
  body
}

/// A frontmatter key with its inline value and any attached YAML list items.
type Entry {
  Entry(key: String, inline: String, items: List(String))
}

/// Parse frontmatter lines into entries. A `key: value` line starts a new
/// entry; a following `- item` line attaches to the current entry (YAML list).
fn parse_entries(lines: List(String)) -> List(Entry) {
  lines
  |> list.fold([], fn(acc, line) {
    let trimmed = string.trim(line)
    case string.starts_with(trimmed, "- "), acc {
      True, [current, ..rest] -> [
        Entry(..current, items: [string.drop_start(trimmed, 2), ..current.items]),
        ..rest
      ]
      _, _ ->
        case string.split_once(line, ":") {
          Ok(#(k, v)) -> [
            Entry(
              key: string.lowercase(string.trim(k)),
              inline: string.trim(v),
              items: [],
            ),
            ..acc
          ]
          Error(Nil) -> acc
        }
    }
  })
  |> list.reverse
  |> list.map(fn(e) { Entry(..e, items: list.reverse(e.items)) })
}

fn scalar(entries: List(Entry), key: String) -> String {
  case list.find(entries, fn(e) { e.key == key }) {
    Ok(e) -> e.inline
    Error(Nil) -> ""
  }
}

fn list_field(entries: List(Entry), key: String) -> List(String) {
  case list.find(entries, fn(e) { e.key == key }) {
    Error(Nil) -> []
    Ok(e) -> to_list(e.inline, e.items)
  }
}

/// Turn a frontmatter list value into a list of strings, supporting the inline
/// `[a, b]` form, the bare comma form `a, b`, and the multi-line `- a` form.
fn to_list(inline: String, items: List(String)) -> List(String) {
  case inline {
    "" -> clean(items)
    "[]" -> []
    _ ->
      case string.starts_with(inline, "[") {
        True ->
          inline
          |> string.replace("[", "")
          |> string.replace("]", "")
          |> string.split(",")
          |> clean
        False ->
          inline
          |> string.split(",")
          |> clean
      }
  }
}

fn clean(xs: List(String)) -> List(String) {
  xs
  |> list.map(string.trim)
  |> list.filter(fn(x) { x != "" })
}

/// Derive a summary when none is given: first markdown heading, else the first
/// 120 characters of the trimmed body (spec §5.2).
fn derive_summary(body: String) -> String {
  let trimmed = string.trim(body)
  let lines = string.split(trimmed, "\n")
  case
    list.find(lines, fn(l) { string.starts_with(string.trim_start(l), "#") })
  {
    Ok(heading) -> heading |> string.trim |> drop_hashes |> string.trim
    Error(Nil) -> truncate(trimmed, 120)
  }
}

fn drop_hashes(s: String) -> String {
  case string.starts_with(s, "#") {
    True -> drop_hashes(string.drop_start(s, 1))
    False -> s
  }
}

fn truncate(s: String, max: Int) -> String {
  case string.length(s) > max {
    True -> string.slice(s, 0, max)
    False -> s
  }
}

fn filename_no_ext(path: String) -> String {
  let base = path |> string.split("/") |> list.last |> result.unwrap(path)
  drop_md(base)
}

fn drop_md(path: String) -> String {
  case string.ends_with(path, ".md") {
    True -> string.drop_end(path, 3)
    False -> path
  }
}

// ---------------------------------------------------------------------------
// Index (_INDEX.md) parsing (spec §5.3)
// ---------------------------------------------------------------------------

/// Parse `_INDEX.md` lines of the form `- [[path]] #tag #tag — summary`.
fn parse_index(raw: String) -> List(NoteMeta) {
  raw
  |> string.split("\n")
  |> list.filter_map(parse_index_line)
}

fn parse_index_line(line: String) -> Result(NoteMeta, Nil) {
  let trimmed = string.trim(line)
  case string.starts_with(trimmed, "- [[") {
    False -> Error(Nil)
    True -> {
      use link <- result.try(between(trimmed, "[[", "]]"))
      let path = ensure_md(string.trim(link))
      let after = case string.split_once(trimmed, "]]") {
        Ok(#(_, rest)) -> rest
        Error(Nil) -> ""
      }
      let #(meta_part, summary) = case string.split_once(after, "—") {
        Ok(#(m, s)) -> #(m, string.trim(s))
        Error(Nil) -> #(after, "")
      }
      Ok(NoteMeta(
        path: path,
        title: filename_no_ext(path),
        tags: extract_hashtags(meta_part),
        keywords: [],
        updated: "",
        summary: summary,
      ))
    }
  }
}

fn between(s: String, open: String, close: String) -> Result(String, Nil) {
  use #(_, rest) <- result.try(string.split_once(s, open))
  use #(mid, _) <- result.try(string.split_once(rest, close))
  Ok(mid)
}

fn extract_hashtags(s: String) -> List(String) {
  s
  |> string.split(" ")
  |> list.filter_map(fn(tok) {
    let t = string.trim(tok)
    case string.starts_with(t, "#") {
      True -> Ok(string.drop_start(t, 1))
      False -> Error(Nil)
    }
  })
  |> list.filter(fn(t) { t != "" })
}

fn ensure_md(p: String) -> String {
  case string.ends_with(p, ".md") {
    True -> p
    False -> p <> ".md"
  }
}

// ---------------------------------------------------------------------------
// Relevance selection (spec §6.3 — the heart of "don't read everything")
// ---------------------------------------------------------------------------

/// Select the notes relevant to `task` using only index metadata (no body
/// reads). Scores by tag/keyword overlap with the prompt plus fixed bonuses for
/// the always-important notes, keeps positive scores, returns the top `limit`,
/// and always includes `tasks/current.md` when it exists.
pub fn select_relevant(
  index: MemoryIndex,
  task: Task,
  limit: Int,
) -> List(NoteMeta) {
  let MemoryIndex(notes) = index
  let words = extract_keywords(task.user_prompt)

  let top =
    notes
    |> list.map(fn(m) { #(m, score_note(m, words)) })
    |> list.filter(fn(pair) { pair.1 > 0 })
    |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
    |> list.take(limit)
    |> list.map(fn(pair) { pair.0 })

  ensure_current(top, notes)
}

fn score_note(m: NoteMeta, words: List(String)) -> Int {
  let tag_hits = count_matches(m.tags, words) * 3
  let kw_hits = count_matches(m.keywords, words) * 2
  let bonus = case m.path {
    "project/architecture.md" | "project/conventions.md" -> 5
    "tasks/current.md" -> 4
    _ -> 0
  }
  tag_hits + kw_hits + bonus
}

/// Count how many of `terms` (lowercased) appear as a token in `words`.
fn count_matches(terms: List(String), words: List(String)) -> Int {
  terms
  |> list.filter(fn(t) { list.contains(words, string.lowercase(t)) })
  |> list.length
}

/// Notes that must always ride along when they exist: the current plan (spec
/// §6.3 step 4) and the planner→coder handoff (the anti-drift channel).
const always_included = ["tasks/current.md", "tasks/handoff.md"]

/// Guarantee the always-included notes are present (spec §6.3 step 4).
fn ensure_current(
  selected: List(NoteMeta),
  all: List(NoteMeta),
) -> List(NoteMeta) {
  list.fold(always_included, selected, fn(sel, path) {
    case list.any(sel, fn(m) { m.path == path }) {
      True -> sel
      False ->
        case list.find(all, fn(m) { m.path == path }) {
          Ok(note) -> list.append(sel, [note])
          Error(Nil) -> sel
        }
    }
  })
}

/// Tokenise a prompt into lowercase keywords: split on non-alphanumeric
/// separators, drop very short tokens and stopwords, dedupe (spec §6.3 step 1,
/// §19.2 inline stopword list).
fn extract_keywords(prompt: String) -> List(String) {
  prompt
  |> string.lowercase
  |> tokenize
  |> list.filter(fn(w) { string.length(w) > 1 && !is_stopword(w) })
  |> list.unique
}

fn tokenize(s: String) -> List(String) {
  separators
  |> list.fold(s, fn(acc, sep) { string.replace(acc, sep, " ") })
  |> string.split(" ")
  |> list.map(string.trim)
  |> list.filter(fn(w) { w != "" })
}

const separators = [
  "\n", "\t", "\r", ",", ".", "!", "?", ";", ":", "(", ")", "[", "]", "{", "}",
  "\"", "'", "/", "\\", "|", "#", "*", "`", "<", ">", "=", "+", "~", "@", "&",
  "^", "%", "$", "-", "_",
]

const stopwords = [
  "the", "an", "is", "are", "to", "of", "and", "or", "in", "on", "for", "with",
  "it", "this", "that", "my", "me", "we", "you", "please", "can", "help", "how",
  "do",
]

fn is_stopword(w: String) -> Bool {
  list.contains(stopwords, w)
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// Write a note atomically: write a temp file then rename it into place, so
/// Obsidian never observes a half-written file (spec §6.3, §15.7). Parent
/// directories are created automatically. A `rel_path` that resolves to an
/// existing directory fails at the rename step (spec edge case).
pub fn write_note(
  cfg: Config,
  rel_path: String,
  content: String,
) -> Result(Nil, String) {
  let full = cfg.vault_path <> "/" <> rel_path
  let tmp = full <> ".tmp"
  use _ <- result.try(
    simplifile.create_directory_all(parent_dir(full))
    |> result.map_error(describe_fs),
  )
  use _ <- result.try(
    simplifile.write(to: tmp, contents: content)
    |> result.map_error(describe_fs),
  )
  simplifile.rename(at: tmp, to: full)
  |> result.map_error(describe_fs)
}

/// Append a line to today's session log (`sessions/YYYY-MM-DD.md`), creating the
/// directory if needed. Session logs are append-only ground truth (spec §11).
pub fn append_session(cfg: Config, line: String) -> Result(Nil, String) {
  let dir = cfg.vault_path <> "/sessions"
  use _ <- result.try(
    simplifile.create_directory_all(dir)
    |> result.map_error(describe_fs),
  )
  simplifile.append(to: dir <> "/" <> today() <> ".md", contents: line <> "\n")
  |> result.map_error(describe_fs)
}

/// Regenerate `_INDEX.md` from a fresh vault scan so it always reflects reality
/// (spec §11, §15.10). The produced file round-trips through `load_index`.
pub fn rebuild_index(cfg: Config) -> Result(Nil, String) {
  use index <- result.try(scan_vault(cfg))
  write_note(cfg, "_INDEX.md", render_index(index))
}

fn render_index(index: MemoryIndex) -> String {
  let MemoryIndex(notes) = index
  let header =
    "# Memory Index\n\n"
    <> "> auto-maintained by kimi_proxy. Regenerated on write — manual edits may be overwritten.\n"
  let body =
    notes
    |> group_by_section
    |> list.map(render_section)
    |> string.join("\n")
  header <> "\n" <> body <> "\n"
}

/// Group notes by top-level directory, ordered project → decisions → tasks →
/// everything else (alphabetical); notes within a section are sorted by path so
/// the output is deterministic.
fn group_by_section(notes: List(NoteMeta)) -> List(#(String, List(NoteMeta))) {
  let grouped =
    list.fold(notes, dict.new(), fn(acc, m) {
      dict.upsert(acc, section_of(m.path), fn(existing) {
        case existing {
          Some(l) -> [m, ..l]
          None -> [m]
        }
      })
    })
  grouped
  |> dict.keys
  |> list.sort(section_order)
  |> list.map(fn(sec) {
    let ms =
      dict.get(grouped, sec)
      |> result.unwrap([])
      |> list.sort(fn(a, b) { string.compare(a.path, b.path) })
    #(sec, ms)
  })
}

fn section_order(a: String, b: String) -> Order {
  case int.compare(section_rank(a), section_rank(b)) {
    Eq -> string.compare(a, b)
    other -> other
  }
}

fn section_rank(s: String) -> Int {
  case s {
    "project" -> 0
    "decisions" -> 1
    "tasks" -> 2
    _ -> 3
  }
}

fn render_section(section: #(String, List(NoteMeta))) -> String {
  let #(name, notes) = section
  let lines = notes |> list.map(render_index_line) |> string.join("\n")
  "## " <> name <> "\n" <> lines <> "\n"
}

fn render_index_line(m: NoteMeta) -> String {
  let link = "[[" <> drop_md(m.path) <> "]]"
  let tags = case m.tags {
    [] -> ""
    ts -> " " <> { ts |> list.map(fn(t) { "#" <> t }) |> string.join(" ") }
  }
  let summary = case string.trim(m.summary) {
    "" -> ""
    s -> " — " <> s
  }
  "- " <> link <> tags <> summary
}

fn section_of(path: String) -> String {
  case string.split_once(path, "/") {
    Ok(#(section, _)) -> section
    Error(Nil) -> "root"
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Strip the vault prefix from a full path to get a vault-relative path.
fn to_rel(vault: String, full: String) -> String {
  case string.split_once(full, vault <> "/") {
    Ok(#("", rest)) -> rest
    _ -> full
  }
}

/// True for notes that belong in the index: `.md` files that are neither
/// session logs nor underscore-prefixed (`_INDEX.md`, `_TEMPLATE.md`).
fn is_indexable(rel: String) -> Bool {
  let base = rel |> string.split("/") |> list.last |> result.unwrap(rel)
  string.ends_with(rel, ".md")
  && !string.starts_with(base, "_")
  && !string.starts_with(rel, "sessions/")
}

fn parent_dir(path: String) -> String {
  let parts = string.split(path, "/")
  parts |> list.take(list.length(parts) - 1) |> string.join("/")
}

fn describe_fs(e: simplifile.FileError) -> String {
  simplifile.describe_error(e)
}

fn today() -> String {
  birl.to_naive_date_string(birl.now())
}
