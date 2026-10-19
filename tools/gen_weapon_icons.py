#!/usr/bin/env python3
"""Tạo 5 icon vũ khí mới (16x16, mũi vũ khí hướng sang PHẢI, giống các weapon_*.png hiện có).

- spear, staff: cắt từ atlas 0x72 DungeonTilesetII v1.3 (CC0) rồi XOAY 90° và BỎ đoạn cán giữa (giữ nguyên từng
  pixel, không co ảnh) để vừa khung 16px. Cần đường dẫn atlas: python3 tools/gen_weapon_icons.py <atlas.png>
- bow, railgun, scythe: pixel-art tự vẽ bằng script (0x72 không có), dùng đúng bảng màu + viền 1px của các icon cũ.
Không có atlas thì chỉ tạo 3 icon tự vẽ.
"""
import sys
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "dungeon"
K = (18, 14, 18, 255)  # viền
PAL = {
    "g": (158, 166, 178, 255), "G": (225, 230, 235, 255), "d": (92, 98, 110, 255),
    "w": (168, 122, 74, 255), "W": (120, 84, 50, 255), "D": (74, 50, 30, 255),
    "c": (79, 198, 198, 255), "C": (102, 255, 255, 255),
    "r": (198, 99, 39, 255), "o": (255, 127, 51, 255),
}

def from_rows(rows):
    """rows: 16 chuỗi (ký tự bảng màu, '.' = trong suốt); tự thêm viền K quanh các pixel có màu."""
    assert len(rows) == 16, f"need 16 rows, got {len(rows)}"
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    filled = {}
    for y, row in enumerate(rows):
        row = row.rstrip(".")  # chỉ phần ruột quan trọng; '.' cuối dòng là trống
        assert len(row) <= 16, f"row {y} has width {len(row)} > 16"
        row = row.ljust(16, ".")
        for x, ch in enumerate(row):
            if ch != ".":
                filled[(x, y)] = PAL[ch]
    for (x, y), col in filled.items():
        img.putpixel((x, y), col)
    for (x, y) in list(filled):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < 16 and 0 <= ny < 16 and (nx, ny) not in filled:
                img.putpixel((nx, ny), K)
    return img

# 16 cột x 16 hàng, viền tự sinh nên chỉ vẽ phần ruột (chừa 1px mép cho viền).
BOW = [
    "................",
    "................",
    "......ww........",
    ".....wWw........",
    ".....G.ww.......",
    ".....G..wW......",
    ".....G...wW.....",
    ".....G...wW.....",
    ".GGGGGGGGGGGGgg.",   # mũi tên xuyên qua dây cung, đầu mũi tên ở bên phải
    ".....G...wW.....",
    ".....G...wW.....",
    ".....G..wW......",
    ".....G.ww.......",
    ".....wWw........",
    "......ww........",
    "................",
]
RAILGUN = [
    "................",
    "................",
    "................",
    "......cccccccccc",
    "....GGGGGGGGGGGC",
    "..wwgggggggggggC",
    ".wwWddddddddddd.",
    ".wwW.dd..gg.....",
    "..W..dd.........",
    ".....d...........",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
]
SCYTHE = [
    "................",
    "................",
    "........ggg.....",
    "......ggGGGg....",
    ".....gGGggggg...",
    "....gGg....ggg..",
    "...gGg......gGg.",
    "...gg........gg.",
    "..g...........g.",
    "...............W",
    "....ww.........w",
    "wwwwwWwwwwwwwwww",
    ".WWWWWWWWWWWWWw.",
    "................",
    "................",
    "................",
]

def crop_rotate(atlas, box, keep_rows):
    x, y, w, h = box
    c = atlas.crop((x, y, x + w, y + h))
    rows = [c.crop((0, r, w, r + 1)) for r in keep_rows]
    t = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for i, r in enumerate(rows):
        t.paste(r, (0, i))
    t = t.rotate(-90, expand=True)  # xoay thuận chiều kim đồng hồ: đầu vũ khí (trên) -> bên phải
    out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    out.paste(t, (16 - t.width, (16 - t.height) // 2))
    return out

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    from_rows(BOW).save(OUT / "weapon_bow.png")
    from_rows(RAILGUN).save(OUT / "weapon_railgun.png")
    from_rows(SCYTHE).save(OUT / "weapon_scythe.png")
    if len(sys.argv) > 1:
        atlas = Image.open(sys.argv[1]).convert("RGBA")
        # spear 6x30: giữ hàng 0-13 (đầu giáo) + 28-29 (mũi cán) = 16; staff 8x30: giữ 0-8 + 23-29 = 16
        crop_rotate(atlas, (293, 177, 6, 30), list(range(0, 14)) + [28, 29]).save(OUT / "weapon_spear.png")
        crop_rotate(atlas, (340, 145, 8, 30), list(range(0, 9)) + list(range(23, 30))).save(OUT / "weapon_staff.png")
    print("done")

if __name__ == "__main__":
    main()
