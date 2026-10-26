# Dungeon Raider (Godot 4.7) — bản Hollow Knight-style

Metroidvania 2D: ba khu (Gate Ruins → Weeping Catacombs → Ashen Vaults), 24 phòng, 3 boss, 3 kỹ năng mở khoá khu vực, 8 bùa, thương nhân, bench, chết để lại Shade giữ Geo.
Mở bằng **Godot 4.7+** (Import `project.godot`), bấm **F5**. Cảnh chính: `hk/main.tscn` (tiêu đề → New Game / Continue).

Game cũ (roguelite nhìn từ trên xuống) được lưu ở nhánh `archive/dungeon-raider-v1`; mã cũ vẫn còn trong `scripts/` và `scenes/` cho tới khi có quyết định xoá riêng.

## Điều khiển
| Hành động | Phím |
|---|---|
| Di chuyển | A/D hoặc ←/→ |
| Nhảy (giữ = cao, nhả sớm = thấp) | Z hoặc Space |
| Chém (kèm W/S = chém lên/xuống, chém xuống trúng thì nảy) | X hoặc J |
| Dash (sau khi lấy Shadow Dash) | C hoặc K |
| Focus hồi mặt nạ (giữ, đứng yên, đủ 33 Soul) | V hoặc L |
| Soul Bolt | F hoặc I |
| Bản đồ / Bùa / Tạm dừng | M / E hoặc Tab / Esc |
| Bench & thương nhân | W/↑ khi đứng gần |

Kỹ năng: **Shadow Dash** (gate_8) → **Wings of Ash** nhảy đôi (cat_4) → **Claw Grip** bám tường (cat_9). Save tự động tại `user://hk_save.json` (ghi nguyên tử), lưu khi nghỉ ở bench, nhận kỹ năng/bùa, hạ boss, đóng menu/shop.

## Cấu trúc `hk/`
- `state.gd` — trạng thái ván (static, không phải autoload): máu/soul/geo, kỹ năng, bùa & ô, cờ, bench, shade, lưu/đọc.
- `world.gd` — nạp phòng, chuyển cửa, bench, chết/shade, tương tác, boss; báo `ending_reached` lên `main.gd`.
- `room.gd` + `world_data.gd` — dựng phòng từ lưới ký tự `hk/rooms/*.txt` (1 ô = 32px).
- `player.gd`, `enemy.gd`, `boss.gd`, `projectile.gd`, `shade.gd` — thực thể. `hud.gd`, `menu.gd`, `shop.gd`, `title.gd`, `ending.gd` — giao diện (giao tiếp bằng signal).
- `sprites.gd`, `music.gd` — dùng lại sprite 0x72 (CC0) và nhạc CC0 của game cũ trong `assets/`; chỉ để vẽ/phát, không ảnh hưởng logic.
- `input.gd` — đăng ký phím bằng code (không đụng InputMap game cũ).

## Công cụ
- `python3 tools/hk/gen_rooms.py` — sinh lại `hk/rooms/*.txt` (sửa phòng ở đây, không sửa tay file sinh ra).
- `python3 tools/hk/validate_rooms.py [--quick]` — mô phỏng vật lý người chơi để kiểm tra mọi phòng/vật phẩm/kỹ năng tới được đúng thứ tự và không có bẫy. Thoát 1 nếu lỗi.
- `godot --headless --path . --script tools/tests/hk_world_test.gd` (cũng `hk_player_test.gd`, `hk_flow_test.gd`) — test headless. `bash tools/tests/run_all.sh` chạy tất cả.
- `tools/_hkshot.gd -- <room_id> <out.png>` dưới `xvfb-run ... --rendering-driver opengl3` — chụp ảnh một phòng.

Giới hạn đã biết của validator: không mô phỏng pogo, Soul Bolt, quái/boss; mẫu thời điểm bấm phím rời rạc nên "không tới được" cần kiểm tay, còn "tới được" là chắc chắn.
