#!/usr/bin/env python3
"""Cắt sprite trang trí phòng (biểu ngữ, hố tường, chất nhờn, đài phun nước, cột áp tường, sọ) từ atlas gốc 0x72 DungeonTilesetII v1.3 (CC0).
Chạy: python3 tools/gen_decor_sprites.py <đường_dẫn_atlas.png>   rồi: godot --headless --path . --import  và  python3 tools/hk/gen_bodies.py
Atlas lấy từ bản mirror công khai (xem assets/dungeon/CREDITS.md); không commit atlas, chỉ commit PNG đã cắt."""
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "dungeon")

if len(sys.argv) < 2:
    sys.exit(__doc__)
atlas = Image.open(sys.argv[1]).convert("RGBA")


def crop(x, y, w=16, h=16):
    return atlas.crop((x, y, x + w, y + h))


def stack(*parts):
    im = Image.new("RGBA", (16, 16 * len(parts)), (0, 0, 0, 0))
    for i, p in enumerate(parts):
        im.paste(p, (0, 16 * i))
    return im


sprites = {
    "decor_banner_red": crop(16, 32), "decor_banner_blue": crop(32, 32),
    "decor_banner_green": crop(16, 48), "decor_banner_yellow": crop(32, 48),
    "decor_hole": crop(48, 32),
    "decor_goo": stack(crop(64, 80), crop(64, 96)),
    "decor_column_wall": crop(96, 80, 16, 48),
    "decor_skull": crop(288, 320),
}
for k, x in enumerate((64, 80, 96)):   # đài phun: đỉnh + thân + bể, 3 khung hoạt hoạ
    sprites["decor_fountain_red_anim_f%d" % k] = stack(crop(x, 0), crop(x, 16), crop(x, 32))
    sprites["decor_fountain_blue_anim_f%d" % k] = stack(crop(x, 0), crop(x, 48), crop(x, 64))
for name, im in sprites.items():
    im.save(os.path.join(OUT, name + ".png"))
print("wrote", len(sprites), "sprites")
