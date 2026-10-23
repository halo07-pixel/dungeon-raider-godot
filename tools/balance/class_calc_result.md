# Cân bằng class — tính tĩnh từ dữ liệu game

Mô hình: 1 mục tiêu, tỉ lệ trúng 75%, vũ khí khởi đầu độ hiếm **common**, kỹ năng khởi đầu, KHÔNG buff/rank/trạng thái. Chỉ nên đọc TƯƠNG ĐỐI giữa các class.

## 1. Thời gian hạ boss (giây) với vũ khí khởi đầu của class

| Tầng | Boss | HP | Giáp (giảm) | ranger (pistol) | brawler (broadsword) | mage (staff) | rogue (daggers) |
|---|---|---|---|---|---|---|---|
| 1 | Dungeon Warden | 700 | 2 (-6%) | 18s (40.0 dps) | 17s (40.5 dps) | 21s (32.6 dps) | 18s (38.9 dps) |
| 3 | Dungeon Warden | 1478 | 5 (-14%) | 40s (36.7 dps) | 40s (37.2 dps) | 48s (30.6 dps) | 42s (35.3 dps) |
| 4 | Dark Necromancer | 1653 | 6 (-17%) | 45s (36.7 dps) | 46s (35.6 dps) | 56s (29.6 dps) | 47s (35.5 dps) |
| 6 | Dark Necromancer | 2342 | 10 (-25%) | 70s (33.3 dps) | 72s (32.4 dps) | 82s (28.5 dps) | 74s (31.8 dps) |
| 7 | Frozen Horror | 3553 | 11 (-27%) | 107s (33.3 dps) | 109s (32.5 dps) | 134s (26.6 dps) | 112s (31.8 dps) |
| 9 | Frozen Horror | 4464 | 14 (-32%) | 149s (30.0 dps) | 153s (29.2 dps) | 168s (26.5 dps) | 140s (31.9 dps) |
| 10 | Dungeon Lord | 11700 | 16 (-35%) | 439s (26.7 dps) | 401s (29.2 dps) | 459s (25.5 dps) | 416s (28.2 dps) |

## 2. Chỉ số so sánh class (DPS lên boss, trung bình 4 class = 100)

| Tầng | ranger | brawler | mage | rogue |
|---|---|---|---|---|
| 1 | 105 | 106 | 86 | 102 |
| 3 | 105 | 107 | 87 | 101 |
| 4 | 107 | 104 | 86 | 103 |
| 6 | 106 | 103 | 91 | 101 |
| 7 | 107 | 105 | 86 | 102 |
| 9 | 102 | 99 | 90 | 108 |
| 10 | 97 | 107 | 93 | 103 |

## 3. Kỹ năng khởi đầu (đóng góp DPS trung bình lên boss tầng 6)

- **ranger**: vũ khí 25.0 dps + kỹ năng 8.3 dps (Overdrive +33% DPS) → kỹ năng chiếm 25%
- **brawler**: vũ khí 30.0 dps + kỹ năng 2.4 dps (Slam 19/6s) → kỹ năng chiếm 7%
- **mage**: vũ khí 21.0 dps + kỹ năng 7.5 dps (Well 8x6/6.4s) → kỹ năng chiếm 26%
- **rogue**: vũ khí 28.8 dps + kỹ năng 3.0 dps (Dash 16+crit/6s) → kỹ năng chiếm 9%

## 4. Xếp hạng vũ khí theo class (DPS lên boss tầng 6, chưa tính kỹ năng; tỉ lệ so với vũ khí khởi đầu của class)

**ranger** (khởi đầu 25.0 dps): SMG 44.1 (x1.76), Flamethrower 32.1 (x1.29), Spear 31.4 (x1.25), Longbow 31.1 (x1.24), Longsword 26.7 (x1.07), Crossbow 25.6 (x1.02), Pistol 25.0 (x1.00), Daggers 25.0 (x1.00), War Hammer 25.0 (x1.00), Arcane Staff 23.0 (x0.92), Railgun 22.0 (x0.88), Scythe 21.6 (x0.86), Laser Gun 21.0 (x0.84), Shotgun 18.0 (x0.72), Chakram 10.6 (x0.42)

**brawler** (khởi đầu 30.0 dps): Spear 35.5 (x1.18), SMG 35.3 (x1.18), Flamethrower 32.1 (x1.07), Longsword 30.0 (x1.00), War Hammer 28.3 (x0.94), Daggers 28.1 (x0.94), Longbow 27.8 (x0.93), Scythe 24.4 (x0.81), Crossbow 22.9 (x0.76), Pistol 22.5 (x0.75), Arcane Staff 21.0 (x0.70), Railgun 19.2 (x0.64), Laser Gun 18.0 (x0.60), Shotgun 15.0 (x0.50), Chakram 9.4 (x0.31)

**mage** (khởi đầu 21.0 dps): SMG 35.3 (x1.68), Flamethrower 32.1 (x1.53), Spear 31.4 (x1.49), Longbow 27.8 (x1.32), Longsword 26.7 (x1.27), Daggers 25.0 (x1.19), War Hammer 25.0 (x1.19), Crossbow 22.9 (x1.09), Pistol 22.5 (x1.07), Scythe 21.6 (x1.03), Arcane Staff 21.0 (x1.00), Railgun 19.2 (x0.92), Laser Gun 18.0 (x0.86), Shotgun 15.0 (x0.71), Chakram 9.4 (x0.45)

**rogue** (khởi đầu 28.8 dps): SMG 40.6 (x1.41), Flamethrower 37.0 (x1.29), Spear 36.1 (x1.25), Longbow 32.0 (x1.11), Longsword 30.7 (x1.07), Daggers 28.8 (x1.00), War Hammer 28.8 (x1.00), Crossbow 26.4 (x0.92), Pistol 25.9 (x0.90), Scythe 24.8 (x0.86), Arcane Staff 24.1 (x0.84), Railgun 22.1 (x0.77), Laser Gun 20.7 (x0.72), Shotgun 17.2 (x0.60), Chakram 10.8 (x0.37)

## 5. Ghi chú đọc số liệu
- Giáp boss giảm theo phần trăm (K=30); đạn nhỏ (SMG, Flamethrower) bị phạt như mọi vũ khí nhưng làm tròn tối thiểu 1 sát thương/đòn.
- Class chênh nhau quá ~25% so với trung bình ở nhiều tầng liên tiếp đáng cân nhắc chỉnh; dưới ~15% coi như cân bằng.
- Chưa tính: sát thương diện rộng (Arcane Staff nổ, Flamethrower/Scythe xuyên nhiều quái — lợi thế của mage trong bầy quái bị đánh giá thấp ở bảng boss), buff (Power/Crit/Berserk/...), rank vũ khí, trạng thái (cháy/độc/chảy máu), mastery, né/di chuyển, mô hình lượng sát thương nhận.
