# Dungeon Raider (bản Hollow Knight-style) — quy tắc cho AI (Godot 4.7)

Áp dụng cho mọi agent làm việc trong repo này. Dựa trên Ponytail ("senior dev lười": giải đủ bài toán bằng ít code mới nhất) và những lỗi thật đã gặp trong dự án.

## 0. Thứ tự ưu tiên (không đảo)
1. **Quy trình 5 bước của dự án** (đề xuất → duyệt → nhánh feature + push → chờ duyệt gộp → gộp vào `main`). Không bao giờ push thẳng `main`, dù chỉ sửa một dòng.
2. Quy tắc Godot ở mục 3.
3. Quy tắc "ít code" ở mục 1–2.

## 1. Ít code nhưng làm đủ việc
Trước khi viết: đọc code liên quan, liệt kê mọi chỗ thay đổi phải chạm tới (nơi gọi, test, scene, `project.godot`, file `.uid`, save/load). Lấy lựa chọn đầu tiên chạy được:
1. Có cần tồn tại không? Bỏ tính năng/option/linh hoạt không ai yêu cầu và nói rõ một dòng.
2. Repo đã có helper/component/pattern chưa? Dùng theo cách code xung quanh đang dùng (vd `hk/state.gd`, `hk/sprites.gd` là static helper trên RefCounted).
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
- Script chạy bằng `--script` không thấy autoload lúc biên dịch (dự án hiện không dùng autoload): lấy qua `load()` lúc chạy.
- Đổi ảnh `.png`: cần `godot --headless --path . --import`. File `.uid` được commit; thiếu `.uid` làm hai nhánh xung đột.
- **Lỗi Hitbox/va chạm: không đoán mò offset.** Tìm pattern chuẩn (Hitbox Component), vạch luồng logic và báo cáo trước.

## 4. Độ khó
- Độ khó đến từ hành vi quái, boss và bố cục phòng, không đến từ nhân HP/sát thương.
- Không thêm nguồn nhân sát thương hay tốc độ đánh mà không có trần hoặc giảm dần theo stack (bùa hiện có: Heavy Blow +40%, Fury +75% khi còn 1 mặt nạ).
- Đổi số liệu quái/boss/bùa: ghi giá trị cũ → mới vào mô tả nhánh.

## 5. Làm việc song song với agent khác
- Một chat khác cũng push vào `main`. Trước khi gộp: `git fetch` và `git merge-tree --write-tree origin/main HEAD` để kiểm tra xung đột.
- Merge dùng `--no-ff`; push lớn: `git -c http.postBuffer=524288000 push`.
- File `.uid` trùng y hệt gộp được; xung đột thật thì dừng và báo.

## 6. Công cụ Ponytail (nếu đã cài plugin)
`/ponytail-review` trước khi báo "đã push nhánh"; `/ponytail-audit` định kỳ cho cả repo; `/ponytail-debt` để xem các `# shortcut:`.

## 7. Bản Hollow Knight-style (`hk/`)
- Phòng nằm ở `hk/rooms/*.txt`, được sinh bởi `tools/hk/gen_rooms.py`: sửa generator rồi sinh lại, không sửa tay.
- Sau mọi thay đổi phòng hoặc hằng số di chuyển trong `player.gd`: chạy `python3 tools/hk/validate_rooms.py --quick` (phải OK) và `hk_world_test.gd`, `hk_player_test.gd`, `hk_flow_test.gd`.
- Test input headless: `Input.action_press` KHÔNG tạo `is_action_just_pressed`; dùng `Input.parse_input_event(InputEventAction)` rồi `await process_frame`.
- Màn hình/menu mở bằng phím điều hướng phải bỏ qua khung đầu (phím mở còn just_pressed); xem `shop.gd`, `title.gd`.
- `hk/state.gd` là static, không phải autoload: test phải `reset()` và đổi `save_path` sang file riêng.

- **Hình = hộp.** Kích thước hộp quái/boss/vật tương tác lấy từ bbox nhìn thấy của sprite (`hk/bodies.gd`, sinh bởi `tools/hk/gen_bodies.py` sau khi đổi ảnh) — không gõ tay số hộp riêng. Vẽ qua `SPRITES.draw_body` (đáy nhìn thấy chạm chân hộp). Người chơi: `player.BODY` 24×44; validator dùng cùng số (HALF_W/HALF_H, GROUND_ACCEL).
- Lật sprite: `draw_texture_rect` với `size.x < 0` vẫn phủ `[position.x, position.x+|size.x|]`, không tự dời vị trí.
- F3 trong game bật lớp soi hộp thật (`hk/debug_boxes.gd`); `tools/_hkshot.gd <phòng> <png> [x y] debug` chụp kèm lớp này. Test: `hk_align_test.gd`.
- Gợi ý phím trong phòng: dòng `hint: cột hàng chữ` trong header phòng (sinh từ `r.extra` ở `gen_rooms.py`), vẽ bởi `room.gd`, rõ dần khi lại gần. Âm lượng nhạc/hiệu ứng: `STATE.music_vol/sfx_vol` (0..10, không bị `reset()` xoá, lưu trong save), chỉnh ở tab Pause bằng Left/Right. Test: `hk_settings_test.gd`.
- Đo độ khó: `godot --headless --path . -s tools/_hkbot.gd -- <crawler|flyer|spitter|charger|warden|wraith|lord> [số lần]` (bot trung bình, tầm chém cố định; chỉ so sánh giữa hai phiên bản, không phải số tuyệt đối). Muốn so cũ/mới: `git worktree add /tmp/old <commit>` rồi chép bot sang.
- `hk_walk_test.gd`: đi qua mọi cửa trong engine thật (nối hai chiều, vào không chồng tường/gai/cửa, không bị bật lại, đứng được trên sàn), khoá/mở phòng boss, chết giữa trận boss, bàn thờ cần boss. Lưu ý khi viết test kiểu này: sau `load_room` phải `await process_frame` (phòng cũ `queue_free` xong) trước khi đặt người chơi, và cô lập tín hiệu cửa/gai của world để chuyển phòng bất đồng bộ không làm nhiễu.
- Quái mới: `g` guard (khiên chặn chính diện; trúng từ sau lưng/trên xuống hoặc lúc hạ khiên; `take_hit` trả `false` khi bị chặn, player không cộng Soul) và `d` dropper (treo trần ở ô đặt, rơi khi người chơi ở ngay dưới). Mini-boss `brute` (cat_6) và `hexer` (gate_7) dùng chung `boss.gd` (cờ `boss_<id>`), bùa trong phòng đó có `needs=boss_<id>`. `take_hit` đổi từ void sang trả bool: gọi bằng `== false` để phân biệt bị chặn. Test: `hk_enemy_test.gd`.
- Bản đồ (`menu.gd`): `Menu.map_icons(room)` trả biểu tượng cho phòng đã đến (bench, thương nhân, bàn thờ/bùa chưa lấy, boss chưa hạ, rương chưa mở, cửa tới phòng chưa đến); phím mũi tên kéo bản đồ; `P` đặt/gỡ ghim (`STATE.pins`, tối đa `MAX_PINS`, lưu trong save, đọc có kiểm tra kiểu). Test: `hk_map_test.gd`.
