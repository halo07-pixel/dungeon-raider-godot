#!/usr/bin/env python3
"""Sinh sprite pixel-art + hoạt ảnh cho: Lò Rèn, Cổng (xuống tầng / Council), Tome, Sigil, và các loại lính (minion).
Chạy: python3 tools/gen_art_pass.py   (cần Pillow). Tất cả là hình tự tạo (không lấy từ nguồn ngoài), bảng màu khớp tileset 0x72.
Lính/Sigil vẽ bằng sắc xám-trắng để game nhân màu (modulate) theo màu từng loại/độ hiếm."""
from PIL import Image
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "dungeon")
OL = (34, 34, 34, 255)  # viền, cùng màu viền các sprite sẵn có


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c if len(c) == 4 else (*c, 255))


def rect(im, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(im, x, y, c)


def disc(im, cx, cy, r, c):
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                px(im, x, y, c)


def outline(im, col=OL):
    src = im.copy()
    for y in range(im.height):
        for x in range(im.width):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < im.width and 0 <= ny < im.height and src.getpixel((nx, ny))[3] > 200:
                        im.putpixel((x, y), col)
                        break
    return im


def save(im, name):
    im.save(os.path.join(OUT, name))


def rnd(a, b=0):
    """Số giả ngẫu nhiên ổn định trong [0,1) theo (a,b) — để các khung hình lặp lại giống nhau giữa các lần chạy."""
    return (math.sin(a * 12.9898 + b * 78.233) * 43758.5453) % 1.0


# ------------------------------------------------------------------ Lò Rèn (32x24, 4 khung)
STEEL = [(60, 62, 76), (92, 96, 112), (128, 134, 152), (176, 182, 198)]
STONE = [(52, 48, 60), (78, 74, 90), (108, 104, 122), (140, 136, 154)]
FIRE = [(150, 28, 24), (230, 76, 24), (255, 150, 36), (255, 214, 96), (255, 246, 190)]


def forge(frame):
    im = new(32, 24)
    # --- lò (bên phải): thân đá, ống khói, miệng lò
    rect(im, 17, 7, 30, 22, STONE[1])
    for y in range(7, 23):
        for x in range(17, 31):
            brick = (y // 4 + (x + (y // 4) * 3) // 7) % 2
            if (y % 4 == 0) or ((x + (y // 4) * 3) % 7 == 0):
                px(im, x, y, STONE[0])
            elif brick:
                px(im, x, y, STONE[2])
    rect(im, 17, 7, 30, 8, STONE[3])
    rect(im, 24, 0, 28, 7, STONE[1])
    rect(im, 24, 0, 28, 1, STONE[3])
    rect(im, 25, 2, 27, 7, STONE[0])
    # miệng lò (vòm) + lửa
    rect(im, 19, 12, 28, 21, (24, 14, 18))
    rect(im, 20, 11, 27, 11, (24, 14, 18))
    for x in range(20, 28):
        h = 4 + int(rnd(x, frame) * 4) + (1 if frame % 2 == 0 else 0)
        for k in range(h):
            y = 21 - k
            t = k / max(h - 1, 1)
            c = FIRE[min(4, int(t * 4.2))]
            if k > 0 and rnd(x * 3 + k, frame + 7) < 0.18:
                c = FIRE[max(0, min(4, int(t * 4.2)) - 1)]
            px(im, x, y, c)
    rect(im, 19, 21, 28, 22, FIRE[0] if frame % 2 else FIRE[1])
    # tàn lửa bay ra khỏi ống khói
    for i in range(3):
        ph = (frame * 0.25 + i * 0.33) % 1.0
        px(im, 26 + int((i - 1) * 2 + math.sin(ph * 6 + i) * 1.5), 0 - 0 + int(2 - ph * 2), (*FIRE[3], int(255 * (1 - ph))))
    # --- đe (bên trái)
    rect(im, 3, 19, 13, 22, STEEL[0])
    rect(im, 5, 14, 11, 18, STEEL[1])
    rect(im, 1, 10, 14, 13, STEEL[2])
    rect(im, 1, 10, 14, 10, STEEL[3])
    px(im, 0, 11, STEEL[2]); px(im, 0, 12, STEEL[1])  # mũi đe
    px(im, 15, 11, STEEL[1])
    rect(im, 2, 13, 13, 13, STEEL[1])
    # sắt nung đỏ trên đe + tia lửa khi búa nện (khung 1 và 3)
    rect(im, 5, 8, 10, 9, FIRE[1] if frame in (0, 2) else FIRE[3])
    px(im, 5, 8, FIRE[2]); px(im, 10, 9, FIRE[0])
    if frame in (1, 3):
        for (sx, sy) in ((3, 6), (7, 4), (11, 5), (12, 7), (1, 8)) if frame == 1 else ((4, 5), (8, 3), (10, 6), (13, 8)):
            px(im, sx, sy, FIRE[4])
    return outline(im)


# ------------------------------------------------------------------ Cổng (28x28, 6 khung)
def portal(frame, pal):
    im = new(28, 28)
    cx = cy = 13.5
    spin = frame / 6.0 * 2 * math.pi
    for y in range(28):
        for x in range(28):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if r > 13.4:
                continue
            ang = math.atan2(dy, dx)
            arm = (math.sin(5 * (ang - spin) + r * 0.9) + 1) / 2  # 5 nhánh xoắn quay, lõi là đĩa sáng tròn
            ring = 1.0 if 10.5 <= r <= 13.2 else 0.0
            v = 0.2 + 0.55 * arm * min(1.0, r / 4.0) * (1 - r / 15) + 0.9 * max(0.0, 1.0 - r / 3.2)
            if ring:
                gap = (math.sin(5 * (ang + spin * 1.5)) + 1) / 2
                v = 0.6 + 0.4 * gap
            idx = min(len(pal) - 1, int(v * len(pal)))
            a = 255 if r < 12.6 else int(255 * (13.4 - r) / 0.8)
            c = pal[idx]
            px(im, x, y, (*c, max(0, min(255, a))))
    return im


PORTAL_PAL = [(32, 20, 90), (60, 44, 160), (96, 80, 230), (150, 140, 255), (225, 220, 255)]
COUNCIL_PAL = [(80, 10, 20), (150, 24, 28), (230, 60, 36), (255, 140, 70), (255, 235, 190)]


# ------------------------------------------------------------------ Tome (16x16, 2 khung)
def tome(frame):
    im = new(16, 16)
    rect(im, 3, 3, 12, 13, (86, 48, 140))
    rect(im, 3, 3, 5, 13, (150, 110, 210))   # gáy sách sáng
    rect(im, 12, 3, 12, 13, (58, 30, 98))
    rect(im, 4, 13, 12, 14, (232, 222, 190))  # mép giấy
    rect(im, 6, 5, 11, 5, (122, 78, 178))
    # biểu tượng vàng ở giữa bìa
    for (x, y) in ((8, 7), (7, 8), (8, 8), (9, 8), (8, 9)):
        px(im, x, y, (255, 214, 100))
    px(im, 8, 8, (255, 246, 190))
    # khóa gài
    rect(im, 11, 8, 12, 9, (255, 214, 100))
    outline(im)
    if frame == 1:
        for (x, y) in ((2, 2), (13, 4), (1, 9), (14, 11)):
            px(im, x, y, (255, 246, 190))
    return im


# ------------------------------------------------------------------ Sigil (16x16, 2 khung), sắc xám-trắng để nhân màu
def sigil(frame):
    im = new(16, 16)
    for y in range(16):
        for x in range(16):
            d = abs(x - 7.5) / 7.0 + abs(y - 7.5) / 7.5
            if d <= 1.0:
                v = 235 if d > 0.78 else (190 if d > 0.5 else 120)
                px(im, x, y, (v, v, v))
    # rune khắc ở giữa
    for (x, y) in ((7, 5), (8, 5), (7, 6), (8, 7), (7, 8), (8, 9), (7, 10), (8, 10)):
        px(im, x, y, (250, 250, 250) if frame == 0 else (255, 255, 255))
    for (x, y) in ((5, 7), (10, 8)):
        px(im, x, y, (250, 250, 250))
    if frame == 1:
        for (x, y) in ((7, 1), (8, 14), (2, 7), (13, 8)):
            px(im, x, y, (255, 255, 255))
    return outline(im)


# ------------------------------------------------------------------ Lính (16x16, 2 khung), xám-trắng để nhân màu
W, L, M, D = (245, 245, 245), (215, 215, 215), (170, 170, 175), (86, 86, 98)
EYE = (30, 30, 46)


def eyes(im, y, f=0):
    px(im, 5, y, EYE); px(im, 10, y, EYE)
    if f == 1:
        px(im, 5, y + 1, EYE); px(im, 10, y + 1, EYE)


def m_spirit(f):
    im = new(16, 16)
    disc(im, 8, 7, 5.5, L)
    rect(im, 3, 7, 12, 12, L)
    for x in range(3, 13):  # đuôi bóng ma lượn sóng
        px(im, x, 13 + ((x + f) % 2), L)
    disc(im, 6, 5, 2.2, W)
    eyes(im, 7, f)
    rect(im, 3, 9, 3, 12, M); rect(im, 12, 9, 12, 12, M)
    return outline(im)


def m_wisp(f):
    im = new(16, 16)
    disc(im, 8, 8 - f, 4.5, L)
    disc(im, 7, 7 - f, 2.5, W)
    for k in range(5):  # đuôi lửa
        px(im, 8 + (k % 2) - 1, 12 - f + k // 2, M)
    px(im, 8, 14, D)
    px(im, 3 + f, 3, W); px(im, 13 - f, 4, W)
    eyes(im, 8 - f)
    return outline(im)


def m_guardian(f):
    im = new(16, 16)
    # khiên chữ nhật bo + gờ
    rect(im, 3, 2, 12, 11, L)
    for y in range(11, 15):
        rect(im, 3 + (y - 11), y, 12 - (y - 11), y, L)
    rect(im, 3, 2, 12, 3, W)
    rect(im, 7, 3, 8, 13, M)  # sống khiên
    rect(im, 4, 6, 11, 7, M)
    px(im, 7, 5, W); px(im, 8, 5, W)
    if f == 1:
        rect(im, 4, 4, 4, 9, W)
    return outline(im)


def m_turret(f):
    im = new(16, 16)
    rect(im, 3, 11, 12, 14, M)               # đế
    rect(im, 5, 6, 10, 11, L)                # thân
    rect(im, 5, 6, 10, 7, W)
    rect(im, 10, 8, 14, 9, D)                # nòng
    px(im, 14, 8, W if f == 0 else L)
    disc(im, 7, 9, 1.3, D)
    if f == 1:
        px(im, 15, 8, W); px(im, 15, 9, W)
    return outline(im)


def m_totem(f):
    im = new(16, 16)
    rect(im, 5, 5, 10, 14, L)                # cột
    rect(im, 5, 5, 6, 14, W)
    rect(im, 9, 5, 10, 14, M)
    rect(im, 3, 6, 4, 7, L); rect(im, 11, 6, 12, 7, L)   # cánh hai bên
    rect(im, 6, 7, 9, 8, D)                  # mắt
    rect(im, 7, 10, 8, 11, D)                # miệng
    rect(im, 4, 13, 11, 14, M)               # chân
    disc(im, 8, 3, 2.4, W if f == 0 else L)  # ngọc đỉnh phát sáng
    if f == 1:
        px(im, 8, 0, W); px(im, 5, 2, W); px(im, 11, 2, W)
    return outline(im)


def m_ward(f):
    im = new(16, 16)
    for (x, y, w) in ((8, 1, 0), (7, 2, 2), (6, 3, 4), (5, 4, 6), (5, 5, 6), (5, 6, 6), (6, 7, 4), (7, 8, 2), (8, 9, 0)):
        pass
    # tinh thể kéo dài
    for y in range(16):
        half = (7.0 - abs(y - 7.5)) * 0.62
        for x in range(16):
            if abs(x - 7.5) <= half:
                px(im, x, y, W if x < 8 else L)
    rect(im, 7, 4, 8, 11, W if f == 0 else L)
    px(im, 6, 5, W); px(im, 6, 6, W)
    rect(im, 4, 13, 11, 14, M)
    return outline(im)


def m_mini(f):
    im = new(16, 16)
    disc(im, 8, 9, 5, L)
    px(im, 4, 3, L); px(im, 5, 4, L); px(im, 11, 3, L); px(im, 10, 4, L)   # sừng
    px(im, 3, 2, W); px(im, 12, 2, W)
    rect(im, 5, 8, 6, 8, EYE); rect(im, 9, 8, 10, 8, EYE)               # mắt hằm hằm
    px(im, 5, 7, D); px(im, 10, 7, D)
    rect(im, 6, 11, 9, 11, D)
    px(im, 6, 12 if f else 11, W); px(im, 9, 12 if f else 11, W)         # răng
    return outline(im)


def m_blades(f):
    im = new(16, 16)
    # lưỡi kiếm dọc, mũi hướng lên
    for y in range(1, 12):
        w = 1 if y > 2 else 0
        rect(im, 7 - w, y, 8 + w, y, W if y < 8 else L)
    rect(im, 7, 1, 8, 2, W)
    rect(im, 5, 11, 10, 11, M)               # chắn
    rect(im, 7, 12, 8, 14, D)                # cán
    if f == 1:
        px(im, 6, 4, W); px(im, 9, 6, W)
    return outline(im)


MINIONS = {"spirit": m_spirit, "wisp": m_wisp, "guardian": m_guardian, "turret": m_turret,
           "totem": m_totem, "ward": m_ward, "mini": m_mini, "blades": m_blades}


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in range(4):
        save(forge(f), "forge_anim_f%d.png" % f)
    for f in range(6):
        save(portal(f, PORTAL_PAL), "portal_anim_f%d.png" % f)
        save(portal(f, COUNCIL_PAL), "council_portal_anim_f%d.png" % f)
    for f in range(2):
        save(tome(f), "tome_anim_f%d.png" % f)
        save(sigil(f), "sigil_anim_f%d.png" % f)
        for k, fn in MINIONS.items():
            save(fn(f), "minion_%s_f%d.png" % (k, f))
    print("ok")


if __name__ == "__main__":
    main()
