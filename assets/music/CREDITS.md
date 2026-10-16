# Âm nhạc - Dungeon Raider

Toàn bộ nhạc dưới đây thuộc **CC0 1.0 Universal (public domain)**. Không bắt buộc ghi công, vẫn liệt kê để minh bạch nguồn.

## Nhạc nền và nhạc boss (FreePD)
- Nguồn: https://freepd.com - trang ghi: "This music is all licensed CC0 1.0 Universal Public Domain Dedication."
- File gốc lấy qua bản mirror công khai trên GitHub (repo SoundSafari/CC0-1.0-Music, thư mục `freepd.com`) vì môi trường build không truy cập trực tiếp freepd.com được. Giấy phép đối chiếu với lời khẳng định của chính freepd.com, không dựa vào mirror.
- Trang freepd.com đã đối chiếu không nêu tên nhạc sĩ từng bài nên không liệt kê tên.
- Chỉnh sửa cho game: cắt đoạn lặp, nối đầu-cuối bằng crossfade công suất đều (lặp liền mạch), chuẩn hoá độ lớn (LUFS), mã hoá lại Ogg Vorbis (q4).

| Vị trí trong game | File | Bài gốc (FreePD) | Đoạn lấy (giây) |
|---|---|---|---|
| Main Menu | `menu.ogg` | Night in the Castle | 0.5 - 187.0 |
| Biome 1 (đá, tầng 1-3) | `explore_stone.ogg` | Ancient Rite | 0 - 110.0 |
| Biome 2 (đầm lầy, tầng 4-6) | `explore_swamp.ogg` | Murder On The Bayou | 0 - 119.5 |
| Biome 3 (băng, tầng 7-9 và 11+) | `explore_ice.ogg` | Icicles Melting | 1.0 - 176.5 |
| Boss Dungeon Warden | `boss_warden.ogg` | Black Knight | 66.2 - 114.8 |
| Boss Dark Necromancer | `boss_necromancer.ogg` | Evil Incoming | 0 - 168.5 |
| Boss Frozen Horror | `boss_frost.ogg` | Jokull | 101.0 - 242.5 |
| Tầng 10, trước khi vào phòng Lord | `lord_intro.ogg` | Dawn of the Apocalypse | 6.0 - 140.3 |
| Dungeon Lord, vào trận | `lord_fight.ogg` | Epic Boss Battle | 50.3 - 99.5 |
| Dungeon Lord, từ pha 3 (dưới 50% máu) | `lord_final.ogg` | Uberpunch | 24.5 - 90.2 |

## Tiếng nhấn (Beatscribe)
- Nguồn: https://github.com/Beatscribe/homebrew_vgm (thư mục `NES/ogg`). README của repo ghi: "They are available under Creative Commons Zero". Ghi công "Beatscribe" là tuỳ chọn.
- Chỉnh sửa: chuẩn hoá độ lớn (-16 LUFS), mã hoá lại Ogg Vorbis (q5).

| Sự kiện | File | Bài gốc |
|---|---|---|
| Boss xuất hiện | `stinger_boss_appears.ogg` | boss_appears |
| Hạ boss | `stinger_victory.ogg` | victory |
| Game Over | `stinger_game_over.ogg` | game_over |

## Bài dự phòng (không nằm trong repo)
Mỗi vị trí còn 1-3 bài dự phòng đã xử lý sẵn cùng cách, cùng nguồn FreePD, để đổi nếu nghe thử thấy không hợp: Consecrated Ground, Creepy Hallow, Lurking Sloth, Midnight in the Green House, The Land of the Dead, Ice and Snow, Parhelion, Honor Bound, Behind Enemy Lines, Release the Hybrids, Beginning of Conflict, The Ice Giants, Northur, Strength of the Titans, Epic Blockbuster 2, Fright Night Twist.
