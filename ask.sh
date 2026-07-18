#!/bin/sh
# ask.sh — talk to kimi_proxy from the command line. (jq version, no Python)
# Usage:  ./ask.sh <model> "<your prompt>"
#   model = auto | plan | code | gemini-3-pro | gpt-5 | ...
# Examples:
#   ./ask.sh plan "Plan fix for bug NM1 Error 400"
#   ./ask.sh code "Write function login"
#
# oo7 task context: when run inside an oo7 task folder (any directory whose
# ancestors contain a TASK.md), the nearest task root is sent as `task_root`
# and the proxy injects that task's markdown (TASK.md, AGENTS.md, docs, ...)
# into the prompt automatically. Set ASK_NO_TASK=1 to skip the detection.
#
# Reads PROXY_URL env (default http://127.0.0.1:8080). Needs: curl, jq.

set -e
PROXY_URL="${PROXY_URL:-http://127.0.0.1:8080}"

model="$1"
shift 2>/dev/null || true
prompt="$*"

if [ -z "$model" ] || [ -z "$prompt" ]; then
  echo "usage: ./ask.sh <model> \"<prompt>\""
  echo "  model = auto | plan | code | gemini-3-pro | gpt-5"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found (install: brew install jq)"
  exit 1
fi

# Walk up from $PWD to the nearest directory holding a TASK.md (like git
# finding .git). Empty when none — or when ASK_NO_TASK=1 opts out.
task_root=""
if [ -z "$ASK_NO_TASK" ]; then
  dir=$(pwd)
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/TASK.md" ]; then
      task_root="$dir"
      break
    fi
    dir=$(dirname "$dir")
  done
fi

# Build the request body safely with jq (handles quotes/newlines/Unicode correctly).
if [ -n "$task_root" ]; then
  echo "» task: $(basename "$task_root")" >&2
  body=$(jq -n --arg m "$model" --arg p "$prompt" --arg t "$task_root" \
    '{model: $m, task_root: $t, messages: [{role: "user", content: $p}]}')
else
  body=$(jq -n --arg m "$model" --arg p "$prompt" \
    '{model: $m, messages: [{role: "user", content: $p}]}')
fi

# Send with a heartbeat: the proxy legitimately takes 1-3 minutes (the model is
# thinking), and a silent blank line reads as "hung". Status goes to stderr so
# stdout stays exactly the answer; the animated spinner only appears when
# stderr is a tty (pipelines/logs get the one-line header, no \r spam).
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
start=$(date +%s)
echo "» $model → $PROXY_URL (ปกติ 1-3 นาที · Ctrl+C ยกเลิก)" >&2

# แสดง model/effort จริงที่ route นี้ resolve — ถามจาก proxy (GET /routes)
# เงียบไปเฉยๆ ถ้า proxy รุ่นเก่า/ไม่ตอบ ไม่กระทบการยิงจริง
routes_json=$(curl -s --max-time 2 "$PROXY_URL/routes" 2>/dev/null) || routes_json=""
if [ -n "$routes_json" ]; then
  case "$model" in
    plan | design | opus | claude-opus-4-8 | opus-4-8)
      info=$(printf '%s' "$routes_json" | jq -r \
        '.plan | "model \(.model) · effort \(.effort) · \(.via) CLI (fallback \(.fallback))"' \
        2> /dev/null) ;;
    code | kimi | kimi-k3)
      info=$(printf '%s' "$routes_json" | jq -r \
        '.code | "model \(.model) · \(.effort) · \(.via) CLI (fallback \(.fallback))"' \
        2> /dev/null) ;;
    auto)
      info=$(printf '%s' "$routes_json" | jq -r \
        '"router เลือกเอง → plan \(.plan.model) / code \(.code.model)"' \
        2> /dev/null) ;;
    *)
      info="direct model $model (ยิงตรง API · ข้าม vault)" ;;
  esac
  if [ -n "${info:-}" ] && [ "$info" != "null" ]; then
    echo "»   $info" >&2
  fi
fi

curl -s "$PROXY_URL/v1/chat/completions" \
  -H 'content-type: application/json' \
  -d "$body" > "$tmp" &
req=$!
trap 'kill "$req" 2>/dev/null; rm -f "$tmp"; exit 130' INT

if [ -t 2 ]; then
  i=0
  while kill -0 "$req" 2>/dev/null; do
    i=$(( (i % 3) + 1 ))
    dots=$(printf '%.*s' "$i" '...')
    printf '\r  กำลังคิด%-3s %ds ' "$dots" "$(( $(date +%s) - start ))" >&2
    sleep 1
  done
  printf '\r%40s\r' '' >&2
fi

# set -e guard: a failing curl must reach our error message, not kill us here
status=0
wait "$req" || status=$?
trap 'rm -f "$tmp"' EXIT INT
if [ "$status" -ne 0 ] || [ ! -s "$tmp" ]; then
  echo "error: could not reach proxy at $PROXY_URL (is it running?)" >&2
  exit 1
fi
# โหมดที่ทำงานจริง — proxy รายงานกลับใน field kimi_proxy (intent จาก router,
# role ที่รัน, และ backend ที่ตอบจริง: CLI หรือ API fallback)
meta=$(jq -r 'if .kimi_proxy then .kimi_proxy
  | "mode \(.intent) · role \(.role) · ทำงานจริงโดย \(.via)"
  else empty end' < "$tmp" 2> /dev/null) || meta=""
if [ -n "$meta" ]; then
  echo "» $meta" >&2
fi
echo "» ตอบแล้วใน $(( $(date +%s) - start ))s" >&2
# Print just the assistant text, or the error message, or raw on parse fail.
jq -r '.choices[0].message.content // .error.message // .' < "$tmp" 2>/dev/null \
  || cat "$tmp"
