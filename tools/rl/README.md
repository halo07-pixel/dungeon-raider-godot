# Huấn luyện AI Dungeon Lord (offline)

Game không chạy Python. Thư mục này chỉ dùng khi muốn huấn luyện lại; kết quả là một file JSON
(`assets/ai/lord_policy.json`) mà `RLController.load_policy()` nạp lúc Lord xuất hiện.

## Cách chạy

```
python3 tools/rl/train_lord.py                # mặc định 60 vòng, khoảng 10-15 phút (cần numpy)
python3 tools/rl/train_lord.py --iters 100 --pop 24 --seed 3
```

Cuối lượt chạy, script in bảng so sánh "tiên nghiệm" (bộ viết tay cũ) với "đã học" trên 30 seed mới,
gồm cả 2 kiểu người chơi KHÔNG dùng khi huấn luyện (`dancer`, `camper`) để biết có học vẹt hay không.

## Gồm những gì

- `lord_sim.py`: mô phỏng gần đúng trận Lord (đấu trường 24x16 ô, 4 pha 15s, bảng cooldown/telegraph,
  pool đòn từng pha, vòng đạn, vùng nổ, truy đuổi, Phán Quyết, triệu hồi...). Các bot người chơi:
  `skilled`, `kiter`, `brawler`, `novice` (huấn luyện) và `dancer`, `camper` (kiểm tra).
- `train_lord.py`: Evolution Strategies (numpy). Tối ưu 3 hàng trọng số (di chuyển x/y, chọn đòn), bias,
  `move_blend` (0.1-0.7) và `pick_bias` (0.3-2.2), xuất phát từ bộ tiên nghiệm trong `rl_controller.gd`.

## Kết quả bản đang dùng (`assets/ai/lord_policy.json`)

Trên 120 seed mới trong mô phỏng, so với bộ viết tay cũ: sát thương/giây gây cho người chơi tăng trung bình
khoảng **+12%** (bot giỏi +5%, kiểu đứng xa +17%, cận chiến +21%, bot giữ lại `dancer` +14%, `camper` +19%;
riêng bot `novice` không đổi). Phần lớn lợi ích đến từ `pick_bias` ~2.07 (chọn đòn theo khoảng cách/tốc độ
người chơi rõ rệt hơn) và `move_blend` = 0.1 (di chuyển ít bị chính sách kéo lệch). Đây là mức tăng NHẸ,
vì boss chỉ di chuyển được giữa các đòn và chỉ thiên lệch được việc chọn đòn; muốn khó hơn nữa cần thêm
đòn/đổi số liệu trong `boss.gd` hoặc nới `MAX_GAIN`.

## Giới hạn cần biết

- Mô phỏng chỉ GẦN ĐÚNG `boss.gd` (hình học đòn đơn giản hoá, bot không phải người thật). Hằng số
  nhập tay từ `boss.gd`/`player.gd`; nếu sau này đổi các đòn của Lord thì nên cập nhật `lord_sim.py` và
  huấn luyện lại.
- "Khó hơn" được chặn: điểm bão hoà ở +30% sát thương/giây so với bộ cũ, bot giỏi nhất không bị vượt
  quá 1.4 lần. Muốn chỉnh độ khó thì đổi `MAX_GAIN` / `SKILLED_CAP` trong `train_lord.py` rồi chạy lại.
- Trong game, chính sách vẫn tự tinh chỉnh nhẹ quanh bộ trọng số đã học (kẹp `MAX_DELTA` của
  `rl_controller.gd`). Xoá file JSON thì Lord quay về bộ viết tay như trước.
