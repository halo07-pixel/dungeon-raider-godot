# Cân bằng class — tính tĩnh từ dữ liệu game

Mô hình: 1 mục tiêu, tỉ lệ trúng 75%, vũ khí khởi đầu độ hiếm **common**, kỹ năng khởi đầu, KHÔNG buff/rank/trạng thái. Chỉ nên đọc TƯƠNG ĐỐI giữa các class.

## 1. Thời gian hạ boss (giây) với vũ khí khởi đầu của class

| Tầng | Boss | HP | Giáp (giảm) | ranger (pistol) | brawler (broadsword) | mage (staff) | rogue (daggers) |
|---|---|---|---|---|---|---|---|
| 1 | Dungeon Warden | 700 | 2 (-6%) | 21s (33.3 dps) | 15s (45.5 dps) | 25s (27.6 dps) | 13s (54.3 dps) |
| 3 | Dungeon Warden | 1478 | 5 (-14%) | 49s (30.0 dps) | 35s (42.2 dps) | 58s (25.6 dps) | 29s (50.4 dps) |
| 4 | Dark Necromancer | 1653 | 6 (-17%) | 55s (30.0 dps) | 41s (40.6 dps) | 67s (24.6 dps) | 33s (50.5 dps) |
| 6 | Dark Necromancer | 2342 | 10 (-25%) | 88s (26.7 dps) | 63s (37.4 dps) | 96s (24.5 dps) | 50s (46.5 dps) |
| 7 | Frozen Horror | 3553 | 11 (-27%) | 133s (26.7 dps) | 99s (35.8 dps) | 157s (22.6 dps) | 84s (42.5 dps) |
| 9 | Frozen Horror | 4464 | 14 (-32%) | 167s (26.7 dps) | 131s (34.2 dps) | 198s (22.5 dps) | 105s (42.6 dps) |
| 10 | Dungeon Lord | 9000 | 16 (-35%) | 386s (23.3 dps) | 277s (32.5 dps) | 419s (21.5 dps) | 234s (38.5 dps) |

## 2. Chỉ số so sánh class (DPS lên boss, trung bình 4 class = 100)

| Tầng | ranger | brawler | mage | rogue |
|---|---|---|---|---|
| 1 | 83 | 113 | 69 | 135 |
| 3 | 81 | 114 | 69 | 136 |
| 4 | 82 | 111 | 67 | 139 |
| 6 | 79 | 111 | 73 | 138 |
| 7 | 84 | 112 | 71 | 133 |
| 9 | 85 | 109 | 71 | 135 |
| 10 | 81 | 112 | 74 | 133 |

## 3. Kỹ năng khởi đầu (đóng góp DPS trung bình lên boss tầng 6)

- **ranger**: vũ khí 20.0 dps + kỹ năng 6.7 dps (Overdrive +33% DPS) → kỹ năng chiếm 25%
- **brawler**: vũ khí 35.0 dps + kỹ năng 2.4 dps (Slam 19/6s) → kỹ năng chiếm 6%
- **mage**: vũ khí 17.0 dps + kỹ năng 7.5 dps (Well 8x6/6.4s) → kỹ năng chiếm 31%
- **rogue**: vũ khí 43.1 dps + kỹ năng 3.4 dps (Dash 16+crit/6s) → kỹ năng chiếm 7%

## 4. Xếp hạng vũ khí theo class (DPS lên boss tầng 6, chưa tính kỹ năng; tỉ lệ so với vũ khí khởi đầu của class)

**ranger** (khởi đầu 20.0 dps): SMG 44.1 (x2.21), Daggers 37.5 (x1.88), Flamethrower 32.1 (x1.61), Longsword 31.7 (x1.58), Spear 31.4 (x1.57), Longbow 31.1 (x1.55), Crossbow 25.6 (x1.28), War Hammer 25.0 (x1.25), Railgun 22.0 (x1.10), Scythe 21.6 (x1.08), Laser Gun 21.0 (x1.05), Pistol 20.0 (x1.00), Arcane Staff 19.0 (x0.95), Shotgun 18.0 (x0.90), Chakram 10.6 (x0.53)

**brawler** (khởi đầu 35.0 dps): Daggers 40.9 (x1.17), Spear 35.5 (x1.01), SMG 35.3 (x1.01), Longsword 35.0 (x1.00), Flamethrower 32.1 (x0.92), War Hammer 28.3 (x0.81), Longbow 27.8 (x0.79), Scythe 24.4 (x0.70), Crossbow 22.9 (x0.66), Pistol 20.0 (x0.57), Railgun 19.2 (x0.55), Laser Gun 18.0 (x0.51), Arcane Staff 17.0 (x0.49), Shotgun 15.0 (x0.43), Chakram 9.4 (x0.27)

**mage** (khởi đầu 17.0 dps): Daggers 37.5 (x2.21), SMG 35.3 (x2.08), Flamethrower 32.1 (x1.89), Longsword 31.7 (x1.86), Spear 31.4 (x1.84), Longbow 27.8 (x1.64), War Hammer 25.0 (x1.47), Crossbow 22.9 (x1.35), Scythe 21.6 (x1.27), Pistol 20.0 (x1.18), Railgun 19.2 (x1.13), Laser Gun 18.0 (x1.06), Arcane Staff 17.0 (x1.00), Shotgun 15.0 (x0.88), Chakram 9.4 (x0.55)

**rogue** (khởi đầu 43.1 dps): Daggers 43.1 (x1.00), SMG 40.6 (x0.94), Flamethrower 37.0 (x0.86), Longsword 36.4 (x0.84), Spear 36.1 (x0.84), Longbow 32.0 (x0.74), War Hammer 28.8 (x0.67), Crossbow 26.4 (x0.61), Scythe 24.8 (x0.57), Pistol 23.0 (x0.53), Railgun 22.1 (x0.51), Laser Gun 20.7 (x0.48), Arcane Staff 19.5 (x0.45), Shotgun 17.2 (x0.40), Chakram 10.8 (x0.25)

## 5. Ghi chú đọc số liệu
- Giáp boss giảm theo phần trăm (K=30); đạn nhỏ (SMG, Flamethrower) bị phạt như mọi vũ khí nhưng làm tròn tối thiểu 1 sát thương/đòn.
- Class chênh nhau quá ~25% so với trung bình ở nhiều tầng liên tiếp đáng cân nhắc chỉnh; dưới ~15% coi như cân bằng.
- Chưa tính: sát thương diện rộng (Arcane Staff nổ, Flamethrower/Scythe xuyên nhiều quái — lợi thế của mage trong bầy quái bị đánh giá thấp ở bảng boss), buff (Power/Crit/Berserk/...), rank vũ khí, trạng thái (cháy/độc/chảy máu), mastery, né/di chuyển, mô hình lượng sát thương nhận.
