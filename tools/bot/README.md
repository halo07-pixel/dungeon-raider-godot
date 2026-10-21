# Bot kiểm thử cân bằng (tools/bot)

Bot tự chơi Dungeon Raider (headless) để thu số liệu cân bằng. **Không thuộc game chính.**
Bot điều khiển Player qua đúng các cổng của người chơi (Input.action_press, `Player.ai_aim_point`,
`_start_roll`, `class_skill.try_activate`) và dùng file save riêng `user://bot_save.dat`.

## Chạy

```
godot --headless --path . --script tools/bot/run_bot.gd -- --runs 5 --class ranger,mage --speed 10 --max-min 15
godot --headless --path . --script tools/bot/run_bot.gd -- --runs 5 --heat-compare        # mỗi class: Heat tắt vs bật
godot --headless --path . --script tools/bot/run_bot.gd -- --runs 1 --class ranger --trace 1   # in trạng thái mỗi 5 giây
```

Tham số: `--runs` (ván/cấu hình), `--class a,b`, `--heat x,y`, `--heat-compare`, `--speed` (tăng tốc, mặc định 6),
`--max-min` (trần phút mô phỏng/ván), `--max-floor`, `--seed`, `--out file.json`, `--trace 1`.
Mỗi ván in một dòng (tầng, kết cục, thời gian, hạ bao nhiêu, số lần lăn né, "săn", kẹt, kẻ hạ gục) rồi bảng tổng hợp
theo class + Heat.

## Bot v1 làm được gì
- Dọn phòng bằng cách đi theo đường tìm được (A*), giữ khoảng cách với quái tầm xa, áp sát quái hay lùi (cung thủ/pháp sư),
  tránh vùng nguy hiểm đang báo trước, lăn né đạn/chạm sát (có xác suất sai), dùng kỹ năng Q khi có >= 3 quái hoặc trùm,
  chọn buff theo bậc hiếm + synergy, nhặt máu/xu gần, đi cổng sang tầng kế, chống kẹt, "săn" khi không hạ được con nào quá lâu.

## Giới hạn hiện tại (cần nâng cấp dần)
- Bot yếu hơn người chơi thật: chưa ngắm đón đầu, né trùm còn thô, không dùng Forge/Altar/rương/đổi vũ khí, không tự
  chọn vũ khí tốt hơn, chưa biết các chiêu đặc biệt của từng trùm. **Số "tầng chết" tuyệt đối vì thế KHÔNG phải độ khó
  thật** — chỉ có ý nghĩa để so sánh giữa các cấu hình (class, Heat) khi chạy nhiều ván cùng bot.
- Kết quả có nhiễu ngẫu nhiên lớn: nên chạy >= 10 ván mỗi cấu hình.

## Hướng nâng cấp
1. Ngắm đón đầu + né theo từng chiêu của trùm. 2. Dùng vật phẩm/vũ khí (Forge, rương, đổi vũ khí theo DPS).
3. Chọn buff theo build. 4. Hồ sơ "khó": cho bot phản ứng nhanh/chậm để mô phỏng người mới và cao thủ.
