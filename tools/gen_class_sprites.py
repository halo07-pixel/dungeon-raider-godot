#!/usr/bin/env python3
"""Cắt sprite nhân vật Mage (wizzard_m) và Rogue (lizard_m) từ atlas 0x72 DungeonTilesetII v1.3 (CC0)
thành từng frame 16x28 căn đáy (cùng khuôn với elf_m/knight_m), lưu vào assets/dungeon/.
Chạy: python3 tools/gen_class_sprites.py <đường dẫn 0x72_DungeonTilesetII_v1_3.png>"""
import sys
from PIL import Image

# prefix_đầu_ra: (tên trong atlas, {anim: (x, y, w, h, số_frame)})
SETS = {
    "wizard_m": {"idle": (128, 170, 16, 22, 4), "run": (192, 170, 16, 22, 4), "hit": (256, 164, 16, 28, 1)},
    "lizard_m": {"idle": (128, 237, 16, 19, 4), "run": (192, 237, 16, 19, 4), "hit": (256, 237, 16, 19, 1)},
}

def main(atlas_path):
    atlas = Image.open(atlas_path).convert("RGBA")
    for prefix, anims in SETS.items():
        for anim, (x, y, w, h, n) in anims.items():
            for i in range(n):
                fr = atlas.crop((x + i * w, y, x + (i + 1) * w, y + h))
                out = Image.new("RGBA", (16, 28), (0, 0, 0, 0))
                out.paste(fr, (0, 28 - h))
                out.save("assets/dungeon/%s_%s_anim_f%d.png" % (prefix, anim, i))

if __name__ == "__main__":
    main(sys.argv[1])
