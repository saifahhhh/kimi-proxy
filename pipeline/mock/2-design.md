# Design — หน้า Login (mock)

## Design Tokens
- palette: background #0f1117 → gradient #1a1f2b, surface #161a24, primary #2f6fed,
  text #e6e8ee, muted #9aa3b2, error #ff6b6b, success #51cf66
- typography: -apple-system/'Segoe UI', heading 24px/600, body 15px, caption 13px
- spacing: 8 / 12 / 16 / 24 / 32px
- radius: card 16px, input/ปุ่ม 10px; shadow: 0 20px 60px rgba(0,0,0,.45)

## Layout
card กว้าง 400px กึ่งกลางจอทั้งสองแกน บนพื้น gradient มืด
ภายใน: โลโก้/ชื่อ app → หัวข้อ → form (email, password, ปุ่ม) → ลิงก์ลืมรหัสผ่าน
ช่องไฟระหว่างกลุ่ม 24px, ระหว่าง field 16px

## Components
- input: สูง 44px, พื้น surface, ขอบ 1px #2a3245, focus ขอบ primary
- ปุ่ม: เต็มกว้าง สูง 46px พื้น primary ตัวหนังสือขาว hover สว่างขึ้น 8%
- error text: caption สี error ใต้ field

## States
- loading: ปุ่ม opacity .6 + ข้อความเปลี่ยน
- error: ขอบ input เป็นสี error + ข้อความใต้ field
- success: กล่องเขียว (success) แทน form
