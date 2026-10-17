#!/usr/bin/env python3
"""Sinh sprite pixel-art 16x16 cho Altar và Shrine (phòng sự kiện) -> assets/dungeon/.
Chạy: python3 tools/gen_event_sprites.py   (cần Pillow). Sprite tự tạo, bảng màu khớp tileset hiện có."""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "dungeon")

BASE = {
    "O": (34, 34, 34),        # viền, cùng màu viền các sprite sẵn có
    "a": (132, 128, 146),     # đá sáng
    "b": (92, 88, 104),       # đá giữa
    "c": (60, 57, 72),        # đá tối
    "m": (74, 116, 62),       # rêu
    "r": (122, 22, 38),       # máu sẫm
    "R": (214, 54, 66),       # máu sáng
    "g": (250, 150, 44),      # rune cam
    "G": (255, 214, 100),     # rune lõi sáng
    "k": (46, 40, 44),        # vết nứt
}

ALTAR = [
    "................",
    "................",
    "...OOOOOOOOOO...",
    "..OaaaaaaaaaaO..",
    "..OrRRRRRRRRrO..",
    "...ObbbbbbbbO...",
    "....OOObbOOO....",
    "....ObbbbbbO....",
    "....ObbabbcO....",
    "...OOOOOOOOOO...",
    "..OaaaaaaaaaaO..",
    "..ObbbbbbbbbbO..",
    "..ObbcbbkbcbbO..",
    "..OccccccccccO..",
    "..OOOOOOOOOOOO..",
    "................",
]
SHRINE = [
    "................",
    ".....OOOOOO.....",
    "....OaaaaaaO....",
    "....ObbbbbbO....",
    "....ObbGGbbO....",
    "....ObgGGgbO....",
    "....ObbggbbO....",
    "....ObgbbgbO....",
    "....ObbbbbbO....",
    "....ObbkbbcO....",
    "...OOObbbbcOOO..",
    "..OaaaaaaaaaaO..",
    "..ObbbbbbbbbbO..",
    "..OccccccccccO..",
    "..OOOOOOOOOOOO..",
    "................",
]

def render(rows, pal):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        assert len(row) == 16, (y, row)
        for x, ch in enumerate(row):
            if ch in pal:
                im.putpixel((x, y), pal[ch] + (255,))
    return im

def with_moss(rows):
    r = [list(x) for x in rows]
    for (x, y) in [(3, 11), (4, 11), (12, 10), (3, 12)]:
        if r[y][x] in "ab": r[y][x] = "m"
    return ["".join(x) for x in r]

def used_pal(p):
    q = {}
    for k, (r, g, b) in p.items():
        if k == "O":
            q[k] = (r, g, b); continue
        lum = (r + g + b) / 3
        q[k] = (int(r * 0.45 + lum * 0.3), int(g * 0.45 + lum * 0.3), int(b * 0.45 + lum * 0.3))
    q["r"] = (58, 34, 38); q["R"] = (74, 42, 46)      # máu khô
    q["g"] = (78, 56, 50); q["G"] = (96, 66, 56)      # rune tắt
    return q

if __name__ == "__main__":
    render(with_moss(ALTAR), BASE).save(os.path.join(OUT, "altar_idle.png"))
    render(with_moss(ALTAR), used_pal(BASE)).save(os.path.join(OUT, "altar_used.png"))
    render(SHRINE, BASE).save(os.path.join(OUT, "shrine_idle.png"))
    render(SHRINE, used_pal(BASE)).save(os.path.join(OUT, "shrine_used.png"))
    print("ok")
