[33mWarning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.[39m
## Design Tokens

- **palette:**
  - background gradient: `#0F172A` → `#1E3A5F` → `#0E7490` (มุม 135°, ทางแนวทแยงซ้ายบน→ขวาล่าง)
  - surface (card): `#FFFFFF`
  - primary: `#0E7490` · primary-hover: `#155E75` · primary-disabled: `#94A3B8`
  - text หลัก: `#0F172A` · muted: `#64748B`
  - border ปกติ: `#CBD5E1` · border focus: `#0E7490`
  - error: `#DC2626` · error-bg (banner): `#FEF2F2` · error-border: `#FECACA`
  - success: `#15803D` · success-bg: `#F0FDF4`
  - contrast: ตัวอักษร `#0F172A` บน `#FFFFFF` และ `#FFFFFF` บนปุ่ม `#0E7490` ผ่านระดับ AA ทั้งคู่
- **typography:**
  - font stack: `'Noto Sans Thai', 'Sarabun', -apple-system, 'Segoe UI', Roboto, sans-serif` (โหลด Noto Sans Thai จาก Google Fonts weight 400/500/700 — อนุญาตตาม AC)
  - heading (ชื่อ product): 24px / 700
  - subheading (คำโปรย): 14px / 400 / สี muted
  - body + input + ปุ่ม: 16px / 400 (ปุ่ม 500)
  - label: 14px / 500 · caption/error รายฟิลด์: 13px / 400
  - line-height ทั้งหน้า: 1.5 (ตัวไทยมีสระบน-ล่าง อย่าต่ำกว่านี้)
- **spacing:** scale 4 / 8 / 12 / 16 / 24 / 32 px — padding card 32px (จอ ≤360px ลดเหลือ 20px), ช่องว่างระหว่าง field 16px, ระหว่างกลุ่ม (หัว→ฟอร์ม, ฟอร์ม→ปุ่ม) 24px
- **radius / shadow:**
  - radius: card 16px · input/ปุ่ม 8px · checkbox 4px
  - shadow card: `0 20px 40px rgba(15, 23, 42, 0.25)`
  - focus ring: `0 0 0 3px rgba(14, 116, 144, 0.25)` (ใช้ร่วมกับเปลี่ยนสี border)

## Layout

หน้าเดียว ไม่มี scroll ในจอปกติ:

- พื้นหลัง: gradient เต็ม viewport (`min-height: 100vh`), จัด card กึ่งกลางทั้งแนวตั้ง-แนวนอนด้วย flexbox
- **card:** พื้น surface, กว้าง `100%` สูงสุด `400px`, มี margin ข้าง 16px กันชนขอบจอเล็ก (รองรับ ≥320px), padding 32px, radius 16px + shadow ตาม tokens
- ลำดับ element ใน card บนลงล่าง:
  1. โลโก้ตัวอักษร: วงกลม 48px พื้น primary ตัวอักษร "F" สีขาว กึ่งกลาง — ห่างจากหัวข้อ 16px
  2. หัวข้อ "Forward Insight" (heading, กึ่งกลาง) + คำโปรยใต้ 8px: "เข้าสู่ระบบเพื่อใช้งาน" (subheading, กึ่งกลาง)
  3. ห่าง 24px → **error banner** (ซ่อนไว้ default) — กล่องพื้น error-bg ขอบ error-border ตัวอักษร error, padding 12px, radius 8px
  4. ห่าง 16px → field อีเมล (label เหนือ input 8px, error รายฟิลด์ใต้ input 4px)
  5. ห่าง 16px → field รหัสผ่าน (โครงเดียวกัน + ปุ่ม toggle ในตัว input ชิดขวา)
  6. ห่าง 12px → แถวเดียวกัน 2 ฝั่ง (flex, space-between): checkbox "จดจำฉัน" ชิดซ้าย · ลิงก์ "ลืมรหัสผ่าน?" ชิดขวา
  7. ห่าง 24px → ปุ่ม submit "เข้าสู่ระบบ" กว้างเต็ม card
  8. ห่าง 24px → บรรทัดกึ่งกลาง (caption, muted): "ยังไม่มีบัญชี? " + ลิงก์ "สมัครสมาชิก"
- **success view:** อยู่ใน card เดียวกัน แทนที่ฟอร์มทั้งก้อน (ซ่อนฟอร์ม แสดงก้อนนี้) — ดูรายละเอียดใน States
- responsive: ไม่มี breakpoint พิเศษนอกจากลด padding card ที่จอ ≤360px — layout คอลัมน์เดียวรอดเองถึง 320px

## Components

- **input (อีเมล / รหัสผ่าน):** กว้างเต็ม, สูง 48px, padding แนวนอน 14px, พื้นขาว, ขอบ 1px `#CBD5E1`, radius 8px, ตัวอักษร 16px สี text — placeholder สี muted ("you@example.com" / "อย่างน้อย 8 ตัวอักษร")
  - focus: border เปลี่ยนเป็น primary + focus ring ตาม tokens (`outline: none` ได้เพราะมี ring แทน)
  - invalid (หลังตรวจ): border เป็น error `#DC2626` + ข้อความ error ใต้ field
- **ปุ่ม toggle รหัสผ่าน:** `type="button"` วางซ้อนใน field ชิดขวา (input เผื่อ padding-right 48px), ขนาดกดได้ 40×40px, ไม่มีพื้น/ขอบ, ไอคอนตา SVG inline สี muted (มี `aria-label="แสดงรหัสผ่าน"` สลับเป็น "ซ่อนรหัสผ่าน") — hover: ไอคอนเป็นสี text · focus-visible: focus ring เดียวกับ input · กดแล้วสลับ `type` password↔text และสลับไอคอนตา/ตาขีดฆ่า
- **checkbox "จดจำฉัน":** 18×18px, accent-color เป็น primary, label 14px สี text คลิกได้ทั้ง label
- **ลิงก์ ("ลืมรหัสผ่าน?", "สมัครสมาชิก"):** สี primary, 14px, ไม่มีขีดเส้นใต้ default — hover: ขีดเส้นใต้ · focus-visible: focus ring
- **ปุ่ม submit "เข้าสู่ระบบ":** กว้างเต็ม, สูง 48px, พื้น primary ตัวอักษรขาว 16px/500, radius 8px, ไม่มีขอบ, cursor pointer
  - hover: พื้น primary-hover · active: ขยับลง 1px · focus-visible: focus ring
  - disabled (ตอน loading): พื้น primary-disabled, cursor not-allowed
- **spinner:** วงกลม 18px ขอบ 2px สีขาวโปร่ง 30% + เสี้ยวขาวทึบ หมุนด้วย CSS animation, วางหน้าข้อความในปุ่ม ห่าง 8px
- **error banner / error รายฟิลด์:** banner ตามสเปคใน Layout ข้อ 3 · error รายฟิลด์เป็นตัวอักษร 13px สี error ใต้ input (แต่ละ field มีที่ของตัวเอง, ซ่อนเมื่อไม่มี error)

## States

- **default:** banner และ error รายฟิลด์ซ่อนทั้งหมด, ปุ่ม enabled ข้อความ "เข้าสู่ระบบ", input ขอบปกติ
- **validation error (ก่อนยิง mock):** ตรวจตอน submit — อีเมลว่าง/รูปแบบผิด → ใต้ field: "กรุณากรอกอีเมลให้ถูกต้อง" · รหัสผ่านว่างหรือสั้นกว่า 8 → ใต้ field: "รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร" — field ที่ผิดขอบเป็นสี error, focus ไป field แรกที่ผิด, **ไม่เข้า loading** · error หายเมื่อผู้ใช้พิมพ์แก้ใน field นั้น
- **loading:** เข้าเมื่อ validation ผ่าน — ปุ่ม disabled + แสดง spinner + ข้อความเปลี่ยนเป็น "กำลังเข้าสู่ระบบ…", input ทุกช่อง disabled, banner เดิม (ถ้ามี) ซ่อน, หน่วง ~1000ms จำลอง network
- **error (mock auth ไม่ผ่าน):** ออกจาก loading กลับ default + แสดง error banner: "อีเมลหรือรหัสผ่านไม่ถูกต้อง" (พื้น error-bg ขอบ error-border ตัวอักษร error), ฟอร์มกลับมากดได้ ค่าที่กรอกคงอยู่
- **success (demo@example.com / password123):** ซ่อนฟอร์มทั้งก้อน แสดงใน card แทน: ไอคอนวงกลม 56px พื้น success-bg เครื่องหมายถูก SVG สี success กึ่งกลาง → ห่าง 16px → หัวข้อ "เข้าสู่ระบบสำเร็จ" (20px/700 สี text) → ห่าง 8px → "ยินดีต้อนรับกลับมา คุณ demo@example.com" (14px สี muted) — ไม่มีปุ่มเพิ่ม ไม่ขยาย scope

