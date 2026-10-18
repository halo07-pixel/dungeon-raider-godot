#!/usr/bin/env python3
"""Sinh tileset biome "Hell" (đỏ địa ngục) từ tile đá gốc bằng cách đổi bảng màu theo độ sáng,
cộng vết nứt than hồng; và 4 khung hoạt ảnh Ô Dung Nham. Ghi vào assets/dungeon/ (hậu tố _hell).
Chạy: python3 tools/gen_hell_tiles.py   (cần Pillow). Kết quả xác định (seed theo tên tile)."""
from PIL import Image
import os, random

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "dungeon")
NAMES = ["floor_1", "floor_2", "floor_3", "floor_4", "floor_5", "floor_6", "floor_7", "floor_8",
         "wall_top_left", "wall_top_mid", "wall_top_right", "wall_left", "wall_right",
         "wall_edge_bottom_left", "wall_edge_bottom_right", "wall_mid"]

# Bảng màu theo độ sáng 0..1 (than đen -> đỏ sẫm -> đỏ gạch)
FLOOR_RAMP = [(10, 4, 6), (46, 10, 12), (92, 20, 16), (150, 38, 22)]
WALL_RAMP = [(10, 3, 6), (44, 10, 14), (92, 18, 18), (150, 34, 24)]
EMBER = [(255, 90, 20), (255, 150, 40)]

def ramp(stops, t):
    t = max(0.0, min(1.0, t)) * (len(stops) - 1)
    i = min(int(t), len(stops) - 2)
    f = t - i
    a, b = stops[i], stops[i + 1]
    return tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3))

def remap(name):
    src = Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")
    is_floor = name.startswith("floor")
    stops = FLOOR_RAMP if is_floor else WALL_RAMP
    rng = random.Random(name)
    out = Image.new("RGBA", src.size)
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = src.getpixel((x, y))
            if a == 0:
                out.putpixel((x, y), (0, 0, 0, 0))
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            lum = (lum - 0.15) / 0.75
            out.putpixel((x, y), ramp(stops, lum) + (a,))
    # vết nứt than hồng: chuỗi điểm ngắn ngẫu nhiên
    cracks = 2 if is_floor else 1
    for _ in range(cracks):
        x, y = rng.randrange(2, src.width - 2), rng.randrange(2, src.height - 2)
        for _ in range(rng.randint(3, 6)):
            if out.getpixel((x, y))[3] > 0:
                out.putpixel((x, y), EMBER[rng.randint(0, 1)] + (255,))
            x = max(1, min(src.width - 2, x + rng.choice([-1, 0, 1])))
            y = max(1, min(src.height - 2, y + rng.choice([-1, 0, 1])))
    out.save(os.path.join(OUT, name + "_hell.png"))

def lava_frame(idx):
    rng = random.Random(100 + idx)
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            edge = min(x, y, 15 - x, 15 - y)
            if edge == 0 and (x + y) % 2 == 0:
                continue
            phase = (x * 3 + y * 5 + idx * 4) % 16 / 15.0
            t = 0.35 + 0.45 * abs(phase - 0.5) * 2 + rng.random() * 0.12
            if edge == 0:
                col = (60, 10, 8)           # lớp vỏ nguội viền
            elif edge == 1:
                col = (170, 36, 12)
            else:
                col = ramp([(190, 40, 10), (255, 100, 20), (255, 190, 60)], t)
            im.putpixel((x, y), col + (255,))
    im.save(os.path.join(OUT, "floor_lava_anim_f%d.png" % idx))

if __name__ == "__main__":
    for n in NAMES:
        remap(n)
    for i in range(4):
        lava_frame(i)
    print("ok")
