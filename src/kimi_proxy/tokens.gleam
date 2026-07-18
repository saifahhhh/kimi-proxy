//// Conservative token estimation (spec §6.2).
////
//// Pure and deterministic — no network, no LLM. We deliberately over-estimate
//// to avoid context overflow. Counts Unicode code points (not grapheme
//// clusters) so Thai/Chinese text is never under-estimated — see `estimate`.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import kimi_proxy/types.{type ContextBlock}

/// Average characters per token used by the heuristic. Lower = more conservative.
const chars_per_token: Float = 3.5

/// Fixed per-block overhead (role markers etc.), added to every non-empty block.
const block_overhead: Int = 4

/// Estimate the number of tokens in `text`, rounded up and padded with a small
/// per-block overhead. Returns 0 for the empty string (spec §6.2 acceptance).
///
/// NOTE: the reference skeleton (spec §B.1) uses `string.length`, but Gleam's
/// `string.length` counts grapheme clusters, which under-counts Thai text with
/// combining marks. The spec body (§6.2) and its acceptance ("Thai text must not
/// be underestimated") call for code-point counting, so we count code points. This
/// is the rule-#6 "follow the real library / honour the acceptance" deviation.
pub fn estimate(text: String) -> Int {
  case codepoint_count(text) {
    0 -> 0
    n -> ceil_div(n, chars_per_token) + block_overhead
  }
}

/// Sum the pre-computed `est_tokens` of several blocks. Each block's overhead is
/// already baked into its `est_tokens` (via `estimate`), so we simply add them
/// (spec §B.1) — no double counting.
pub fn estimate_blocks(blocks: List(ContextBlock)) -> Int {
  list.fold(blocks, 0, fn(acc, b) { acc + b.est_tokens })
}

fn codepoint_count(text: String) -> Int {
  text
  |> string.to_utf_codepoints
  |> list.length
}

fn ceil_div(n: Int, divisor: Float) -> Int {
  let ratio = int.to_float(n) /. divisor
  ratio
  |> float.ceiling
  |> float.round
}
