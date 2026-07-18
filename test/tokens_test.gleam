import gleam/list
import gleam/string
import gleeunit/should
import kimi_proxy/tokens
import kimi_proxy/types.{ContextBlock}

pub fn empty_is_zero_test() {
  tokens.estimate("") |> should.equal(0)
}

pub fn single_char_test() {
  // ceil(1 / 3.5) = 1, + 4 overhead = 5
  tokens.estimate("a") |> should.equal(5)
}

pub fn ascii_phrase_test() {
  // "hello world" = 11 code points; ceil(11 / 3.5) = 4, + 4 = 8
  tokens.estimate("hello world") |> should.equal(8)
}

pub fn monotonic_test() {
  let a = tokens.estimate("a")
  let ab = tokens.estimate("ab")
  let long = tokens.estimate(string.repeat("a", 100))
  should.be_true(tokens.estimate("") <= a)
  should.be_true(a <= ab)
  should.be_true(ab <= long)
}

pub fn five_codepoints_test() {
  // "tests" = 5 code points; ceil(5 / 3.5) = 2, + 4 = 6
  tokens.estimate("tests") |> should.equal(6)
}

pub fn ten_codepoints_test() {
  // Code points must drive the estimate (never grapheme-collapsed, which would
  // under-count). "helloworld" = 10 code points; ceil(10 / 3.5) = 3, + 4 = 7.
  let s = "helloworld"
  list.length(string.to_utf_codepoints(s)) |> should.equal(10)
  tokens.estimate(s) |> should.equal(7)
}

pub fn estimate_blocks_sums_est_tokens_test() {
  let blocks = [
    ContextBlock(label: "A", content: "x", priority: 1, est_tokens: 10),
    ContextBlock(label: "B", content: "y", priority: 2, est_tokens: 25),
  ]
  tokens.estimate_blocks(blocks) |> should.equal(35)
}

pub fn estimate_blocks_empty_test() {
  tokens.estimate_blocks([]) |> should.equal(0)
}
