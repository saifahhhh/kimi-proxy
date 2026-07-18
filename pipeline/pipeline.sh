#!/bin/sh
# pipeline.sh — Agentic Loop: idea 1 บรรทัด → หน้าเว็บที่ verify แล้ว โดยไม่มีคนกลางทาง
#
#   human idea ─▶ 1.PO(plan) ─▶ 2.Designer(plan) ─▶ 3.Dev(code) ─▶ 4.Verify(auto)
#                                                        ▲               │
#                                                        └── verdict ────┘  (Reflect,
#                                                            สูงสุด $MAX_LOOPS รอบ)
#
# vault ของ pipeline = โฟลเดอร์ run: แต่ละ stage เขียน output เป็นไฟล์ .md
# แล้ว stage ถัดไปอ่านต่อ — ไม่มีคน copy-paste ระหว่างทาง
#
# Usage:  ./pipeline.sh "หน้า login สวยๆ" [run-name]
# Env:    PROXY_URL      ที่อยู่ proxy            (default http://127.0.0.1:8080)
#         STAGE_TIMEOUT  วินาที/การเรียก LLM     (default 180)  ← kill switch #1
#         MAX_LOOPS      รอบ dev↔verify สูงสุด   (default 3)    ← kill switch #3
#         MOCK=1         ใช้คำตอบสำเร็จรูป ไม่เรียก LLM (ทดสอบ plumbing)
#
# Kill switch #2 (sandbox): สคริปต์นี้เท่านั้นที่เขียนไฟล์ และเขียนเฉพาะใต้
# pipeline/runs/<run>/ — ตัว Coder เองรัน read-only (agents/readonly.agent.yaml)
# จึงแตะ source จริงไม่ได้ (บทเรียนจากเหตุการณ์ `pub fn add`)

set -u

here=$(cd "$(dirname "$0")" && pwd)
proxy_dir=$(dirname "$here")

idea="${1:-}"
if [ -z "$idea" ]; then
  echo "usage: ./pipeline.sh \"<idea>\" [run-name]"
  exit 1
fi
name="${2:-run}"
STAGE_TIMEOUT="${STAGE_TIMEOUT:-180}"
MAX_LOOPS="${MAX_LOOPS:-3}"

run_dir="$here/runs/$(date +%F)-$name"
mkdir -p "$run_dir/3-code"
state="$run_dir/STATE.md"
lessons="$here/LESSONS.md"
log="$run_dir/pipeline.log"
html="$run_dir/3-code/index.html"
verdict="$run_dir/4-verdict.md"
spec="$run_dir/1-spec.md"

# ---------------------------------------------------------------------------
# memory ของ loop: STATE.md = ใครทำอะไรถึงไหน, LESSONS.md = เคยพลาดอะไร
# ---------------------------------------------------------------------------

note_state() { # stage, status, detail
  printf -- "- %s | %-8s | %-6s | %s\n" "$(date '+%H:%M:%S')" "$1" "$2" "$3" \
    >> "$state"
}

lesson() { # one-line lesson — แท็ก [mock] เมื่อเป็นรอบทดสอบ กันปนกับบทเรียนจริง
  _tag=""
  [ "${MOCK:-}" = "1" ] && _tag="[mock] "
  printf -- "- %s %s | %s%s\n" "$(date +%F)" "$(basename "$run_dir")" "$_tag" "$1" \
    >> "$lessons"
}

die() { # stage
  note_state "$1" FAIL "error/timeout (limit ${STAGE_TIMEOUT}s)"
  lesson "stage $1 ล้ม (error หรือเกิน ${STAGE_TIMEOUT}s) — ดู pipeline.log"
  echo "✗ pipeline หยุดที่ stage $1 — ดู $state และ $log"
  exit 1
}

# ---------------------------------------------------------------------------
# ask: เรียก LLM ผ่าน ask.sh ครอบด้วย watchdog timeout (kill switch #1)
# ---------------------------------------------------------------------------

ask() { # model, prompt-file, out-file
  if [ "${MOCK:-}" = "1" ]; then
    mock_answer "$3"
    return $?
  fi
  _prompt=$(cat "$2")
  ( ASK_NO_TASK=1 sh "$proxy_dir/ask.sh" "$1" "$_prompt" > "$3" 2>> "$log" ) &
  _pid=$!
  ( sleep "$STAGE_TIMEOUT" && kill "$_pid" 2> /dev/null ) &
  _wd=$!
  wait "$_pid"
  _st=$?
  kill "$_wd" 2> /dev/null
  wait "$_wd" 2> /dev/null
  [ "$_st" -ne 0 ] && return 1
  [ -s "$3" ] || return 1
  # ask.sh พิมพ์ error message ของ proxy ออก stdout พร้อม exit 0 — จับไว้ตรงนี้
  if grep -q "all backends failed\|invalid request body" "$3"; then
    return 1
  fi
  return 0
}

mock_answer() { # out-file → เลือก mock ตามชื่อไฟล์ปลายทาง
  case "$1" in
    *1-spec.md) cp "$here/mock/1-spec.md" "$1" ;;
    *2-design.md) cp "$here/mock/2-design.md" "$1" ;;
    *dev-loop1.md) cp "$here/mock/dev-loop1.md" "$1" ;;
    *dev-loop*.md) cp "$here/mock/dev-loop2.md" "$1" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# extract_html: ดึง code block แรกจากคำตอบ Dev → เซฟลง sandbox เท่านั้น
# ---------------------------------------------------------------------------

extract_html() { # reply-file, out-file
  awk 'f && /^```/ { exit } f { print } /^```/ { f = 1 }' "$1" > "$2"
  if [ ! -s "$2" ] && grep -qi '<html' "$1"; then
    cp "$1" "$2" # ไม่มี fence แต่เป็นเอกสาร HTML ทั้งก้อน — ใช้ตรง ๆ
  fi
}

# ---------------------------------------------------------------------------
# verify (Observe): เช็คของจริง ไม่เชื่อคำพูดของ Dev — 3 ชั้น:
#   1) base: ไฟล์มีจริง + เอกสารสมบูรณ์
#   2) AC จาก spec: PO เขียน "- AC: <คำอธิบาย> => <ERE>" แล้ว verify grep ตามนั้น
#      (checklist จึงเปลี่ยนตาม idea เอง ไม่ hardcode ต่อหน้า login)
#   3) runtime "ตา": render ด้วย headless Chrome ดู DOM จริง + console error
# ---------------------------------------------------------------------------

PASS=1

check() { # label, grep -Ei pattern
  if grep -Eqi "$2" "$html" 2> /dev/null; then
    echo "- OK   $1" >> "$verdict"
  else
    echo "- FAIL $1" >> "$verdict"
    PASS=0
  fi
}

find_chrome() {
  if [ -n "${CHROME_BIN:-}" ] && [ -x "$CHROME_BIN" ]; then
    echo "$CHROME_BIN"
    return
  fi
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    if [ -x "$c" ]; then
      echo "$c"
      return
    fi
  done
  command -v google-chrome chromium 2> /dev/null | head -1
}

render_page() { # ใช้ globals: chrome/html/dom/clog — เรียกผ่าน watchdog เท่านั้น
  "$chrome" --headless=new --disable-gpu --enable-logging=stderr \
    --virtual-time-budget=3000 --dump-dom "file://$html" > "$dom" 2> "$clog"
}

verify_runtime() {
  chrome=$(find_chrome)
  if [ -z "$chrome" ]; then
    echo "- SKIP runtime (ไม่พบ Chrome — ตั้ง CHROME_BIN ให้ชี้ binary ได้)" >> "$verdict"
    return
  fi
  dom="$run_dir/.render-dom.html"
  clog="$run_dir/.render-console.log"
  ( render_page ) &
  _rp=$!
  ( sleep 30 && kill "$_rp" 2> /dev/null ) &
  _rw=$!
  wait "$_rp"
  _rs=$?
  kill "$_rw" 2> /dev/null
  wait "$_rw" 2> /dev/null
  if [ "$_rs" -ne 0 ] || [ ! -s "$dom" ]; then
    echo "- FAIL runtime: render ไม่สำเร็จ (Chrome ล้ม/ค้าง หรือ DOM ว่าง)" >> "$verdict"
    PASS=0
    return
  fi
  _errs=$(grep -c 'Uncaught\|:ERROR:CONSOLE' "$clog" 2> /dev/null || true)
  if [ "${_errs:-0}" -gt 0 ]; then
    echo "- FAIL runtime: console มี error $_errs รายการ:" >> "$verdict"
    grep 'Uncaught\|:ERROR:CONSOLE' "$clog" | head -3 | sed 's/^/    /' >> "$verdict"
    PASS=0
  else
    echo "- OK   runtime: render ได้ (DOM $(wc -c < "$dom" | tr -d ' ') bytes) console สะอาด" >> "$verdict"
  fi
}

verify() {
  : > "$verdict"
  echo "# Verify — $(date '+%F %H:%M:%S')" >> "$verdict"
  PASS=1
  if [ ! -s "$html" ]; then
    echo "- FAIL ไฟล์ 3-code/index.html ว่างหรือไม่ถูกสร้าง" >> "$verdict"
    PASS=0
  else
    check "เปิดเอกสาร <html>" "<html"
    check "ปิดเอกสาร </html>" "</html>"
    # Acceptance Criteria จาก spec — สายพานเดียวกับที่ Dev อ่าน
    grep '^- AC:' "$spec" > "$run_dir/.ac-list" 2> /dev/null || true
    while IFS= read -r _line; do
      _body=${_line#- AC: }
      case "$_body" in
        *" => "*)
          check "${_body%% => *}" "${_body##* => }"
          ;;
        *)
          echo "- WARN AC ไม่มี pattern (ข้าม): $_body" >> "$verdict"
          ;;
      esac
    done < "$run_dir/.ac-list"
    verify_runtime
  fi
  echo "" >> "$verdict"
  if [ "$PASS" = "1" ]; then
    echo "VERDICT: PASS" >> "$verdict"
  else
    echo "VERDICT: FAIL" >> "$verdict"
  fi
}

# ---------------------------------------------------------------------------
# run: 0-idea → 1-spec → 2-design → (3-code → 4-verdict)×loop
# ---------------------------------------------------------------------------

echo "$idea" > "$run_dir/0-idea.md"
{
  echo "# STATE — $(basename "$run_dir")"
  echo "idea: $idea"
  echo "mode: $([ "${MOCK:-}" = "1" ] && echo mock || echo live) | timeout ${STAGE_TIMEOUT}s/stage | max ${MAX_LOOPS} loops"
  echo ""
} > "$state"
echo "▶ run: $run_dir"

# Stage 1 — PO (Plan)
note_state PO run "อ่าน 0-idea.md"
{
  cat "$here/roles/po.md"
  printf "\n\n## IDEA\n%s\n" "$idea"
} > "$run_dir/.prompt-po.md"
ask plan "$run_dir/.prompt-po.md" "$run_dir/1-spec.md" || die PO
# fail fast: spec ที่ไม่มี AC แบบ machine-checkable = Verify ตาบอด อย่าเผา Dev ต่อ
if ! grep -q '^- AC: .* => ' "$run_dir/1-spec.md"; then
  lesson "PO ไม่เขียน AC รูปแบบ '- AC: <ข้อความ> => <pattern>' — หยุดก่อนเข้า Dev"
  die PO
fi
note_state PO done "เขียน 1-spec.md ($(grep -c '^- AC:' "$run_dir/1-spec.md") AC)"
echo "  ✓ 1/4 PO → 1-spec.md"

# Stage 2 — Designer (Plan)
note_state DESIGNER run "อ่าน 1-spec.md"
{
  cat "$here/roles/designer.md"
  printf "\n\n## SPEC\n"
  cat "$run_dir/1-spec.md"
} > "$run_dir/.prompt-designer.md"
ask plan "$run_dir/.prompt-designer.md" "$run_dir/2-design.md" || die DESIGNER
note_state DESIGNER done "เขียน 2-design.md"
echo "  ✓ 2/4 Designer → 2-design.md"

# Stage 3+4 — Dev (Act) ↔ Verify (Observe) พร้อม Reflect ผ่าน verdict
loop=1
while [ "$loop" -le "$MAX_LOOPS" ]; do
  note_state DEV "loop$loop" "อ่าน spec+design$([ "$loop" -gt 1 ] && echo '+verdict')"
  {
    cat "$here/roles/dev.md"
    printf "\n\n## SPEC\n"
    cat "$run_dir/1-spec.md"
    printf "\n\n## DESIGN\n"
    cat "$run_dir/2-design.md"
    if [ "$loop" -gt 1 ]; then
      printf "\n\n## VERDICT (ผล verify รอบก่อน — แก้ทุกข้อ FAIL)\n"
      cat "$verdict"
      printf "\n\n## โค้ดรอบก่อน\n\`\`\`html\n"
      cat "$html"
      printf "\`\`\`\n"
    fi
  } > "$run_dir/.prompt-dev.md"
  ask code "$run_dir/.prompt-dev.md" "$run_dir/3-code/dev-loop$loop.md" || die DEV
  extract_html "$run_dir/3-code/dev-loop$loop.md" "$html"
  note_state DEV "loop$loop" "เขียน 3-code/index.html"
  echo "  ✓ 3/4 Dev loop $loop → 3-code/index.html"

  verify
  if grep -q "^VERDICT: PASS" "$verdict"; then
    note_state VERIFY "loop$loop" "PASS → 4-verdict.md"
    echo "  ✓ 4/4 Verify: PASS (loop $loop)"
    echo "✓ เสร็จ ไม่มีคนแตะระหว่างทาง — เปิดดู: $html"
    exit 0
  fi
  note_state VERIFY "loop$loop" "FAIL → ส่ง verdict กลับ Dev"
  lesson "loop $loop FAIL: $(grep '^- FAIL' "$verdict" | tr '\n' ' ' | tr -s ' ')"
  echo "  ✗ 4/4 Verify: FAIL (loop $loop) → ส่งกลับ Dev"
  loop=$((loop + 1))
done

note_state PIPELINE stop "ครบ $MAX_LOOPS loops แล้วยังไม่ผ่าน (kill switch)"
lesson "หยุดหลัง $MAX_LOOPS loops — งานนี้ต้องการมนุษย์ (ดู $verdict)"
echo "✗ ครบ $MAX_LOOPS loops แล้วยังไม่ผ่าน — kill switch ทำงาน ต้องมีคนดู"
exit 2
