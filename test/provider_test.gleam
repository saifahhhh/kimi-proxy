import gleam/string
import gleeunit/should
import kimi_proxy/config.{type Config, Config}
import kimi_proxy/provider.{AllBackendsFailed, Coder}
import simplifile

fn cfg_with(kimi: List(String), key: Result(String, Nil)) -> Config {
  Config(
    host: "127.0.0.1",
    port: 8080,
    vault_path: "build/test_tmp",
    dedalus_key: key,
    coder_context_budget: 120_000,
    planner_context_budget: 80_000,
    enable_memory_write: True,
    sonnet_cli: ["/bin/sh", "-c", "echo planned"],
    kimi_cli: kimi,
    usage_file: Error(Nil),
    usage_throttle_pct: 90,
  )
}

/// Like cfg_with, but with the usage throttle configured (spec §21).
fn cfg_with_usage(kimi: List(String), usage_path: String, pct: Int) -> Config {
  Config(
    ..cfg_with(kimi, Error(Nil)),
    usage_file: Ok(usage_path),
    usage_throttle_pct: pct,
  )
}

/// Write a real usage file under build/test_tmp and return its path.
fn usage_file(name: String, contents: String) -> String {
  let dir = "build/test_tmp/usage"
  let _ = simplifile.create_directory_all(dir)
  let path = dir <> "/" <> name
  let assert Ok(_) = simplifile.write(to: path, contents: contents)
  path
}

// --- is_quota_error patterns (spec §6.5) -----------------------------------

pub fn quota_detects_all_signals_test() {
  should.be_true(provider.is_quota_error("Error: rate limit exceeded"))
  should.be_true(provider.is_quota_error("you hit your QUOTA today"))
  should.be_true(provider.is_quota_error("monthly usage limit"))
  should.be_true(provider.is_quota_error("please upgrade your plan"))
  should.be_true(provider.is_quota_error("HTTP 429: too many requests"))
  should.be_true(provider.is_quota_error("limit reached"))
}

pub fn quota_ignores_normal_output_test() {
  should.be_false(provider.is_quota_error("here is your code: pub fn main()"))
  should.be_false(provider.is_quota_error(""))
}

// --- subscription success --------------------------------------------------

pub fn sub_success_returns_output_test() {
  // mock CLI: /bin/sh -c "echo coded-by-mock" <prompt-appended>
  let cfg = cfg_with(["/bin/sh", "-c", "echo coded-by-mock"], Error(Nil))
  let assert Ok(provider.Answer(out, _)) = provider.run_role(cfg, Coder, "do it")
  string.contains(out, "coded-by-mock") |> should.be_true
}

// --- fallback chain: every sub failure mode -> API (no key) -> AllBackendsFailed

pub fn sub_quota_falls_back_then_fails_without_key_test() {
  let cfg =
    cfg_with(["/bin/sh", "-c", "echo 'rate limit exceeded'"], Error(Nil))
  provider.run_role(cfg, Coder, "x")
  |> should.equal(Error(AllBackendsFailed(Coder)))
}

pub fn sub_nonzero_exit_falls_back_then_fails_test() {
  let cfg = cfg_with(["/bin/sh", "-c", "exit 3"], Error(Nil))
  provider.run_role(cfg, Coder, "x")
  |> should.equal(Error(AllBackendsFailed(Coder)))
}

pub fn missing_cli_falls_back_then_fails_test() {
  let cfg = cfg_with(["/nonexistent/xyzcli"], Error(Nil))
  provider.run_role(cfg, Coder, "x")
  |> should.equal(Error(AllBackendsFailed(Coder)))
}

// --- describe --------------------------------------------------------------

pub fn describe_mentions_role_test() {
  provider.describe(AllBackendsFailed(Coder))
  |> string.contains("coder")
  |> should.be_true
}

// --- usage throttle (spec §21) ----------------------------------------------

// -- read_usage --

pub fn read_usage_unconfigured_is_unknown_test() {
  provider.read_usage(cfg_with(["x"], Error(Nil))) |> should.equal(Error(Nil))
}

pub fn read_usage_parses_trimmed_integer_test() {
  let path = usage_file("ok.txt", "  88\n")
  provider.read_usage(cfg_with_usage(["x"], path, 90)) |> should.equal(Ok(88))
}

pub fn read_usage_missing_file_is_unknown_test() {
  provider.read_usage(cfg_with_usage(
    ["x"],
    "build/test_tmp/usage/does_not_exist_zzz",
    90,
  ))
  |> should.equal(Error(Nil))
}

pub fn read_usage_bad_content_is_unknown_test() {
  let path = usage_file("bad.txt", "ninety-seven")
  provider.read_usage(cfg_with_usage(["x"], path, 90))
  |> should.equal(Error(Nil))
}

pub fn read_usage_out_of_range_is_unknown_test() {
  let over = usage_file("over.txt", "150")
  provider.read_usage(cfg_with_usage(["x"], over, 90))
  |> should.equal(Error(Nil))
  let neg = usage_file("neg.txt", "-5")
  provider.read_usage(cfg_with_usage(["x"], neg, 90))
  |> should.equal(Error(Nil))
}

// -- run_role behaviour under the throttle --

pub fn usage_unconfigured_attempts_subscription_test() {
  // no usage_file in config -> feature is a no-op, subscription runs
  let cfg = cfg_with(["/bin/sh", "-c", "echo sub-ran"], Error(Nil))
  let assert Ok(provider.Answer(out, _)) = provider.run_role(cfg, Coder, "x")
  string.contains(out, "sub-ran") |> should.be_true
}

pub fn usage_below_threshold_attempts_subscription_test() {
  let path = usage_file("low.txt", "42")
  let cfg = cfg_with_usage(["/bin/sh", "-c", "echo sub-ran"], path, 90)
  let assert Ok(provider.Answer(out, _)) = provider.run_role(cfg, Coder, "x")
  string.contains(out, "sub-ran") |> should.be_true
}

pub fn usage_at_threshold_skips_subscription_test() {
  // the mock CLI would succeed if it ran; AllBackendsFailed proves it was
  // skipped (the API layer has no key), i.e. the quota-failure fallback path
  let path = usage_file("at.txt", "90")
  let cfg = cfg_with_usage(["/bin/sh", "-c", "echo should-not-run"], path, 90)
  provider.run_role(cfg, Coder, "x")
  |> should.equal(Error(AllBackendsFailed(Coder)))
}

pub fn usage_above_threshold_skips_subscription_test() {
  let path = usage_file("high.txt", "97")
  let cfg = cfg_with_usage(["/bin/sh", "-c", "echo should-not-run"], path, 90)
  provider.run_role(cfg, Coder, "x")
  |> should.equal(Error(AllBackendsFailed(Coder)))
}

pub fn usage_malformed_file_attempts_subscription_test() {
  // unreadable usage means "unknown, proceed normally" — never a crash
  let path = usage_file("garbage.txt", "97%\nextra")
  let cfg = cfg_with_usage(["/bin/sh", "-c", "echo sub-ran"], path, 90)
  let assert Ok(provider.Answer(out, _)) = provider.run_role(cfg, Coder, "x")
  string.contains(out, "sub-ran") |> should.be_true
}

pub fn usage_missing_file_attempts_subscription_test() {
  let cfg =
    cfg_with_usage(
      ["/bin/sh", "-c", "echo sub-ran"],
      "build/test_tmp/usage/never_written_zzz",
      90,
    )
  let assert Ok(provider.Answer(out, _)) = provider.run_role(cfg, Coder, "x")
  string.contains(out, "sub-ran") |> should.be_true
}
