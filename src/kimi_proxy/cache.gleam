//// Index caching (spec §16 Phase 3, §A.6).
////
//// "Caching" here is pure-functional per spec §A.6: load the vault index once
//// and thread the resulting `MemoryIndex` down the call chain as an argument —
//// no stateful actor (rule #4: no gleam_otp), no shared mutable state.
////
//// Scope note: §16-P3 acceptance literally says "read disk once per *process*
//// until a write". True cross-request caching needs shared state (an actor or
//// ETS), which §A.6 explicitly rejects for v2. So this is once-per-*request*:
//// the router calls `resolve_index` once when it starts handling a request and
//// passes the result to `select_relevant` / `build_blocks`, which avoids
//// repeated disk reads within a request. Cross-request caching is future work
//// (§18). This deviation is the rule-#6 "follow the explicit decision" call.

import kimi_proxy/config.{type Config}
import kimi_proxy/memory.{type MemoryIndex, MemoryIndex}

/// Load the index once, with graceful fallback so there is always *some* index:
/// fast `_INDEX.md` parse → full vault scan → empty index (spec §11, §12).
pub fn resolve_index(cfg: Config) -> MemoryIndex {
  case memory.load_index(cfg) {
    Ok(index) -> index
    Error(_) ->
      case memory.scan_vault(cfg) {
        Ok(index) -> index
        Error(_) -> MemoryIndex([])
      }
  }
}
