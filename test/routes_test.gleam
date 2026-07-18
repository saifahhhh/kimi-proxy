import gleam/json
import gleam/string
import gleeunit/should
import kimi_proxy/config.{Config}
import kimi_proxy/routes
import simplifile

fn base_config(sonnet: List(String), kimi: List(String)) -> config.Config {
  Config(
    host: "127.0.0.1",
    port: 8080,
    vault_path: "build/test_tmp",
    dedalus_key: Error(Nil),
    coder_context_budget: 120_000,
    planner_context_budget: 80_000,
    enable_memory_write: True,
    sonnet_cli: sonnet,
    kimi_cli: kimi,
    usage_file: Error(Nil),
    usage_throttle_pct: 90,
  )
}

// ---- cli_flag ---------------------------------------------------------------

pub fn cli_flag_finds_value_test() {
  routes.cli_flag(["claude", "--model", "claude-opus-4-8", "-p"], "--model")
  |> should.equal(Ok("claude-opus-4-8"))
}

pub fn cli_flag_missing_is_error_test() {
  routes.cli_flag(["claude", "-p"], "--model") |> should.equal(Error(Nil))
  routes.cli_flag(["--model"], "--model") |> should.equal(Error(Nil))
  routes.cli_flag([], "--model") |> should.equal(Error(Nil))
}

// ---- toml_scalar ------------------------------------------------------------

pub fn toml_scalar_test() {
  let raw = "# comment\ndefault_model = \"kimi-code/kimi-k3\"\nx = 1\n"
  routes.toml_scalar(raw, "default_model")
  |> should.equal(Ok("kimi-code/kimi-k3"))
  routes.toml_scalar(raw, "missing") |> should.equal(Error(Nil))
}

// ---- full report ------------------------------------------------------------

pub fn report_resolves_both_roles_test() {
  let toml_path = "build/test_tmp/routes_kimi.toml"
  let _ = simplifile.create_directory_all("build/test_tmp")
  let assert Ok(_) =
    simplifile.write(
      to: toml_path,
      contents: "default_model = \"kimi-code/kimi-k3\"\n",
    )
  let cfg =
    base_config(
      ["claude", "--model", "claude-opus-4-8", "--output-format", "text", "-p"],
      ["uvx", "kimi-cli", "--config-file", toml_path, "--quiet", "-p"],
    )
  let out = routes.report(cfg) |> json.to_string
  out |> string.contains("\"model\":\"claude-opus-4-8\"") |> should.be_true
  out |> string.contains("\"effort\":\"default\"") |> should.be_true
  out |> string.contains("\"model\":\"kimi-k3\"") |> should.be_true
  out |> string.contains("\"effort\":\"thinking off\"") |> should.be_true
  out
  |> string.contains("\"fallback\":\"anthropic/claude-opus-4-8\"")
  |> should.be_true
  out
  |> string.contains("\"fallback\":\"moonshot/kimi-k3\"")
  |> should.be_true
}

pub fn report_degrades_without_pins_test() {
  let cfg = base_config(["claude", "-p"], ["kimi"])
  let out = routes.report(cfg) |> json.to_string
  out |> string.contains("\"model\":\"cli-default\"") |> should.be_true
}
