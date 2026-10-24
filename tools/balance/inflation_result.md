# Lạm phát sức mạnh — đo từ dữ liệu game

Giả định build (xem PROFILES trong script): **casual** = 1/3 lượt chọn buff vào tấn công, vũ khí hiếm theo tầng, ít nâng cấp; **focused** = dồn mọi lượt vào buff tấn công + forge; **cap** = mọi trần cùng lúc (trần lý thuyết, không ai đạt được ở đầu game).
Lượt chọn buff tới tầng F = (F-1) + 0.5·(F-1) từ sự kiện. R(F) = hệ số sức mạnh người chơi / (HP quái × giáp) so với tầng 1; R > 1: quái yếu đi tương đối.

## 1a. Sức mạnh sát thương — vũ khí tầm xa

| Tầng | HP×giáp quái | casual: mult → R | focused: mult → R | cap: mult → R |
|---|---|---|---|---|
| 1 | x1.00 | x1.00 → R 1.00 | x1.15 → R 1.15 | x12.05 → R 12.05 |
| 3 | x2.31 | x1.08 → R 0.47 | x2.33 → R 1.01 | x12.05 → R 5.22 |
| 5 | x3.83 | x1.60 → R 0.42 | x3.46 → R 0.90 | x12.05 → R 3.15 |
| 8 | x6.57 | x2.31 → R 0.35 | x5.37 → R 0.82 | x12.05 → R 1.83 |
| 10 | x8.62 | x2.57 → R 0.30 | x6.84 → R 0.79 | x12.05 → R 1.40 |
| 12 | x10.89 | x2.95 → R 0.27 | x8.36 → R 0.77 | x12.05 → R 1.11 |
| 15 | x14.81 | x3.03 → R 0.20 | x9.34 → R 0.63 | x12.05 → R 0.81 |

## 1b. Sức mạnh sát thương — vũ khí cận chiến

| Tầng | HP×giáp quái | casual: mult → R | focused: mult → R | cap: mult → R |
|---|---|---|---|---|
| 1 | x1.00 | x1.00 → R 1.00 | x1.15 → R 1.15 | x10.89 → R 10.89 |
| 3 | x2.31 | x1.08 → R 0.47 | x2.33 → R 1.01 | x10.89 → R 4.72 |
| 5 | x3.83 | x1.60 → R 0.42 | x3.46 → R 0.90 | x10.89 → R 2.85 |
| 8 | x6.57 | x2.31 → R 0.35 | x5.37 → R 0.82 | x10.89 → R 1.66 |
| 10 | x8.62 | x2.57 → R 0.30 | x6.84 → R 0.79 | x10.89 → R 1.26 |
| 12 | x10.89 | x2.95 → R 0.27 | x8.36 → R 0.77 | x10.89 → R 1.00 |
| 15 | x14.81 | x3.03 → R 0.20 | x8.36 → R 0.56 | x10.89 → R 0.74 |

## 2. Cấu thành sức mạnh (tầng 10, tầm xa): đâu là nguồn lớn nhất

| Build | độ hiếm | cộng dồn sát thương (hiếm+buff+mastery) | cấp +N | tốc độ đánh | chí mạng | tổng |
|---|---|---|---|---|---|---|
| casual | epic | x1.66 | x1.16 | x1.23 | x1.08 | **x2.57** |
| focused | legendary | x2.20 | x1.40 | x1.54 | x1.44 | **x6.84** |
| cap | mythic | x3.10 | x1.40 | x1.52 | x1.52 | **x12.05** |

## 3. Độ bền: máu+giáp hiệu dụng so với sát thương quái (tầng 1 = 1.00, ranger)

| Tầng | sát thương quái | casual | focused | cap |
|---|---|---|---|---|
| 1 | x1.00 | 1.00 | 1.42 | 2.97 |
| 3 | x1.24 | 0.81 | 1.14 | 2.40 |
| 5 | x1.48 | 0.73 | 1.14 | 2.01 |
| 8 | x1.84 | 0.66 | 1.03 | 1.61 |
| 10 | x2.08 | 0.63 | 0.96 | 1.43 |
| 12 | x2.32 | 0.56 | 0.91 | 1.28 |
| 15 | x2.68 | 0.49 | 0.82 | 1.11 |

## 4. Thời gian hạ boss (giây) với build focused — vũ khí khởi đầu của class, tầng boss cuối nhóm

| Tầng (boss) | HP boss | ranger | brawler | mage | rogue |
|---|---|---|---|---|---|
| 3 (Dungeon Warden) | 1478 | 22s | 19s | 26s | 19s |
| 6 (Dark Necromancer) | 2342 | 23s | 20s | 28s | 20s |
| 9 (Frozen Horror) | 4464 | 34s | 29s | 41s | 30s |
| 10 (Dungeon Lord) | 11700 | 78s | 67s | 94s | 69s |
| 15 (Dungeon Lord) | 17117 | 98s | 94s | 118s | 98s |

## 5. Cách đọc
- R tăng theo tầng = người chơi mạnh lên nhanh hơn quái; R trên ~2 ở tầng 10 cho build focused nghĩa là boss chỉ bằng nửa độ trâu thiết kế.
- Bảng 2 cho thấy nhân tố nào đóng góp nhiều nhất (độ hiếm/buff cộng dồn, tốc độ đánh nhân, chí mạng nhân).
- Bảng 4 giả định trúng 75%, bỏ qua kỹ năng class, đạn xuyên/AOE, trạng thái; dùng để so các mức build và class, không phải thời gian thực.
- Giả định build (số lượt chọn, vũ khí theo tầng) là ước lượng của tôi; cần đối chiếu với dữ liệu ván thật (telemetry) để chỉnh.
