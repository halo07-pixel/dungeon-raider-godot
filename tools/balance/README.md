# tools/balance

`class_calc.gd` – máy tính cân bằng tĩnh (không bot, không chạy game): DPS lý thuyết của class/vũ khí và thời gian hạ boss theo tầng, đọc thẳng dữ liệu game.

    godot --headless --path . --script tools/balance/class_calc.gd -- --out tools/balance/class_calc_result.md [--acc 0.75] [--rarity common]

Kết quả mẫu: `class_calc_result.md`. Mô hình một mục tiêu, bỏ qua buff/trạng thái/AOE/di chuyển; chỉ đọc TƯƠNG ĐỐI giữa các class.
