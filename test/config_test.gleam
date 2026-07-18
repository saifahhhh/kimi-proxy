import envoy
import gleam/list
import gleam/result
import gleeunit/should
import kimi_proxy/config
import simplifile

const env_names = [
  "VAULT_PATH", "DEDALUS_KEY", "HOST", "PORT", "CODER_BUDGET", "PLANNER_BUDGET",
  "ENABLE_MEMORY_WRITE", "SONNET_CLI", "KIMI_CLI", "KIMI_AGENT_FILE",
  "KIMI_CONFIG_FILE", "KIMI_PROXY_DIR", "USAGE_STATUS_FILE",
  "USAGE_THROTTLE_PCT",
]

/// Clear every env var `config.load` reads, so each test starts from a known
/// state regardless of the host environment or test ordering.
fn clear_env() -> Nil {
  list.each(env_names, envoy.unset)
}

/// Create a throwaway directory under build/ to act as a valid VAULT_PATH.
fn make_tmp_vault(name: String) -> String {
  let path = "build/test_tmp/" <> name
  let _ = simplifile.create_directory_all(path)
  path
}

pub fn missing_vault_path_is_error_test() {
  clear_env()
  config.load() |> result.is_error |> should.be_true
}

pub fn vault_path_not_a_directory_is_error_test() {
  clear_env()
  envoy.set("VAULT_PATH", "build/test_tmp/does_not_exist_xyz")
  config.load() |> result.is_error |> should.be_true
  clear_env()
}

pub fn defaults_test() {
  clear_env()
  let vault = make_tmp_vault("defaults")
  envoy.set("VAULT_PATH", vault)

  let assert Ok(cfg) = config.load()
  cfg.vault_path |> should.equal(vault)
  cfg.host |> should.equal("127.0.0.1")
  cfg.port |> should.equal(8080)
  cfg.coder_context_budget |> should.equal(120_000)
  cfg.planner_context_budget |> should.equal(80_000)
  cfg.enable_memory_write |> should.be_true
  cfg.sonnet_cli
  |> should.equal([
    "claude", "--model", "claude-opus-4-8", "--output-format", "text", "-p",
  ])
  // Coder default runs kimi-cli read-only via an agent file (write tools
  // excluded) and pinned to K3 via a config file. With KIMI_PROXY_DIR unset
  // both paths fall back to project-relative.
  cfg.kimi_cli
  |> should.equal([
    "uvx", "kimi-cli", "--agent-file", "./agents/readonly.agent.yaml",
    "--config-file", "./agents/kimi-k3.toml", "--quiet", "-p",
  ])
  cfg.dedalus_key |> should.equal(Error(Nil))
  // usage throttle (spec §21): off by default, threshold defaults to 90
  cfg.usage_file |> should.equal(Error(Nil))
  cfg.usage_throttle_pct |> should.equal(90)

  clear_env()
}

pub fn custom_values_test() {
  clear_env()
  let vault = make_tmp_vault("custom")
  envoy.set("VAULT_PATH", vault)
  envoy.set("HOST", "0.0.0.0")
  envoy.set("PORT", "9000")
  envoy.set("CODER_BUDGET", "50000")
  envoy.set("PLANNER_BUDGET", "40000")
  envoy.set("ENABLE_MEMORY_WRITE", "false")
  envoy.set("SONNET_CLI", "claude -p --model sonnet")
  envoy.set("KIMI_CLI", "kimi-code")
  envoy.set("DEDALUS_KEY", "secret123")
  envoy.set("USAGE_STATUS_FILE", "/var/run/kimi-usage.txt")
  envoy.set("USAGE_THROTTLE_PCT", "75")

  let assert Ok(cfg) = config.load()
  cfg.host |> should.equal("0.0.0.0")
  cfg.port |> should.equal(9000)
  cfg.coder_context_budget |> should.equal(50_000)
  cfg.planner_context_budget |> should.equal(40_000)
  cfg.enable_memory_write |> should.be_false
  cfg.sonnet_cli |> should.equal(["claude", "-p", "--model", "sonnet"])
  cfg.kimi_cli |> should.equal(["kimi-code"])
  cfg.dedalus_key |> should.equal(Ok("secret123"))
  cfg.usage_file |> should.equal(Ok("/var/run/kimi-usage.txt"))
  cfg.usage_throttle_pct |> should.equal(75)

  clear_env()
}

pub fn bad_usage_throttle_pct_is_error_test() {
  clear_env()
  let vault = make_tmp_vault("badpct")
  envoy.set("VAULT_PATH", vault)
  envoy.set("USAGE_THROTTLE_PCT", "ninety")

  config.load() |> result.is_error |> should.be_true

  clear_env()
}

pub fn bad_port_is_error_test() {
  clear_env()
  let vault = make_tmp_vault("badport")
  envoy.set("VAULT_PATH", vault)
  envoy.set("PORT", "not-a-number")

  config.load() |> result.is_error |> should.be_true

  clear_env()
}
