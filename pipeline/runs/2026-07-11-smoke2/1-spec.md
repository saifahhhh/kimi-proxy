# Spec — หน้า Login (mock)

## Goal
หน้า login สวย สะอาด สำหรับ web app ทั่วไป ให้ผู้ใช้เข้าสู่ระบบด้วย email + password

## Assumptions
- ภาษา UI: ไทย, ชื่อ product: "My App"
- ไม่มี backend — mock ผล submit ฝั่ง client

## Scope
- ทำ: form login ไฟล์เดียว (HTML + inline CSS/JS), validation, 4 states
- ไม่ทำ: สมัครสมาชิก, ลืมรหัสผ่าน (เป็นลิงก์เฉย ๆ), backend จริง

## UI Elements
- input email (type=email, required)
- input password (type=password, required, อย่างน้อย 8 ตัว)
- ปุ่ม submit "เข้าสู่ระบบ"
- ลิงก์ "ลืมรหัสผ่าน?"

## States
- default: form ว่าง ปุ่ม active
- loading: ปุ่ม disabled ข้อความ "กำลังเข้าสู่ระบบ..."
- error: กรอบแดง + ข้อความ error ใต้ field
- success: แสดงข้อความ "เข้าสู่ระบบสำเร็จ"

## Behavior
- validate ตอน submit: email format, password ≥ 8 ตัว
- submit สำเร็จ (mock 1 วินาที) → state success

## Acceptance Criteria
- AC: มี form => <form
- AC: มี input password => type=["']?password
- AC: มี input email => type=["']?email
- AC: มีปุ่ม submit => <button|type=["']?submit
- AC: มี styling ในไฟล์ => <style|style=
- AC: มี error state => error
