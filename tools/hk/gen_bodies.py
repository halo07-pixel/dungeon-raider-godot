#!/usr/bin/env python3
"""Đo vùng mờ đục (phần nhìn thấy) của mọi sprite trong assets/dungeon rồi sinh hk/bodies.gd.
Chạy: python3 tools/hk/gen_bodies.py   — chạy lại mỗi khi đổi/thêm sprite.
Mỗi mục là Rect2 theo pixel ảnh gốc, gốc toạ độ = giữa-đáy ảnh (chân nhân vật): x âm = trái, y âm = lên.
Hoạt ảnh (base_f0..fN) lấy hợp của mọi khung nên hộp không rung theo khung."""
import glob
import os
import re

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "assets", "dungeon")
OUT = os.path.join(ROOT, "hk", "bodies.gd")

groups = {}
for f in sorted(glob.glob(os.path.join(SRC, "*.png"))):
    n = os.path.basename(f)[:-4]
    groups.setdefault(re.sub(r"_f\d+$", "", n), []).append(f)

rects = {}
for base, files in sorted(groups.items()):
    x0 = y0 = 10 ** 9
    x1 = y1 = -10 ** 9
    for f in files:
        im = Image.open(f).convert("RGBA")
        b = im.split()[3].getbbox()
        if b is None:
            continue
        w, h = im.size
        x0, y0 = min(x0, b[0] - w / 2), min(y0, b[1] - h)
        x1, y1 = max(x1, b[2] - w / 2), max(y1, b[3] - h)
    if x1 > x0:
        rects[base] = (x0, y0, x1 - x0, y1 - y0)

lines = ["extends RefCounted",
         "## SINH TỰ ĐỘNG bởi tools/hk/gen_bodies.py — đừng sửa tay.",
         "## Vùng nhìn thấy của sprite (pixel ảnh gốc, gốc = giữa-đáy ảnh). Hitbox, thanh máu, vùng tương tác đều đọc từ đây.",
         "const RECTS: Dictionary = {"]
for k, (x, y, w, h) in rects.items():
    lines.append('\t"%s": Rect2(%g, %g, %g, %g),' % (k, x, y, w, h))
lines += ["}", "",
          "## Vùng nhìn thấy của `base`, phóng `scale` lần (gốc vẫn ở chân).",
          "static func rect(base: String, scale: float = 1.0) -> Rect2:",
          "\tvar r: Rect2 = RECTS.get(base, Rect2(-8.0, -16.0, 16.0, 16.0))",
          "\treturn Rect2(r.position * scale, r.size * scale)", "",
          "## Hợp vùng nhìn thấy của nhiều hoạt ảnh (vd. đứng + chạy + trúng đòn của người chơi).",
          "static func union(bases: Array, scale: float = 1.0) -> Rect2:",
          "\tvar out: Rect2 = rect(String(bases[0]), scale)",
          "\tfor b in bases:",
          "\t\tout = out.merge(rect(String(b), scale))",
          "\treturn out", ""]
open(OUT, "w", encoding="utf-8").write("\n".join(lines))
print("ghi %s: %d mục" % (OUT, len(rects)))
