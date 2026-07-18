# STATE — 2026-07-11-smoke
idea: หน้า login สวยๆ
mode: mock | timeout 180s/stage | max 3 loops

- 13:09:34 | PO       | run    | อ่าน 0-idea.md
- 13:09:34 | PO       | done   | เขียน 1-spec.md
- 13:09:34 | DESIGNER | run    | อ่าน 1-spec.md
- 13:09:34 | DESIGNER | done   | เขียน 2-design.md
- 13:09:34 | DEV      | loop1  | อ่าน spec+design
- 13:09:34 | DEV      | loop1  | เขียน 3-code/login.html
- 13:09:34 | VERIFY   | loop1  | FAIL → ส่ง verdict กลับ Dev
- 13:09:34 | DEV      | loop2  | อ่าน spec+design+verdict
- 13:09:34 | DEV      | loop2  | เขียน 3-code/login.html
- 13:09:34 | VERIFY   | loop2  | PASS → 4-verdict.md
