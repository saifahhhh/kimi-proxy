[33mWarning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.[39m
# Task: หน้า Login สวยๆ (single-file HTML)

## Goal
สร้างหน้า login ภาษาไทยที่สวยงาม ทันสมัย เป็น **ไฟล์ HTML เดียว** (inline CSS/JS, ไม่มี backend — mock ผลลัพธ์ฝั่ง client) สำหรับ product สมมติชื่อ "Forward Insight"

## Plan (phased)

1. **Spec (PO)** — ตัดสินใจแทนมนุษย์และจดเป็น Assumptions:
   - ภาษา UI: ไทย · ชื่อ product: "Forward Insight" · ไม่มี backend จริง
   - Mock auth ฝั่ง client: อีเมล `demo@example.com` / รหัสผ่าน `password123` = สำเร็จ, อื่นๆ = ล้มเหลว
   - UI elements ครบ: `input type="email"` (อีเมล), `input type="password"` (รหัสผ่าน) + ปุ่ม toggle แสดง/ซ่อนรหัสผ่าน, checkbox "จดจำฉัน", ลิงก์ "ลืมรหัสผ่าน?" (href="#"), ปุ่ม `type="submit"` "เข้าสู่ระบบ", ลิงก์ "สมัครสมาชิก" (href="#")
   - States: default / loading (ปุ่ม disabled + spinner ~1 วินาทีจำลอง network) / error (ข้อความแดงใต้ field หรือ banner) / success (ซ่อนฟอร์ม แสดงข้อความต้อนรับ)

2. **Design (Designer)** — layout card กึ่งกลางจอบนพื้นหลัง gradient, font ไทยอ่านง่าย (เช่น system font stack + `Noto Sans Thai` fallback), responsive ≥320px, focus state ชัดเจน, contrast ผ่านระดับอ่านได้

3. **Build (Dev)** — เขียน `index.html` ไฟล์เดียวใน run folder:
   - Validation ฝั่ง client: อีเมล format ถูกต้อง (required), รหัสผ่าน ≥8 ตัวอักษร (required) — แสดง error รายฟิลด์เป็นภาษาไทย, ห้าม submit ถ้าไม่ผ่าน
   - Submit → เข้า loading state → เช็คกับ mock credentials → success หรือ error ("อีเมลหรือรหัสผ่านไม่ถูกต้อง")
   - ไม่มี `console.log` ในโค้ดส่งมอบ

4. **Verify** — เช็คจากตัวไฟล์ HTML ตาม Acceptance Criteria:
   - [ ] มี `<input type="email">` และ `<input type="password">`
   - [ ] มีปุ่ม `type="submit"` ข้อความ "เข้าสู่ระบบ"
   - [ ] มี checkbox "จดจำฉัน" และลิงก์ "ลืมรหัสผ่าน?"
   - [ ] มี toggle แสดง/ซ่อนรหัสผ่าน
   - [ ] มี `<html lang="th">` และ meta viewport
   - [ ] CSS/JS อยู่ inline ทั้งหมด (ไม่มี external script/stylesheet ยกเว้น Google Fonts ถ้าใช้)
   - [ ] มีโค้ดแสดง error state และ success state (ค้นเจอข้อความ error ภาษาไทยในไฟล์)
   - [ ] submit ด้วยฟิลด์ว่างไม่ผ่าน validation (มี required/JS guard)

## Constraints
- ไฟล์เดียวเท่านั้น (HTML + inline CSS/JS), ไม่มี backend, mock ทุกอย่างฝั่ง client
- เขียนไฟล์ได้เฉพาะใน `pipeline/runs/<date>-<name>/` ตามกติกา pipeline
- Thai UI text, English code/identifiers · ไม่มี debug prints · ไม่ commit secrets (ตาม [[project/conventions]])
- ห้ามถามกลับ — ตัดสินใจด้วย sensible defaults แล้วจดใน Assumptions

## Done
- [ ] phase 1 — spec ครบ (Assumptions, UI elements, States, Behavior, AC)
- [ ] phase 2 — design ตัดสินใจ layout/สี/font แล้ว
- [ ] phase 3 — `index.html` เขียนเสร็จ ผ่าน validation flow ครบทุก state
- [ ] phase 4 — Acceptance Criteria ผ่านครบทุกข้อจากการตรวจตัวไฟล์

