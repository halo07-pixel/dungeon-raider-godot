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

Tham số: `--start-floor F --buffs N` (nhảy thẳng tới tầng F với N buff ngẫu nhiên để đo Hell/Council mà không phải đi từ tầng 1), `--runs` (ván/cấu hình), `--class a,b`, `--heat x,y`, `--heat-compare`, `--speed` (tăng tốc, mặc định 6),
`--max-min` (trần phút mô phỏng/ván), `--max-floor`, `--seed`, `--out file.json`, `--trace 1`.
Mỗi ván in một dòng (tầng, kết cục, thời gian, hạ bao nhiêu, số lần lăn né, "săn", kẹt, kẻ hạ gục) rồi bảng tổng hợp
theo class + Heat.

## Bot v1 làm được gì
- Dọn phòng bằng cách đi theo đường tìm được (A*), giữ khoảng cách với quái tầm xa, áp sát quái hay lùi (cung thủ/pháp sư),
  tránh vùng nguy hiểm đang báo trước, lăn né đạn/chạm sát (có xác suất sai), dùng kỹ năng Q khi có >= 3 quái hoặc trùm,
  chọn buff theo bậc hiếm + synergy, nhặt máu/xu gần, đi cổng sang tầng kế, chống kẹt, "săn" khi không hạ được con nào quá lâu.

## Nâng cấp đã làm
- v1.1: bot nghe trạng thái trùm (`charging`, `tele_mode`) để nghiêng khỏi đường lao và lùi khỏi đòn đang báo trước;
  báo cáo tổng hợp thêm "sát thương nhận" theo nguồn. Ranger qua được Warden tầng 1 ở khoảng 4/6 ván (trước: gần như 0).

- v1.2: tránh bẫy sàn (gai/lava/độc/băng), né đạn địch bằng bước ngang theo điểm gần nhất, đường đi dự phòng theo đồ thị
  phòng khi lưới không có đường, `--start-floor/--buffs`. Ngắm đón đầu có sẵn nhưng TẮT (`LEAD_FACTOR = 0`): thử với
  vận tốc quái làm bot tệ đi (8 ván: 2 -> 5 ván sống sót khi tắt), cần xem lại cách lấy vận tốc trước khi bật.

## Giới hạn hiện tại (cần nâng cấp dần)
- Bot yếu hơn người chơi thật: chưa ngắm đón đầu, né trùm còn thô, không dùng Forge/Altar/rương/đổi vũ khí, không tự
  chọn vũ khí tốt hơn, chưa biết các chiêu đặc biệt của từng trùm. **Số "tầng chết" tuyệt đối vì thế KHÔNG phải độ khó
  thật** — chỉ có ý nghĩa để so sánh giữa các cấu hình (class, Heat) khi chạy nhiều ván cùng bot.
- Kết quả có nhiễu ngẫu nhiên lớn: nên chạy >= 10 ván mỗi cấu hình.

## Hướng nâng cấp
1. Ngắm đón đầu + né theo từng chiêu của trùm. 2. Dùng vật phẩm/vũ khí (Forge, rương, đổi vũ khí theo DPS).
3. Chọn buff theo build. 4. Hồ sơ "khó": cho bot phản ứng nhanh/chậm để mô phỏng người mới và cao thủ.

## v1.3 / v1.4 (nâng cấp để đi tới tầng 10)
- Nhặt/đổi vũ khí theo điểm (`_weapon_goal`), ghé phòng kho báu, `--immortal 1` (hồi máu khi < 60% để đi tiếp; bảng theo từng tầng: thời gian, sát thương/max HP, nguồn sát thương).
- Bỏ theo đuổi vật phẩm sau 8 giây mô phỏng (hết kẹt cạnh bẫy gai/tường).
- Chế độ immortal: > 20 phút mô phỏng không đổi tầng thì ép qua tầng (`forced_floors` trong kết quả) – tầng bị ép KHÔNG tính vào thời gian/sát thương trung bình.
- Kết quả mẫu: `tools/bot/results/immortal_floor1-10_summary.md` (4 class x 2 ván, seed 11).
- Lưu ý: số liệu là xấp xỉ "kỹ năng cố định"; bot ăn sát thương nhiều hơn người; dùng để SO SÁNH giữa các tầng/nguồn, không phải độ khó tuyệt đối. Tầng 4–9 (đầm lầy, băng) bot hay kẹt nên mẫu ít.

## v1.5
- Bỏ né bẫy khi đã sát cổng portal (cổng nằm cạnh ô độc/băng làm bot dội ra mãi).
- Boss triệu hồi bầy (> 8 quái): ưu tiên đánh boss nếu có tầm nhìn.
- Vũ khí tầm cực ngắn (Flamethrower ~99px): giảm khoảng giữ/bắn tối thiểu để bắn trúng.
- Báo cáo mới `THỜI GIAN CLEAR TỚI MỐC NÂNG CẤP KỸ NĂNG` (mốc tầng 5 và 10, chỉ tính ván sạch).
- Còn tồn tại: tầng 5–9 vẫn thường phải ép qua tầng; chưa đủ ván sạch để so class.

## bench.gd – so sánh class trong tình huống cố định
`godot --headless --path . --script tools/bot/bench.gd -- --runs 10 --class ranger,brawler,mage,rogue --scenarios warden,swarm,necro,lord --out out.json`
- 4 tình huống cùng tầng/buff/cấp nâng cấp skill/seed cho mọi class: Warden (T1, skill lv0), Bầy 13 quái (T3, lv0), Necromancer (T6, lv1 sau mốc 5), Dungeon Lord (T10, lv2 sau mốc 10).
- Chỉ số: tỉ lệ thắng, TTK, DPS hiệu dụng (HP mục tiêu đã trừ / thời gian), tiến độ %, thời gian tồn tại, sát thương nhận %, skill/phút, chỉ số quy về trung bình = 100.
- Bot không bất tử; chỉ so sánh TƯƠNG ĐỐI giữa các class. "Sát thương nhận" chỉ tính phần trừ vào máu (giáp hấp thụ không tính).
