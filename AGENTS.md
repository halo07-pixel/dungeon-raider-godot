# Dungeon Raider — quy tắc cho AI (Godot 4.7)

Áp dụng cho mọi agent làm việc trong repo này. Dựa trên Ponytail ("senior dev lười": giải đủ bài toán bằng ít code mới nhất) và những lỗi thật đã gặp trong dự án.

## 0. Thứ tự ưu tiên (không đảo)
1. **Quy trình 5 bước của dự án** (đề xuất → duyệt → nhánh feature + push → chờ duyệt gộp → gộp vào `main`). Không bao giờ push thẳng `main`, dù chỉ sửa một dòng.
2. Quy tắc Godot ở mục 3.
3. Quy tắc "ít code" ở mục 1–2.

## 1. Ít code nhưng làm đủ việc
Trước khi viết: đọc code liên quan, liệt kê mọi chỗ thay đổi phải chạm tới (nơi gọi, test, scene, `project.godot`, file `.uid`, save/load). Lấy lựa chọn đầu tiên chạy được:
1. Có cần tồn tại không? Bỏ tính năng/option/linh hoạt không ai yêu cầu và nói rõ một dòng.
2. Repo đã có helper/component/pattern chưa? Dùng theo cách code xung quanh đang dùng (vd `SkillTree`, `Heat`, `RunTelemetry` là static helper trên RefCounted).
3. Godot đã có sẵn (node, signal, `Timer`, `Tween`, `AStarGrid2D`)? Dùng nó.
4. Không thêm addon/dependency cho vài dòng.
5. Ít nhất có thể, nhưng không bỏ: kiểm tra dữ liệu ở biên (save file, input), xử lý lỗi tránh mất dữ liệu, âm thanh/UI người chơi cần.
- Không thêm abstraction, wrapper, tham số, config "để sau". Xoá code thừa tốt hơn thêm.
- Sửa lỗi: grep mọi nơi gọi hàm trước khi sửa, sửa nguyên nhân gốc một lần ở code dùng chung.
- Hàm đổi chữ ký (vd `take_damage`): grep **mọi** nơi gọi, kể cả của kẻ địch/boss/đạn. Lỗi `source` làm đạn người chơi hết gây sát thương đã xảy ra vì bỏ bước này.
- Logic mới có nhánh/vòng lặp/tiền/save: để lại một test headless nhỏ (`godot --headless --path . --script ...`).
- Đường tắt có giới hạn đã biết: `# shortcut: <giới hạn>, <khi nào nâng cấp>`. Dùng `/ponytail-debt` để gom thành sổ nợ.

## 2. Báo cáo
Cuối mỗi lần làm: nói ngắn gọn đã đổi file nào, điều gì chưa kiểm tra, rủi ro cần biết. Không kể lại từng bước.

## 3. Quy tắc Godot (mỗi điều từng gây lỗi thật)
- **Call down, signal up.** Node cha gọi hàm node con; node con báo lên cha bằng Signal. Cấm `get_parent().get_parent()`.
- Logic vật lý ở `_physics_process`; UI và âm thanh qua Signal hoặc hàm riêng, không nhồi chung một hàm.
- Thêm `Area2D`/`CollisionShape2D` hay đổi `global_position` trong callback vật lý: dùng `call_deferred` / `set_deferred` (lỗi "Can't change state while flushing queries", từng gặp ở nổ Volatile).
- `set_script()` phải trước khi gán biến của script đó.
- Cộng dồn số thực: `10 × 0.1 = 0.9999`; so sánh dùng ngưỡng (`>= 0.9999`), không `==`.
- `Engine.time_scale` bị hitstop/`reset_run` đặt lại; mô phỏng nhanh phải ép lại mỗi khung và nâng `Engine.max_physics_steps_per_frame`.
- Script chạy bằng `--script` không thấy autoload `Global` lúc biên dịch: lấy qua `root.get_node("Global")` hoặc `load()` lúc chạy.
- Đổi ảnh `.png`: cần `godot --headless --path . --import`. File `.uid` được commit; thiếu `.uid` làm hai nhánh xung đột.
- **Lỗi Hitbox/va chạm: không đoán mò offset.** Tìm pattern chuẩn (Hitbox Component), vạch luồng logic và báo cáo trước.

## 4. Cân bằng game (chống lạm phát)
- Độ khó đến từ độ sâu và hành vi của quái, không đến từ nhân HP/sát thương.
- Không thêm nguồn nhân sát thương/tốc độ đánh/chí mạng mới mà không có trần hoặc giảm dần theo stack. Hiện tại build "focused" đạt ~x10 sát thương ở tầng 10 (xem `tools/balance/`, nhánh `feature/inflation-calc`).
- Mọi thay đổi số liệu cân bằng: chạy `tools/balance/*.gd` trước/sau và ghi kết quả vào mô tả.
- Bot (`tools/bot/`) dùng để bắt lỗi và smoke test, không dùng để cân bằng (xem README của bot).

## 5. Làm việc song song với agent khác
- Một chat khác cũng push vào `main`. Trước khi gộp: `git fetch` và `git merge-tree --write-tree origin/main HEAD` để kiểm tra xung đột.
- Merge dùng `--no-ff`; push lớn: `git -c http.postBuffer=524288000 push`.
- File `.uid` trùng y hệt gộp được; xung đột thật thì dừng và báo.

## 6. Công cụ Ponytail (nếu đã cài plugin)
`/ponytail-review` trước khi báo "đã push nhánh"; `/ponytail-audit` định kỳ cho cả repo; `/ponytail-debt` để xem các `# shortcut:`.
