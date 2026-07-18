import gleam/list
import gleeunit/should
import kimi_proxy/cache
import kimi_proxy/config.{type Config, Config}
import kimi_proxy/memory
import simplifile

fn tmp_cfg(name: String) -> Config {
  let vault = "build/test_tmp/cache_" <> name
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

pub fn resolve_index_uses_index_file_test() {
  let cfg = tmp_cfg("idx")
  let assert Ok(_) =
    simplifile.write(
      to: cfg.vault_path <> "/_INDEX.md",
      contents: "## project\n- [[project/architecture]] #stack — the stack\n",
    )
  let memory.MemoryIndex(notes) = cache.resolve_index(cfg)
  list.length(notes) |> should.equal(1)
}

pub fn resolve_index_falls_back_to_scan_test() {
  let cfg = tmp_cfg("scan")
  let assert Ok(_) =
    memory.write_note(
      cfg,
      "project/architecture.md",
      "---\ntitle: A\ntags: [x]\n---\nbody\n",
    )
  // no _INDEX.md -> load_index fails -> scan_vault finds the note
  let memory.MemoryIndex(notes) = cache.resolve_index(cfg)
  list.any(notes, fn(m) { m.path == "project/architecture.md" })
  |> should.be_true
}

pub fn resolve_index_empty_when_no_vault_test() {
  let cfg =
    Config(..tmp_cfg("none"), vault_path: "build/test_tmp/cache_missing_zzz")
  let memory.MemoryIndex(notes) = cache.resolve_index(cfg)
  notes |> should.equal([])
}
