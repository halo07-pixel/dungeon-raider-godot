# tools/balance

`class_calc.gd` – máy tính cân bằng tĩnh (không bot, không chạy game): DPS lý thuyết của class/vũ khí và thời gian hạ boss theo tầng, đọc thẳng dữ liệu game.

    godot --headless --path . --script tools/balance/class_calc.gd -- --out tools/balance/class_calc_result.md [--acc 0.75] [--rarity common]

Kết quả mẫu: `class_calc_result.md`. Mô hình một mục tiêu, bỏ qua buff/trạng thái/AOE/di chuyển; chỉ đọc TƯƠNG ĐỐI giữa các class.

`inflation_calc.gd` – đo lạm phát sức mạnh: hệ số sát thương/tốc độ/chí mạng/độ bền của 3 mức build (casual, focused, cap) so với HP, giáp, sát thương quái theo tầng; thời gian hạ boss theo class với build focused.

    godot --headless --path . --script tools/balance/inflation_calc.gd -- --out tools/balance/inflation_result.md

Giả định build (số lượt chọn buff, vũ khí theo tầng) là ước lượng; cần đối chiếu với telemetry ván thật. Không đo DoT, chuỗi sét, nổ khi chết, đạn xuyên/AOE, hút máu thực tế.
