#!/bin/sh
# hands.sh — ปลดมือ Kimi (คืน write tools) แบบควบคุมได้ ทั้งสองทาง — oo7-aware
#
#   ./hands.sh a <task> [--go] [--yolo] [--prompt "<text>"] [--herdr]
#       ทาง A: รัน kimi-cli "เต็มมือ" ตรงใน task worktree (ไม่ผ่าน proxy)
#       - ไม่ส่ง --agent-file (readonly) → มี WriteFile/StrReplace/Shell ครบ
#       - -w <taskdir> → มือทำงานในโฟลเดอร์ task (พังก็ revert branch ได้)
#       - agent อ่าน AGENTS.md/CLAUDE.md ของ task เองโดยธรรมชาติ (ไม่มี vault)
#       - --prompt "<text>" = โหมด headless (--quiet -p) · ไม่ใส่ = interactive
#       - --yolo = ส่ง -y (auto-approve ทุก action — ใช้เมื่อไว้ใจงานเท่านั้น)
#       - --herdr = spawn เป็น agent pane ใน Herdr sidebar (ชื่อ kimi-<id>)
#         แทนการรันใน terminal นี้ — ต้องมี herdr server รันอยู่
#
#   ./hands.sh b <task> [--go] [--port N]
#       ทาง B: boot proxy โหมดปลดล็อก — ได้ vault context + task context + มือ
#       - override KIMI_CLI: ตัด --agent-file ออก + ชี้ -w ไปที่ task
#       - ปลดล็อก "ทุก request ที่เข้า code route" ตลอดการ boot นี้ —
#         ใช้เสร็จ Ctrl-C แล้ว boot โหมดปกติกลับทันที
#
# <task> = id หรือชื่อโฟลเดอร์ใต้ oo7/tasks (เช่น 0009 หรือ 0009-fi-418-...)
#
# DEFAULT = DRY-RUN: พิมพ์คำสั่งที่จะรันให้ตรวจก่อน — เติม --go จึงรันจริง
# (ยึดคำเตือนเดิมของทีม: อย่าปลดมือจนกว่าเป้าจะยืนยัน สคริปต์นี้จึงไม่ทำอะไร
#  เองเงียบ ๆ — ทุกการปลดต้องมีคน (หรือ agent ที่ถูกสั่งชัด ๆ) พิมพ์ --go)
#
# env: KIMI_PIN_FILE = pin TOML (default agents/kimi-k3.toml; ใช้ kimi-k2.7.toml เพื่อ rollback)
#      OO7_TASKS     = โฟลเดอร์ tasks ของ oo7 (default: ../oo7/tasks ข้าง proxy)
#      VAULT_PATH    = vault ของ proxy (ทาง B; default ~/Documents/sandbox/brain)

set -eu

here=$(cd "$(dirname "$0")" && pwd)
pin="${KIMI_PIN_FILE:-$here/agents/kimi-k3.toml}"
tasks_dir="${OO7_TASKS:-$here/../oo7/tasks}"

die() { echo "error: $*" >&2; exit 1; }

mode="${1:-}"; task="${2:-}"
[ -n "$mode" ] && [ -n "$task" ] || {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
shift 2

go=0; yolo=0; prompt=""; port=8080; use_herdr=0
while [ $# -gt 0 ]; do
  case "$1" in
    --go) go=1; shift;;
    --yolo) yolo=1; shift;;
    --prompt) prompt="${2:?--prompt needs text}"; shift 2;;
    --port) port="${2:?--port needs a number}"; shift 2;;
    --herdr) use_herdr=1; shift;;
    *) die "unknown flag: $1";;
  esac
done

[ -f "$pin" ] || die "pin file not found: $pin"
[ -d "$tasks_dir" ] || die "oo7 tasks dir not found: $tasks_dir (set OO7_TASKS)"

# resolve <task>: exact folder name, else zero-padded id prefix
taskdir=""
if [ -d "$tasks_dir/$task" ]; then
  taskdir="$tasks_dir/$task"
else
  # ลอง prefix ตรง ๆ ก่อน (เช่น "0009-…") แล้วค่อย pad ฐานสิบ (เช่น "9" → "0009")
  padded=$(awk -v t="$task" 'BEGIN{printf "%04d", t+0}')
  for cand in "$task" "$padded"; do
    for d in "$tasks_dir/$cand"-*; do
      [ -d "$d" ] && [ -f "$d/TASK.md" ] && { taskdir="$d"; break 2; }
    done
  done
fi
[ -n "$taskdir" ] && [ -f "$taskdir/TASK.md" ] \
  || die "no oo7 task matching '$task' under $tasks_dir (need a folder with TASK.md)"
taskdir=$(cd "$taskdir" && pwd)

case "$mode" in
  a)
    set -- uvx kimi-cli -w "$taskdir" --config-file "$pin"
    [ "$yolo" = 1 ] && set -- "$@" -y
    [ -n "$prompt" ] && set -- "$@" --quiet -p "$prompt"
    if [ "$use_herdr" = 1 ]; then
      agent_name="kimi-$(basename "$taskdir" | cut -d- -f1)"
      set -- herdr agent start "$agent_name" --cwd "$taskdir" -- "$@"
    fi
    echo "» ทาง A — kimi-cli เต็มมือ (ไม่มี readonly agent-file) ใน:" >&2
    echo "»   task: $(basename "$taskdir")" >&2
    echo "»   pin:  $pin" >&2
    [ "$use_herdr" = 1 ] && echo "»   herdr: agent pane '$agent_name' ใน sidebar" >&2
    printf '  %s\n' "$*" >&2
    if [ "$go" = 1 ]; then
      echo "» GO — launching (Ctrl-C เพื่อหยุด)" >&2
      if [ -n "$prompt" ] && [ "$use_herdr" = 0 ]; then exec "$@" < /dev/null
      else exec "$@"; fi
    else
      echo "» dry-run — เติม --go เพื่อรันจริง" >&2
    fi
    ;;
  b)
    kimi_cli="uvx kimi-cli -w $taskdir --config-file $pin --quiet -p"
    vault="${VAULT_PATH:-$HOME/Documents/sandbox/brain}"
    echo "» ทาง B — proxy โหมดปลดล็อก (vault + task context + มือ):" >&2
    echo "»   task:  $(basename "$taskdir")" >&2
    echo "»   vault: $vault · port: $port" >&2
    echo "»   ⚠ ทุก request เข้า code route ของ boot นี้ = Kimi มีมือ" >&2
    printf '  cd %s && KIMI_CLI="%s" VAULT_PATH="%s" KIMI_PROXY_DIR="%s" PORT=%s gleam run\n' \
      "$here" "$kimi_cli" "$vault" "$here" "$port" >&2
    if [ "$go" = 1 ]; then
      echo "» GO — booting proxy (Ctrl-C เพื่อหยุดและกลับโหมดปกติ)" >&2
      cd "$here"
      KIMI_CLI="$kimi_cli" VAULT_PATH="$vault" KIMI_PROXY_DIR="$here" PORT="$port" \
        exec gleam run
    else
      echo "» dry-run — เติม --go เพื่อรันจริง" >&2
    fi
    ;;
  *) die "mode ต้องเป็น a หรือ b (ดู usage: ./hands.sh)";;
esac
