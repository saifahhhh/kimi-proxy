# START HERE — How to use kimi_proxy every day

> kimi_proxy = a "power plug / central brain" that sits idle waiting — you need a **client** to plug in (curl or OpenCode).
> It doesn't "train"/"remember" anything — it's only as smart as the vault (`~/Documents/brain`).

## Prerequisites (already installed on this machine)
- `gleam` (the proxy) · `claude` (Planner) · `uvx kimi-cli` (Coder) — both logged in
- vault at `~/Documents/brain` (7 notes: stack/conventions/glossary/flow/bug/sync)

---

## Step 1 — Start the proxy (terminal #1, leave it running)

```sh
cd ~/Documents/kimi_proxy
KIMI_PROXY_DIR="$HOME/Documents/kimi_proxy" VAULT_PATH="$HOME/Documents/brain" gleam run
```
See `Listening on http://127.0.0.1:8080` = ready. Stop with Ctrl-C.

> `KIMI_PROXY_DIR` tells the proxy where to find the agent file (read-only mode — see below)
> regardless of which directory you run from. If unset, it uses a relative path (`./agents/...`)
> which is only found when `cd`'d into the proxy dir.

## Step 2 — Talk to it (terminal #2)

Use the provided helper (`./ask.sh`) — easier than long curl commands:

```sh
cd ~/Documents/kimi_proxy
./ask.sh plan "Plan fix for bug NM1 recorded Error 400"   # plan (Claude)
./ask.sh code "Write function ... "                       # write code (Kimi)
./ask.sh auto "..."                                       # let the system choose
```

`model` options: `plan` (Claude plans) · `code` (Kimi writes) · `auto` (auto-select) ·
`gemini-3-pro`/`gpt-5` (direct shot, no vault).

---

## Correct workflow (important)

**plan → review → code** — don't skip:

```
1. ./ask.sh plan "Task you want to do"
   → Claude plans + writes to brain/tasks/current.md
2. You "read the plan yourself" → if OK proceed, if not → re-plan with a clearer prompt
3. ./ask.sh code "Follow the plan, start phase 1"
   → Kimi writes code (gets context: plan + conventions + architecture from vault)
```
Why separate: prevents AI from guessing + you control direction (matches what we discussed about constraint-leakage).

---

## ⚠️ Read-only mode (Coder = Kimi) — important

**By default Kimi cannot write/edit files** — it can read the repo + reply with text/code, but
*cannot create/edit files on the machine*. Why: kimi-cli is an agent "with hands" that once accidentally injected code
(`pub fn add`) into the proxy's own source during testing. We disabled write capability at the
*tool level* via `agents/readonly.agent.yaml` (removes WriteFile/StrReplace/Shell)
fed to kimi with `--agent-file` — verified 2026-06-01.

- Use the proxy as a **"generator + memory"** → safe, use this default
- Want Kimi to **actually edit the repo** (full agent mode) → disable read-only:
  ```sh
  export KIMI_CLI="uvx kimi-cli --quiet -p"   # no --agent-file = can write
  ```
  Then run only in the target repo (see OpenCode below) — never run in the proxy dir.

---

## Using with OpenCode (optional — smoother)

Set provider to point at the proxy:
```jsonc
{ "provider": { "kimi_proxy": {
    "options": { "baseURL": "http://127.0.0.1:8080/v1" },
    "models": { "auto": {}, "plan": {}, "code": {} } } } }
```
**Important:** Open OpenCode in the repo you want to edit (`~/Code/Workspace/oil-control-api` or
`oil-control-web`) so Kimi reads the actual repo files + gets vault context simultaneously.
(If you want Kimi to edit files through OpenCode you must disable read-only as described above.)

---

## The Train button (easiest way to feed the vault)

With the proxy running, open **http://127.0.0.1:8080/train** in a browser: pick a
folder, type a title + tags/keywords + markdown content, press **🚀 Train**. The
note is written into the vault atomically, `_INDEX.md` is rebuilt, the session log
gets a `TRAIN wrote ...` line, and the page shows the fresh note count. Same title
again = update the same note. Effective immediately — the proxy reads the vault
fresh on every request, no restart.

## The agentic pipeline (idea → verified page, no human mid-flight)

`pipeline/pipeline.sh` runs PO → Designer → Dev → Verify with a self-correcting
feedback loop (verdict goes back to Dev, max 3 rounds) and kill switches
(per-stage timeout, sandboxed writes, loop cap). See `pipeline/README.md`.

```sh
MOCK=1 ./pipeline/pipeline.sh "หน้า login สวยๆ" smoke   # plumbing test, no LLM
STAGE_TIMEOUT=300 ./pipeline/pipeline.sh "หน้า login สวยๆ" login   # real run
```

## Maintaining the vault = "training" (do when the system changes)

The proxy is only as smart as the vault. Want it to know more → add notes in `~/Documents/brain/`:
- `project/*.md` = high priority (loaded on almost every request) — stack, conventions, design-system
- `decisions/*.md` = loaded when keywords match — flow, ADR, protocol
- image sources (Figma/Miro/screenshots) → **must be transcribed to text first** (proxy cannot read images)
- edit notes without restarting — it reads fresh every request

---

## Quick health checks
```sh
curl -s localhost:8080/health            # should return empty 200
curl -s localhost:8080/v1/models | jq .  # see supported models
cat ~/Documents/brain/sessions/$(date +%F).md   # today's log (every request)
```

## Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `503 all backends failed` | claude/kimi not logged in or not in PATH | `claude` / `uvx kimi-cli login` |
| `422` | body is not JSON | check `./ask.sh` or payload |
| Slow response 1-2 minutes | normal — Claude/Kimi is actually thinking | wait |
| Kimi answers about wrong repo | wrong working dir | open OpenCode in the correct repo |
| Kimi says "no WriteFile/can't create file" | read-only mode (intentional) | disable: `export KIMI_CLI="uvx kimi-cli --quiet -p"` |
| Kimi writes slower than usual (~2-3 min) | read-only makes it search for write tools and fail | normal for read-only; disable if you need actual writes |
