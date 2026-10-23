# Lạm phát sức mạnh — đo từ dữ liệu game

Giả định build (xem PROFILES trong script): **casual** = 1/3 lượt chọn buff vào tấn công, vũ khí hiếm theo tầng, ít nâng cấp; **focused** = dồn mọi lượt vào buff tấn công + forge; **cap** = mọi trần cùng lúc (trần lý thuyết, không ai đạt được ở đầu game).
Lượt chọn buff tới tầng F = (F-1) + 0.5·(F-1) từ sự kiện. R(F) = hệ số sức mạnh người chơi / (HP quái × giáp) so với tầng 1; R > 1: quái yếu đi tương đối.

## 1a. Sức mạnh sát thương — vũ khí tầm xa

| Tầng | HP×giáp quái | casual: mult → R | focused: mult → R | cap: mult → R |
|---|---|---|---|---|
| 1 | x1.00 | x1.00 → R 1.00 | x1.15 → R 1.15 | x15.48 → R 15.48 |
| 3 | x2.31 | x1.08 → R 0.47 | x2.44 → R 1.06 | x15.48 → R 6.71 |
| 5 | x3.83 | x1.60 → R 0.42 | x4.48 → R 1.17 | x15.48 → R 4.05 |
| 8 | x6.57 | x2.31 → R 0.35 | x8.05 → R 1.22 | x15.48 → R 2.36 |
| 10 | x8.62 | x2.57 → R 0.30 | x10.24 → R 1.19 | x15.48 → R 1.80 |
| 12 | x10.89 | x2.95 → R 0.27 | x12.30 → R 1.13 | x15.48 → R 1.42 |
| 15 | x14.81 | x3.09 → R 0.21 | x13.57 → R 0.92 | x15.48 → R 1.05 |

## 1b. Sức mạnh sát thương — vũ khí cận chiến

| Tầng | HP×giáp quái | casual: mult → R | focused: mult → R | cap: mult → R |
|---|---|---|---|---|
| 1 | x1.00 | x1.00 → R 1.00 | x1.15 → R 1.15 | x14.16 → R 14.16 |
| 3 | x2.31 | x1.08 → R 0.47 | x2.44 → R 1.06 | x14.16 → R 6.13 |
| 5 | x3.83 | x1.60 → R 0.42 | x4.48 → R 1.17 | x14.16 → R 3.70 |
| 8 | x6.57 | x2.31 → R 0.35 | x8.05 → R 1.22 | x14.16 → R 2.15 |
| 10 | x8.62 | x2.57 → R 0.30 | x10.24 → R 1.19 | x14.16 → R 1.64 |
| 12 | x10.89 | x2.95 → R 0.27 | x12.30 → R 1.13 | x14.16 → R 1.30 |
| 15 | x14.81 | x3.09 → R 0.21 | x12.30 → R 0.83 | x14.16 → R 0.96 |

## 2. Cấu thành sức mạnh (tầng 10, tầm xa): đâu là nguồn lớn nhất

| Build | độ hiếm | cộng dồn sát thương (hiếm+buff+mastery) | cấp +N | tốc độ đánh | chí mạng | tổng |
|---|---|---|---|---|---|---|
| casual | epic | x1.66 | x1.16 | x1.23 | x1.08 | **x2.57** |
| focused | legendary | x2.55 | x1.40 | x1.99 | x1.44 | **x10.24** |
| cap | mythic | x3.50 | x1.40 | x1.73 | x1.52 | **x15.48** |

## 3. Độ bền: máu+giáp hiệu dụng so với sát thương quái (tầng 1 = 1.00, ranger)

| Tầng | sát thương quái | casual | focused | cap |
|---|---|---|---|---|
| 1 | x1.00 | 1.00 | 1.42 | 3.60 |
| 3 | x1.20 | 0.83 | 1.18 | 3.00 |
| 5 | x1.40 | 0.77 | 1.29 | 2.57 |
| 8 | x1.70 | 0.76 | 1.30 | 2.12 |
| 10 | x1.90 | 0.74 | 1.23 | 1.89 |
| 12 | x2.10 | 0.67 | 1.17 | 1.71 |
| 15 | x2.40 | 0.58 | 1.07 | 1.50 |

## 4. Thời gian hạ boss (giây) với build focused — vũ khí khởi đầu của class, tầng boss cuối nhóm

| Tầng (boss) | HP boss | ranger | brawler | mage | rogue |
|---|---|---|---|---|---|
| 3 (Dungeon Warden) | 1478 | 25s | 15s | 32s | 13s |
| 6 (Dark Necromancer) | 2342 | 21s | 13s | 27s | 11s |
| 9 (Frozen Horror) | 4464 | 27s | 16s | 35s | 14s |
| 10 (Dungeon Lord) | 9000 | 48s | 29s | 61s | 26s |
| 15 (Dungeon Lord) | 13167 | 62s | 41s | 79s | 37s |

## 5. Cách đọc
- R tăng theo tầng = người chơi mạnh lên nhanh hơn quái; R trên ~2 ở tầng 10 cho build focused nghĩa là boss chỉ bằng nửa độ trâu thiết kế.
- Bảng 2 cho thấy nhân tố nào đóng góp nhiều nhất (độ hiếm/buff cộng dồn, tốc độ đánh nhân, chí mạng nhân).
- Bảng 4 giả định trúng 75%, bỏ qua kỹ năng class, đạn xuyên/AOE, trạng thái; dùng để so các mức build và class, không phải thời gian thực.
- Giả định build (số lượt chọn, vũ khí theo tầng) là ước lượng của tôi; cần đối chiếu với dữ liệu ván thật (telemetry) để chỉnh.
