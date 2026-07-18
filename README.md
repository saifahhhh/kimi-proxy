# kimi_proxy v2

An **OpenAI-compatible local proxy** (Gleam / BEAM) that splits work between two
"brains" and keeps long-term memory in an Obsidian vault:

- **Planner** (Opus 4.8) — designs / plans / writes memory
- **Coder** (Kimi K3) — writes code

It composes a fresh, budget-bounded context from the vault on every request, so
the model window never overflows. All control decisions (token counting, file
selection, routing) are made in Gleam — never by an LLM.

```
client ──OpenAI API──▶ kimi_proxy (:8080)
                         router.handle: classify → load memory → fit budget
                           plan → Planner (claude CLI → Dedalus API)
                           code → Coder   (kimi-code CLI → Dedalus API)
                         remember → Obsidian vault (.md)
```

## Requirements

- **Gleam ≥ 1.16** and **Erlang/OTP** (`brew install gleam`)
- The subscription CLIs the proxy shells out to (defaults shown; override with the
  `SONNET_CLI` / `KIMI_CLI` env vars):
  - **Planner** → `claude` (Claude Code): `npm i -g @anthropic-ai/claude-code`, then
    log in once with `claude` (interactive). Default invocation:
    `claude --output-format text -p`.
  - **Coder** → `kimi-cli` (Moonshot) run via `uvx`: `brew install uv`, then log in
    once with `uvx kimi-cli login`. Default invocation: `uvx kimi-cli --quiet -p`.
    (The VS Code extension's bundled `kimi` launcher is *not* used — it hard-codes a
    uv path that may be absent.)
- *(optional)* a `DEDALUS_KEY` for the paid API fallback

## Setup

```sh
# 1. install deps
gleam deps download

# 2. create your memory vault from the templates
export VAULT_PATH="$HOME/Documents/brain"
mkdir -p "$VAULT_PATH"
cp -r obsidian_templates/* "$VAULT_PATH/"
#    then edit project/architecture.md + project/conventions.md for YOUR project
#    (they are priority-1 and loaded into almost every request)

# 3. run
gleam run
```

The server listens on `http://127.0.0.1:8080` by default.

## Environment variables (spec §13)

| Env | Required | Default | Used by |
|---|---|---|---|
| `VAULT_PATH` | ✅ | — | memory (must be an existing directory) |
| `DEDALUS_KEY` | ❌ | — | API fallback |
| `HOST` | ❌ | `127.0.0.1` | server |
| `PORT` | ❌ | `8080` | server |
| `CODER_BUDGET` | ❌ | `120000` | context budget for the Coder |
| `PLANNER_BUDGET` | ❌ | `80000` | context budget for the Planner |
| `ENABLE_MEMORY_WRITE` | ❌ | `true` | memory writes |
| `SONNET_CLI` | ❌ | `claude --output-format text -p` | Planner subscription CLI (space-separated) |
| `KIMI_CLI` | ❌ | `uvx kimi-cli --quiet -p` | Coder subscription CLI (space-separated) |

## HTTP API

### `POST /v1/chat/completions`
OpenAI subset. The `model` field selects the route:

| `model` | behaviour |
|---|---|
| `auto` | classify the prompt → plan / code / answer |
| `plan`, `design`, `opus`, `claude-opus-4-8`, `opus-4-8` | force the Planner |
| `code`, `kimi`, `kimi-k3` | force the Coder |
| anything else (`gemini-3-pro`, `gpt-5`, …) | send straight to that model via the API (no memory) |

```sh
curl -s localhost:8080/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Write a login function"}]}' | jq .
```

Responses are OpenAI `chat.completion` shape. Errors: `422` (bad body), `503`
(all backends failed).

The body also accepts an optional proxy extension, `task_root` — the absolute
path of an **oo7 task folder**. When present, that folder's markdown is read
fresh from disk on every request and injected into the prompt: `TASK.md` as
`[TASK]`, `AGENTS.md` as `[AGENTS]`, every other doc (`DESIGN.md`, `docs/`,
`roles/`, …) as `[TASK FILES]`. Repo worktrees (directories carrying `.git`),
dot-directories, and the `CLAUDE.md`/`GEMINI.md` symlink twins are skipped.
Standard OpenAI clients that never send the field are unaffected.

`ask.sh` fills `task_root` automatically: run it anywhere inside an oo7 task
(even deep in a worktree) and it walks up to the nearest `TASK.md`, prints
`» task: <name>` to stderr, and sends the path along. `ASK_NO_TASK=1 ask.sh …`
skips the detection. Install it on your PATH once with
`ln -s "$(pwd)/ask.sh" ~/.local/bin/ask`, then `ask code "…"` from any task.

### `GET /v1/models`
Lists the route directives + known models.

### `GET /health`
Returns `200`.

## Routing & memory (how it works)

- **Planning** ends by returning the plan and writing `tasks/current.md` — you
  review it, then ask to code in a follow-up request. The Planner is *not*
  invoked on every coding turn (keeps the Pro plan under its rate limit).
- **Planner → Coder handoff (anti-drift).** The planning prompt also makes the
  Planner emit a machine-executable handoff block (objective / first_step /
  files / steps with done-checks / constraints / out_of_scope) in the same LLM
  call — zero extra latency. The proxy strips it from the reply and stores it:
  `<task_root>/HANDOFF.md` when the request carries an oo7 task, else the
  vault's `tasks/handoff.md`. Every later coding turn then receives it as a
  priority-1 `[HANDOFF]` section whose steps override the prose `[PLAN]`, so
  the Coder executes instead of re-interpreting. A new plan overwrites it.
- **Coding / Question** loads the relevant notes (always including the current
  plan) and answers with the Coder.
- **Direct** models bypass the vault entirely.
- Each backend tries the **subscription CLI first**, then falls back to the
  Dedalus API on failure / quota / rate-limit messages.

## Using it from OpenCode

Point an OpenAI-compatible provider at this proxy:

```jsonc
{
  "provider": {
    "kimi_proxy": {
      "options": { "baseURL": "http://127.0.0.1:8080/v1" },
      "models": { "auto": {}, "plan": {}, "code": {} }
    }
  }
}
```

Then pick the `auto` / `plan` / `code` models from OpenCode.

## Development

```sh
gleam test          # unit + integration tests (no real CLI / API calls)
gleam format        # format
gleam build         # type-check + compile
```

Tests are deterministic: subscription CLIs are mocked with `/bin/sh -c …` and the
API path is never reached (no `DEDALUS_KEY` is set during tests).

## Notes on dependencies

- `gleam_http` / `gleam_httpc` are pinned with **open upper bounds**: the spec's
  `< 5.0.0` caps resolve to a `gleam_httpc` 4.x that uses `result.then`, removed
  from `gleam_stdlib` 1.0.3; the resolver picks `gleam_httpc` 5.0.0 instead.
- We use **no actors / `gleam_otp`** in our own code (spec §A.6). `mist` (the
  spec-mandated HTTP server, §2) pulls `gleam_otp` in transitively, as every BEAM
  HTTP server does — that is unavoidable infrastructure, not application state.
