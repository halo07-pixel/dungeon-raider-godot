#!/usr/bin/env python3
"""Sinh sprite quái Địa ngục (tầng 11-15) bằng cách đổi bảng màu theo độ sáng của sprite gốc
(obsidian -> tím -> hồng), vùng sáng nhất thành vàng lửa để mắt/viền phát sáng.
  hell_imp      <- imp (idle + run)          hell_ogre   <- ogre (idle + run)
  hell_acolyte  <- orc_shaman (1 bộ khung)   cinder_tiny <- frost_tiny (1 bộ khung)
Ghi vào assets/dungeon/. Chạy: python3 tools/gen_hell_enemies.py   (cần Pillow). Kết quả xác định."""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "dungeon")
# Tím obsidian phát sáng: tách khỏi nền Địa Ngục (đỏ/than) để quái luôn dễ đọc.
RAMP = [(12, 6, 22), (52, 20, 84), (112, 40, 156), (196, 76, 186), (255, 150, 130), (255, 236, 176)]
JOBS = [  # (nguồn, đích, số khung)
    ("imp_idle_anim_f%d", "hell_imp_idle_anim_f%d", 4),
    ("imp_run_anim_f%d", "hell_imp_run_anim_f%d", 4),
    ("ogre_idle_anim_f%d", "hell_ogre_idle_anim_f%d", 4),
    ("ogre_run_anim_f%d", "hell_ogre_run_anim_f%d", 4),
    ("orc_shaman_anim_f%d", "hell_acolyte_anim_f%d", 4),
    ("frost_tiny_anim_f%d", "cinder_tiny_anim_f%d", 4),
]

def ramp(t):
    t = max(0.0, min(1.0, t)) * (len(RAMP) - 1)
    i = min(int(t), len(RAMP) - 2)
    f = t - i
    a, b = RAMP[i], RAMP[i + 1]
    return tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3))

def recolor(img):
    out = Image.new("RGBA", img.size)
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = img.getpixel((x, y))
            if a == 0:
                out.putpixel((x, y), (0, 0, 0, 0))
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            lum = max(0.0, min(1.0, (lum - 0.08) / 0.8))
            out.putpixel((x, y), ramp(lum ** 0.9) + (a,))
    return out

if __name__ == "__main__":
    n = 0
    for src, dst, frames in JOBS:
        for i in range(frames):
            path = os.path.join(OUT, (src % i) + ".png")
            recolor(Image.open(path).convert("RGBA")).save(os.path.join(OUT, (dst % i) + ".png"))
            n += 1
    print("wrote", n, "frames")
