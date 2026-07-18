# LESSONS — ความจำรวมของ pipeline (append-only)

รูปแบบ: `- <วันที่> <run> | [mock]? <บทเรียน>` — บรรทัด `[mock]` มาจากรอบทดสอบ plumbing
(ล้าง noise จากรอบทดสอบ kill switch 2026-07-11 ออกแล้ว — สรุปเหตุการณ์นั้น: mock Dev
แก้ "error state" ไม่ได้ 3 รอบติด → kill switch หยุดถูกต้องตามออกแบบ)
- 2026-07-11 2026-07-11-smoke2 | [mock] loop 1 FAIL: - FAIL มี input password - FAIL มี error state 
