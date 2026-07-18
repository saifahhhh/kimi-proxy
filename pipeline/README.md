# pipeline — Agentic Loop (idea → verified page, ไม่มีคนกลางทาง)

วงจร **Plan → Act → Observe → Reflect**: PO และ Designer วางแผน (Claude),
Dev ลงมือ (Kimi), Verify สังเกตของจริง แล้วส่ง verdict กลับให้ Dev
แก้เอง วนจนผ่านหรือครบลิมิต — สายพานส่งของคือไฟล์ .md ในโฟลเดอร์ run

Verify มี 3 ชั้น:
1. **base** — ไฟล์มีจริง + เอกสาร `<html>...</html>` สมบูรณ์
2. **AC จาก spec** — PO เขียน `- AC: <ข้อความ> => <ERE>` ใน `1-spec.md` แล้ว verify
   grep ตามนั้น (checklist เปลี่ยนตาม idea เอง ไม่ hardcode; spec ไม่มี AC = ตายตั้งแต่ stage PO)
3. **runtime "ตา"** — render `3-code/index.html` ด้วย headless Chrome จริง:
   DOM ว่าง หรือ console มี error (Uncaught/console.error) = FAIL
   (ไม่เจอ Chrome → SKIP พร้อมบอกวิธีตั้ง `CHROME_BIN`)

```
pipeline/
├── pipeline.sh        orchestrator (4 stage + feedback loop + kill switches)
├── roles/             system prompt ของแต่ละ stage (po / designer / dev)
├── mock/              คำตอบสำเร็จรูปสำหรับ MOCK=1 (loop1 จงใจพลาด → พิสูจน์ self-correct)
├── LESSONS.md         ความจำรวมของ loop: เคยพลาดอะไร (append ทุกครั้งที่ verify FAIL)
└── runs/YYYY-MM-DD-<name>/
    ├── 0-idea.md      ← จุดเดียวที่คนแตะ
    ├── 1-spec.md      ← PO เขียน, Designer อ่าน
    ├── 2-design.md    ← Designer เขียน, Dev อ่าน
    ├── 3-code/        ← index.html + คำตอบดิบของ Dev แต่ละ loop
    ├── 4-verdict.md   ← ผล verify (PASS/FAIL รายข้อ)
    └── STATE.md       ← ใครทำอะไรถึงไหนแล้ว (timeline)
```

## ใช้งาน

```sh
# ทดสอบ plumbing ก่อน (ไม่เรียก LLM ไม่เสีย token):
MOCK=1 ./pipeline.sh "หน้า login สวยๆ" smoke

# ของจริง (proxy ต้องรันอยู่ + claude/kimi login แล้ว):
STAGE_TIMEOUT=300 ./pipeline.sh "หน้า login สวยๆ" login
```

## Kill switches (เบรกฉุกเฉิน — ไม่ใช่คนกลางทาง)

| จุด | เบรก | กันอะไร |
|---|---|---|
| ทุกการเรียก LLM | `STAGE_TIMEOUT` (default 180s) | LLM ค้าง |
| การเขียนไฟล์ | เขียนได้เฉพาะใต้ `runs/<run>/` โดยสคริปต์เอง + Kimi รัน read-only | เหตุการณ์ `pub fn add` ซ้ำรอย |
| feedback loop | `MAX_LOOPS` (default 3) | fail→fix→fail ไม่จบ (diverge) |

## วัดผล "ไม่มีคน"

1. คนแตะกี่ครั้งระหว่างทาง? → เป้า 0 (แตะแค่พิมพ์ idea + ดูผล)
2. กี่ loop กว่าจะ PASS? → ดู STATE.md (ยิ่งน้อยยิ่งใกล้ฝัน)
3. หน้าออกมา "สวย + ใช้ได้" ไหม? → taste check โดยคน — ถ้าใช้ได้แต่ไม่สวย
   คือ insight ว่า AI ทำ floor ได้แต่ ceiling ยังต้องการคน
