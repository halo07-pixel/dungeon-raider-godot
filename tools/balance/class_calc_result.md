# Cân bằng class — tính tĩnh từ dữ liệu game

Mô hình: 1 mục tiêu, tỉ lệ trúng 75%, vũ khí khởi đầu độ hiếm **common**, kỹ năng khởi đầu, KHÔNG buff/rank/trạng thái. Chỉ nên đọc TƯƠNG ĐỐI giữa các class.

## 1. Thời gian hạ boss (giây) với vũ khí khởi đầu của class

| Tầng | Boss | HP | Giáp (giảm) | ranger (pistol) | brawler (broadsword) | mage (staff) | rogue (daggers) | summoner (chakram) |
|---|---|---|---|---|---|---|---|---|
| 1 | Dungeon Warden | 700 | 2 (-6%) | 18s (40.0 dps) | 17s (40.5 dps) | 21s (32.6 dps) | 18s (38.9 dps) | 23s (30.6 dps) |
| 3 | Dungeon Warden | 1478 | 5 (-14%) | 40s (36.7 dps) | 40s (37.2 dps) | 48s (30.6 dps) | 42s (35.3 dps) | 47s (31.3 dps) |
| 4 | Dark Necromancer | 1653 | 6 (-17%) | 45s (36.7 dps) | 46s (35.6 dps) | 56s (29.6 dps) | 47s (35.5 dps) | 50s (33.2 dps) |
| 6 | Dark Necromancer | 2342 | 10 (-25%) | 70s (33.3 dps) | 72s (32.4 dps) | 82s (28.5 dps) | 74s (31.8 dps) | 72s (32.7 dps) |
| 7 | Frozen Horror | 3553 | 11 (-27%) | 107s (33.3 dps) | 109s (32.5 dps) | 134s (26.6 dps) | 112s (31.8 dps) | 105s (33.9 dps) |
| 9 | Frozen Horror | 4464 | 14 (-32%) | 149s (30.0 dps) | 153s (29.2 dps) | 168s (26.5 dps) | 140s (31.9 dps) | 131s (34.0 dps) |
| 10 | Dungeon Lord | 11700 | 16 (-35%) | 439s (26.7 dps) | 401s (29.2 dps) | 459s (25.5 dps) | 416s (28.2 dps) | 351s (33.4 dps) |

## 2. Chỉ số so sánh class (DPS lên boss, trung bình các class = 100, chưa tính Ultimate/tiến hoá)

| Tầng | ranger | brawler | mage | rogue | summoner |
|---|---|---|---|---|---|
| 1 | 110 | 111 | 89 | 107 | 84 |
| 3 | 107 | 109 | 89 | 103 | 91 |
| 4 | 108 | 104 | 87 | 104 | 97 |
| 6 | 105 | 102 | 90 | 100 | 103 |
| 7 | 105 | 103 | 84 | 100 | 107 |
| 9 | 99 | 96 | 87 | 105 | 112 |
| 10 | 93 | 102 | 89 | 99 | 117 |

## 3. Kỹ năng khởi đầu (đóng góp DPS trung bình lên boss tầng 6)

- **ranger**: vũ khí 25.0 dps + kỹ năng 8.3 dps (Overdrive +33% DPS) → kỹ năng chiếm 25%
- **brawler**: vũ khí 30.0 dps + kỹ năng 2.4 dps (Slam 19/6s) → kỹ năng chiếm 7%
- **mage**: vũ khí 21.0 dps + kỹ năng 7.5 dps (Well 8x6/6.4s) → kỹ năng chiếm 26%
- **rogue**: vũ khí 28.8 dps + kỹ năng 3.0 dps (Dash 16+crit/6s) → kỹ năng chiếm 9%
- **summoner**: vũ khí 9.4 dps + kỹ năng 23.3 dps (2 lính 23.3 dps) → kỹ năng chiếm 71%

## 4. Xếp hạng vũ khí theo class (DPS lên boss tầng 6, chưa tính kỹ năng; tỉ lệ so với vũ khí khởi đầu của class)

**ranger** (khởi đầu 25.0 dps): SMG 44.1 (x1.76), Flamethrower 32.1 (x1.29), Spear 31.4 (x1.25), Longbow 31.1 (x1.24), Longsword 26.7 (x1.07), Crossbow 25.6 (x1.02), Pistol 25.0 (x1.00), Daggers 25.0 (x1.00), War Hammer 25.0 (x1.00), Arcane Staff 23.0 (x0.92), Railgun 22.0 (x0.88), Scythe 21.6 (x0.86), Laser Gun 21.0 (x0.84), Shotgun 18.0 (x0.72), Chakram 10.6 (x0.42)

**brawler** (khởi đầu 30.0 dps): Spear 35.5 (x1.18), SMG 35.3 (x1.18), Flamethrower 32.1 (x1.07), Longsword 30.0 (x1.00), War Hammer 28.3 (x0.94), Daggers 28.1 (x0.94), Longbow 27.8 (x0.93), Scythe 24.4 (x0.81), Crossbow 22.9 (x0.76), Pistol 22.5 (x0.75), Arcane Staff 21.0 (x0.70), Railgun 19.2 (x0.64), Laser Gun 18.0 (x0.60), Shotgun 15.0 (x0.50), Chakram 9.4 (x0.31)

**mage** (khởi đầu 21.0 dps): SMG 35.3 (x1.68), Flamethrower 32.1 (x1.53), Spear 31.4 (x1.49), Longbow 27.8 (x1.32), Longsword 26.7 (x1.27), Daggers 25.0 (x1.19), War Hammer 25.0 (x1.19), Crossbow 22.9 (x1.09), Pistol 22.5 (x1.07), Scythe 21.6 (x1.03), Arcane Staff 21.0 (x1.00), Railgun 19.2 (x0.92), Laser Gun 18.0 (x0.86), Shotgun 15.0 (x0.71), Chakram 9.4 (x0.45)

**rogue** (khởi đầu 28.8 dps): SMG 40.6 (x1.41), Flamethrower 37.0 (x1.29), Spear 36.1 (x1.25), Longbow 32.0 (x1.11), Longsword 30.7 (x1.07), Daggers 28.8 (x1.00), War Hammer 28.8 (x1.00), Crossbow 26.4 (x0.92), Pistol 25.9 (x0.90), Scythe 24.8 (x0.86), Arcane Staff 24.1 (x0.84), Railgun 22.1 (x0.77), Laser Gun 20.7 (x0.72), Shotgun 17.2 (x0.60), Chakram 10.8 (x0.37)

**summoner** (khởi đầu 9.4 dps): SMG 35.3 (x3.76), Flamethrower 32.1 (x3.43), Spear 31.4 (x3.35), Longbow 27.8 (x2.97), Longsword 26.7 (x2.84), Daggers 25.0 (x2.67), War Hammer 25.0 (x2.67), Crossbow 22.9 (x2.45), Pistol 22.5 (x2.40), Scythe 21.6 (x2.30), Arcane Staff 21.0 (x2.24), Railgun 19.2 (x2.05), Laser Gun 18.0 (x1.92), Shotgun 15.0 (x1.60), Chakram 9.4 (x1.00)

## 5. Ultimate + kỹ năng tiến hoá (chỉ số, trung bình mọi class = 100)

Mỗi biến thể: vũ khí + kỹ năng (khởi đầu hoặc tiến hoá A/B) + Ultimate trung bình. Chi tiết DPS tầng 6 ở cuối mục.

| Tầng | Biến thể | ranger | brawler | mage | rogue | summoner | lệch max |
|---|---|---|---|---|---|---|---|
| 1 | Khởi đầu+Ult | 106 | 102 | 81 | 107 | 104 | 26 |
| 1 | A+Ult | 126 | 95 | 76 | 104 | 100 | 50 |
| 1 | B+Ult | 95 | 109 | 72 | 112 | 112 | 40 |
| 3 | Khởi đầu+Ult | 104 | 99 | 79 | 103 | 115 | 36 |
| 3 | A+Ult | 135 | 89 | 74 | 96 | 106 | 61 |
| 3 | B+Ult | 94 | 105 | 70 | 108 | 123 | 53 |
| 4 | Khởi đầu+Ult | 105 | 95 | 76 | 103 | 121 | 45 |
| 4 | A+Ult | 141 | 84 | 71 | 94 | 110 | 70 |
| 4 | B+Ult | 96 | 101 | 67 | 107 | 129 | 62 |
| 6 | Khởi đầu+Ult | 102 | 92 | 78 | 101 | 128 | 50 |
| 6 | A+Ult | 142 | 81 | 70 | 91 | 116 | 72 |
| 6 | B+Ult | 95 | 98 | 66 | 105 | 137 | 71 |
| 7 | Khởi đầu+Ult | 102 | 93 | 73 | 101 | 131 | 58 |
| 7 | A+Ult | 146 | 80 | 68 | 89 | 117 | 78 |
| 7 | B+Ult | 95 | 98 | 63 | 106 | 139 | 76 |
| 9 | Khởi đầu+Ult | 97 | 86 | 75 | 105 | 137 | 62 |
| 9 | A+Ult | 149 | 74 | 67 | 91 | 120 | 82 |
| 9 | B+Ult | 93 | 91 | 61 | 109 | 145 | 84 |
| 10 | Khởi đầu+Ult | 92 | 90 | 75 | 99 | 143 | 68 |
| 10 | A+Ult | 148 | 76 | 66 | 85 | 124 | 82 |
| 10 | B+Ult | 89 | 95 | 61 | 104 | 151 | 90 |

- ranger Khởi đầu+Ult: vũ khí 25.0 + kỹ năng 8.3 + ult 5.5 = 38.8 dps
- brawler Khởi đầu+Ult: vũ khí 30.0 + kỹ năng 2.4 + ult 2.7 = 35.0 dps
- mage Khởi đầu+Ult: vũ khí 21.0 + kỹ năng 7.5 + ult 1.3 = 29.8 dps
- rogue Khởi đầu+Ult: vũ khí 28.8 + kỹ năng 3.0 + ult 6.7 = 38.4 dps
- summoner Khởi đầu+Ult: vũ khí 9.4 + kỹ năng 23.3 + ult 16.1 = 48.8 dps
- ranger A+Ult: vũ khí 25.0 + kỹ năng 31.8 + ult 5.5 = 62.3 dps
- brawler A+Ult: vũ khí 30.0 + kỹ năng 3.0 + ult 2.7 = 35.7 dps
- mage A+Ult: vũ khí 21.0 + kỹ năng 8.7 + ult 1.3 = 31.0 dps
- rogue A+Ult: vũ khí 28.8 + kỹ năng 4.5 + ult 6.7 = 39.9 dps
- summoner A+Ult: vũ khí 9.4 + kỹ năng 25.4 + ult 16.1 = 50.9 dps
- ranger B+Ult: vũ khí 25.0 + kỹ năng 4.7 + ult 5.5 = 35.2 dps
- brawler B+Ult: vũ khí 30.0 + kỹ năng 3.6 + ult 2.7 = 36.3 dps
- mage B+Ult: vũ khí 21.0 + kỹ năng 2.1 + ult 1.3 = 24.3 dps
- rogue B+Ult: vũ khí 28.8 + kỹ năng 3.6 + ult 6.7 = 39.0 dps
- summoner B+Ult: vũ khí 9.4 + kỹ năng 25.3 + ult 16.1 = 50.8 dps

## 6. Ghi chú đọc số liệu
- Giáp boss giảm theo phần trăm (K=30); đạn nhỏ (SMG, Flamethrower) bị phạt như mọi vũ khí nhưng làm tròn tối thiểu 1 sát thương/đòn.
- Mục tiêu dự án: mọi class trong ±8% so với trung bình (cột lệch max ≤ 16). Class chênh quá ~25% so với trung bình ở nhiều tầng liên tiếp đáng cân nhắc chỉnh; dưới ~15% coi như cân bằng.
- Giả định Ultimate/tiến hoá (đổi ở hằng số đầu file): nạp ult = min(6, đòn/s x 0.7) + 0.4 (hạ quái) + 0.6 (nhận 1% máu/s); tỉ lệ ult trúng boss BOSS_HIT (Bullet Storm 13%, Starfall 15%, Blade Tempest 70%, Earthquake 100%); Summoner tiến hoá cộng thêm lên lính; Smoke Veil 1 nhịp/0.5s; Shadow Rush ước lượng. Chưa kiểm chứng bằng chơi thật.
- Chưa tính: sát thương diện rộng (Arcane Staff nổ, Flamethrower/Scythe xuyên nhiều quái — lợi thế của mage trong bầy quái bị đánh giá thấp ở bảng boss), buff (Power/Crit/Berserk/...), rank vũ khí, trạng thái (cháy/độc/chảy máu), mastery, né/di chuyển, mô hình lượng sát thương nhận.
