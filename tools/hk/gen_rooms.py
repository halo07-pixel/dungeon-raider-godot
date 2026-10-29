#!/usr/bin/env python3
"""Sinh hk/rooms/*.txt (lưới ký tự). Chạy: python3 tools/hk/gen_rooms.py
Quy ước kích thước: 1 ô = 32px. Nhảy cao tối đa ~3.9 ô (an toàn 3), nhảy xa khi chạy ~6 ô (an toàn 4),
dash thêm ~4 ô (khe cần dash: 9 ô), double jump thêm ~3 ô, bám tường cho phép leo giếng hẹp (rộng 5 ô).
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "hk", "rooms")


class R:
    def __init__(self, rid, w, h, floor, area, name, mp):
        self.id, self.w, self.h, self.F, self.area, self.name, self.mp = rid, w, h, floor, area, name, mp
        self.g = [["." for _ in range(w)] for _ in range(h)]
        self.fill(0, 0, w - 1, 0)
        self.fill(0, 0, 0, h - 1)
        self.fill(w - 1, 0, w - 1, h - 1)
        self.fill(0, floor, w - 1, h - 1)
        self.doors = {}
        self.extra = []

    def fill(self, x0, y0, x1, y1, ch="#"):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.g[y][x] = ch

    def put(self, x, y, ch):
        self.g[y][x] = ch

    def plat(self, x0, x1, y):
        self.fill(x0, y, x1, y, "=")

    def block(self, x0, y0, x1, y1):
        self.fill(x0, y0, x1, y1, "#")

    def hang(self, x, n):
        self.fill(x, 1, x, n, "#")

    def spikes(self, x0, x1, y=None):
        self.fill(x0, (self.h - 2) if y is None else y, x1, (self.h - 2) if y is None else y, "^")

    def pit(self, x0, x1, spikes=True):
        """Khoét hố trên sàn; gai ở dòng áp chót."""
        self.fill(x0, self.F, x1, self.h - 2, ".")
        if spikes:
            self.fill(x0, self.h - 2, x1, self.h - 2, "^")

    def door(self, ch, side, pos, to, to_door, needs=None):
        """side L/R: pos = dòng đầu (3 ô). side T/B: pos = cột đầu (3 ô), B khoét sàn bên trên."""
        if side == "L":
            self.fill(0, pos, 0, pos + 2, ch)
        elif side == "R":
            self.fill(self.w - 1, pos, self.w - 1, pos + 2, ch)
        elif side == "T":
            self.fill(pos, 0, pos + 2, 0, ch)
        elif side == "B":
            self.fill(pos, self.F, pos + 2, self.h - 2, ".")
            self.fill(pos, self.h - 1, pos + 2, self.h - 1, ch)
        self.doors[ch] = (to, to_door, needs)

    def ground_door(self, ch, side, to, to_door, needs=None):
        self.door(ch, side, self.F - 3, to, to_door, needs)

    def enemy(self, ch, x, y=None):
        self.put(x, (self.F - 1) if y is None else y, ch)

    def save(self):
        lines = ["area: " + self.area, "name: " + self.name, "map: %d,%d" % self.mp]
        for ch, (to, td, needs) in sorted(self.doors.items()):
            lines.append("door %s: %s %s%s" % (ch, to, td, (" needs=" + needs) if needs else ""))
        lines += self.extra
        lines.append("---")
        lines += ["".join(r) for r in self.g]
        with open(os.path.join(OUT, self.id + ".txt"), "w") as f:
            f.write("\n".join(lines) + "\n")


rooms = []


def new(rid, w, h, floor, area, name, mp):
    r = R(rid, w, h, floor, area, name, mp)
    rooms.append(r)
    return r


# ====================================================== GATE RUINS
r = new("gate_1", 40, 22, 18, "gate", "Broken Gate", (0, 0))
r.put(6, 17, "B"); r.put(9, 17, "@")
r.enemy("c", 24); r.enemy("c", 31)
r.plat(14, 18, 15); r.plat(28, 32, 15)
for x, n in [(12, 2), (13, 1), (27, 3), (28, 1), (20, 2)]:
    r.hang(x, n)
r.ground_door("1", "R", "gate_2", "1")
r.extra += ["hint: 4 14 Up / W at the bench: rest and save",
            "hint: 9 13 A / D or arrows: move     Z / Space: jump (hold = higher)",
            "hint: 15 11 X / J: nail (hold Up/Down to aim)",
            "hint: 29 13 Esc: pause, volume and controls"]

r = new("gate_2", 40, 22, 18, "gate", "Collapsed Walk", (6, 0))
r.pit(16, 19)
r.plat(9, 13, 15); r.plat(21, 25, 15); r.plat(17, 21, 12)
r.enemy("c", 10); r.put(23, 9, "f"); r.enemy("c", 30)
for x, n in [(8, 2), (24, 3), (30, 1)]:
    r.hang(x, n)
r.ground_door("1", "L", "gate_1", "1")
r.ground_door("2", "R", "gate_3", "1")
r.door("3", "B", 33, "gate_7", "1")

r = new("gate_3", 40, 22, 18, "gate", "Guard Hall", (12, 0))
r.block(17, 15, 22, 17)
r.put(19, 14, "s"); r.enemy("c", 8); r.enemy("g", 30); r.put(36, 17, "$")
r.plat(5, 9, 15); r.plat(27, 31, 15)
for x, n in [(7, 2), (15, 3), (25, 2), (34, 1)]:
    r.hang(x, n)
r.ground_door("1", "L", "gate_2", "2")
r.ground_door("2", "R", "gate_4", "1")

r = new("gate_4", 40, 22, 18, "gate", "Quiet Alcove", (18, 0))
r.put(14, 17, "B"); r.put(22, 17, "M")
for x in (8, 31):
    r.block(x, 1, x + 1, 4)
r.ground_door("1", "L", "gate_3", "2")
r.ground_door("2", "R", "gate_5", "1")

r = new("gate_5", 40, 22, 18, "gate", "Warden's Approach", (24, 0))
r.pit(10, 13); r.pit(25, 28)
r.put(14, 10, "f"); r.put(26, 9, "f"); r.enemy("g", 19); r.enemy("h", 32)
r.plat(6, 9, 15); r.plat(15, 18, 15)
r.put(37, 17, "B")
for x, n in [(17, 2), (30, 3)]:
    r.hang(x, n)
r.ground_door("1", "L", "gate_4", "2")
r.ground_door("2", "R", "gate_6", "1")

r = new("gate_6", 48, 24, 20, "gate", "Warden's Court", (30, 0))
r.put(32, 19, "X")
r.plat(6, 10, 17); r.plat(37, 41, 17)
for x in (14, 33):
    r.block(x, 1, x + 1, 3)
r.ground_door("1", "L", "gate_5", "2")
r.ground_door("2", "R", "gate_8", "1")
r.extra.append("boss: id=warden")

r = new("gate_7", 30, 30, 26, "gate", "Sunken Shaft", (6, 4))
r.put(5, 25, "C"); r.put(22, 25, "X")
r.extra += ["charm: id=long_reach needs=boss_hexer", "boss: id=hexer"]
r.door("1", "T", 14, "gate_2", "3")
for x0, x1, y in [(8, 12, 23), (17, 21, 20), (8, 12, 17), (17, 21, 14), (8, 12, 11), (17, 21, 8), (8, 12, 5), (17, 21, 3)]:
    r.plat(x0, x1, y)
r.put(19, 20, "f"); r.put(10, 16, "$")

r = new("gate_8", 40, 22, 18, "gate", "Shadow Shrine", (37, 0))
r.put(5, 17, "A"); r.put(12, 17, "B")
r.extra.append("altar: id=dash")
r.pit(16, 24)
for x, n in [(9, 2), (30, 3)]:
    r.hang(x, n)
r.ground_door("1", "L", "gate_6", "2")
r.ground_door("2", "R", "cat_1", "1")

# ====================================================== WEEPING CATACOMBS
r = new("cat_1", 40, 22, 18, "catacomb", "Catacomb Gate", (0, 10))
r.put(6, 17, "B")
r.enemy("c", 19); r.enemy("s", 28); r.put(21, 1, "d")
r.plat(12, 16, 15)
for x, n in [(10, 2), (24, 3), (33, 2)]:
    r.hang(x, n)
r.ground_door("1", "L", "gate_8", "2")
r.ground_door("2", "R", "cat_2", "1")

r = new("cat_2", 40, 22, 18, "catacomb", "Bone Walk", (6, 10))
r.pit(9, 12); r.pit(23, 26)
r.plat(5, 8, 15); r.plat(13, 17, 15)
r.enemy("h", 19); r.put(25, 10, "f"); r.enemy("s", 33); r.put(20, 1, "d")
for x, n in [(16, 3), (30, 2)]:
    r.hang(x, n)
r.ground_door("1", "L", "cat_1", "2")
r.ground_door("2", "R", "cat_3", "1")

r = new("cat_3", 40, 30, 26, "catacomb", "Weeping Hall", (12, 10))
r.door("2", "B", 30, "cat_4", "1")
r.plat(8, 12, 23); r.plat(16, 20, 20); r.plat(22, 26, 23)
r.enemy("c", 6); r.put(18, 14, "f"); r.enemy("s", 36); r.enemy("g", 14)
for x, n in [(12, 3), (26, 4)]:
    r.hang(x, n)
r.ground_door("1", "L", "cat_2", "2")

r = new("cat_4", 40, 22, 18, "catacomb", "Ashen Altar", (18, 10))
r.door("1", "T", 30, "cat_3", "2")
r.put(6, 17, "A"); r.put(11, 17, "B")
r.extra.append("altar: id=double_jump")
r.enemy("h", 20)
r.pit(14, 16)
for x0, x1, y in [(22, 25, 15), (27, 30, 12), (22, 25, 9), (27, 30, 6), (22, 25, 3)]:
    r.plat(x0, x1, y)
r.ground_door("2", "R", "cat_5", "1")

r = new("cat_5", 40, 26, 22, "catacomb", "Gallery of Wings", (24, 10))
r.ground_door("1", "L", "cat_4", "2")
r.ground_door("2", "R", "cat_7", "1")
# ban công trên cao (6 ô trên bục cuối) -> cần double jump
r.plat(10, 13, 19); r.plat(16, 19, 16); r.plat(12, 15, 13)
r.block(1, 7, 7, 8)
r.door("3", "L", 4, "cat_6", "1")
r.enemy("c", 27); r.put(22, 10, "f"); r.enemy("s", 33)

r = new("cat_6", 30, 18, 14, "catacomb", "Reliquary", (30, 10))
r.put(6, 13, "C"); r.put(14, 13, "$"); r.put(9, 13, "X")
r.extra += ["charm: id=heavy_blow needs=boss_brute", "boss: id=brute"]
r.door("1", "R", 11, "cat_5", "3")

r = new("cat_7", 40, 22, 18, "catacomb", "Last Rest", (24, 14))
r.enemy("h", 14); r.enemy("s", 28); r.put(22, 10, "f"); r.put(31, 1, "d")
r.pit(18, 21)
r.plat(8, 12, 15)
r.put(34, 17, "B")
r.ground_door("1", "L", "cat_5", "2")
r.ground_door("2", "R", "cat_8", "1")

r = new("cat_8", 48, 26, 22, "catacomb", "Hollow Court", (30, 14))
r.put(34, 21, "X")
r.plat(6, 10, 19); r.plat(37, 41, 19); r.plat(20, 28, 15)
r.ground_door("1", "L", "cat_7", "2")
r.ground_door("2", "R", "cat_9", "1")
r.extra.append("boss: id=wraith")

# giếng rộng 4 ô giữa hai vách đặc: chỉ leo được bằng bám tường
r = new("cat_9", 30, 44, 40, "catacomb", "Claw Shaft", (38, 14))
r.fill(0, 1, 13, 35); r.fill(18, 1, 29, 39)
r.put(5, 39, "A")
r.extra.append("altar: id=wall_cling needs=boss_wraith")
r.ground_door("1", "L", "cat_8", "2")
r.door("2", "T", 14, "vault_1", "1")
r.put(15, 28, "f"); r.put(16, 14, "f")

# ====================================================== ASHEN VAULTS
r = new("vault_1", 40, 22, 18, "vault", "Vault Door", (38, 21))
r.door("1", "B", 14, "cat_9", "2")
r.put(30, 17, "B")
r.put(22, 10, "f"); r.enemy("s", 26); r.enemy("c", 35)
for x, n in [(8, 3), (24, 2)]:
    r.hang(x, n)
r.ground_door("2", "R", "vault_2", "1")

r = new("vault_2", 40, 22, 18, "vault", "Ember Span", (44, 21))
r.pit(6, 33)
for x0, x1, y in [(8, 10, 16), (13, 15, 14), (18, 20, 16), (23, 25, 14), (28, 30, 16)]:
    r.plat(x0, x1, y)
r.put(14, 9, "f"); r.put(24, 8, "f"); r.enemy("s", 2); r.enemy("h", 36)
r.put(37, 17, "C")
r.extra.append("charm: id=fury")
r.ground_door("1", "L", "vault_1", "2")
r.ground_door("2", "R", "vault_3", "1")

r = new("vault_3", 30, 40, 36, "vault", "Chimney", (50, 21))
r.fill(0, 1, 17, 31); r.fill(22, 1, 29, 35)
r.ground_door("1", "L", "vault_2", "2")
r.door("2", "T", 19, "vault_4", "1")
r.put(19, 26, "f"); r.put(20, 14, "f")

r = new("vault_4", 40, 22, 18, "vault", "Chime Gallery", (50, 16))
r.door("1", "B", 14, "vault_3", "2")
r.plat(9, 12, 15); r.plat(14, 17, 12)
r.block(1, 9, 6, 10)
r.put(3, 8, "C")
r.extra.append("charm: id=quick_focus")
r.enemy("g", 24); r.enemy("h", 30); r.enemy("s", 35); r.put(20, 8, "f")
r.ground_door("2", "R", "vault_5", "1")

r = new("vault_5", 40, 22, 18, "vault", "Hearth", (56, 16))
r.put(12, 17, "B"); r.put(20, 17, "M")
for x in (6, 31):
    r.block(x, 1, x + 1, 4)
r.ground_door("1", "L", "vault_4", "2")
r.ground_door("2", "R", "vault_6", "1")
r.door("3", "B", 30, "arc_1", "1")   # lối xuống Drowned Archive (khu phụ, không bắt buộc)

r = new("vault_6", 40, 22, 18, "vault", "Last Gauntlet", (62, 16))
r.pit(8, 12); r.pit(26, 30)
r.plat(15, 18, 15); r.plat(20, 23, 12)
r.plat(15, 18, 9)
r.block(30, 4, 36, 4)
r.put(33, 3, "C")
r.extra.append("charm: id=iron_heart")
r.enemy("h", 15); r.put(22, 7, "f"); r.enemy("s", 33); r.enemy("g", 5); r.put(24, 1, "d")
r.ground_door("1", "L", "vault_5", "2")
r.ground_door("2", "R", "vault_7", "1")

r = new("vault_7", 48, 24, 20, "vault", "Lord's Throne", (68, 16))
r.put(32, 19, "X")
r.plat(6, 10, 17); r.plat(37, 41, 17)
for x in (14, 33):
    r.block(x, 1, x + 1, 3)
r.ground_door("1", "L", "vault_6", "2")
r.ground_door("2", "R", "sov_1", "1", "sovereign_open")   # lối tới boss bí mật: chỉ mở khi đủ 6 ký ức
r.extra += ["boss: id=lord", "hint: 36 14 A sealed way. Remember everything."]

# ====================================================== BOSS BÍ MẬT
r = new("sov_1", 56, 28, 24, "vault", "The Hollow Throne", (75, 16))
r.put(28, 23, "X")
r.plat(8, 13, 20); r.plat(42, 47, 20)
r.plat(19, 25, 16); r.plat(31, 37, 16)
for x in (17, 38):
    r.block(x, 1, x + 1, 4)
r.ground_door("1", "L", "vault_7", "2")
r.extra.append("boss: id=many_faced")

# ====================================================== DROWNED ARCHIVE (khu 4, nhánh phụ từ Hearth)
r = new("arc_1", 30, 30, 26, "archive", "Flooded Stair", (56, 21))
r.door("1", "T", 14, "vault_5", "3")
r.ground_door("2", "R", "arc_2", "1")
for x0, x1, y in [(8, 12, 23), (17, 21, 20), (8, 12, 17), (17, 21, 14), (8, 12, 11), (17, 21, 8), (8, 12, 5), (17, 21, 3)]:
    r.plat(x0, x1, y)
r.put(19, 19, "f"); r.enemy("c", 14); r.enemy("s", 25); r.put(10, 16, "$")

r = new("arc_2", 40, 22, 18, "archive", "Silt Corridor", (60, 21))
r.pit(12, 15); r.pit(24, 27)
r.plat(8, 11, 15); r.plat(16, 19, 15); r.plat(20, 23, 12)
r.enemy("g", 18); r.put(25, 9, "f"); r.enemy("s", 34); r.put(6, 1, "d")
for x, n in [(30, 3), (36, 2)]:
    r.hang(x, n)
r.ground_door("1", "L", "arc_1", "2")
r.ground_door("2", "R", "arc_3", "1")

r = new("arc_3", 40, 22, 18, "archive", "Sunken Library", (66, 21))
r.put(6, 17, "B"); r.put(14, 17, "M")
for x in (9, 28):
    r.block(x, 1, x + 1, 4)
r.enemy("h", 32)
r.ground_door("1", "L", "arc_2", "2")
r.ground_door("2", "R", "arc_4", "1")

r = new("arc_4", 40, 22, 18, "archive", "Pearl Walk", (72, 21))
r.pit(8, 12); r.pit(20, 31)
for x0, x1, y in [(14, 17, 15), (20, 22, 14), (24, 26, 12), (28, 30, 14)]:
    r.plat(x0, x1, y)
r.enemy("g", 5); r.put(24, 8, "f"); r.enemy("h", 36); r.put(15, 1, "d")
r.put(37, 17, "B")
r.ground_door("1", "L", "arc_3", "2")
r.ground_door("2", "R", "arc_5", "1")

r = new("arc_5", 48, 24, 20, "archive", "Tide Court", (78, 21))
r.put(6, 19, "C"); r.put(32, 19, "X")
r.plat(12, 16, 17); r.plat(37, 41, 17)
for x in (20, 28):
    r.block(x, 1, x + 1, 3)
r.ground_door("1", "L", "arc_4", "2")
r.extra += ["charm: id=swift_current needs=boss_colossus", "boss: id=colossus"]

def add_torches():
    """Lò lửa: cạnh mỗi bench (3 ô bên phải, nếu trống) và hai bên phòng boss. Chỉ trang trí."""
    for r in rooms:
        cols = []
        for y, row in enumerate(r.g):
            for x, ch in enumerate(row):
                if ch == "B":
                    cols.append(x + 3)
        if any(e.startswith("boss:") for e in r.extra):
            cols += [3, r.w - 4]
        for x in cols:
            if 1 < x < r.w - 2 and r.g[r.F - 1][x] == "." and r.g[r.F - 2][x] == "." and r.g[r.F][x] in "#=":
                r.extra.append("torch: %d %d" % (x, r.F - 1))


# Trang trí (chỉ vẽ, không va chạm): tên sprite, số ô cao, đứng sàn hay treo tường
DECO = {
    "column": (3, "floor"), "column_wall": (3, "floor"), "crate": (2, "floor"), "skull": (1, "floor"),
    "fountain_red": (3, "floor"), "fountain_blue": (3, "floor"), "tome": (1, "floor"), "sigil": (1, "floor"),
    "banner_red": (1, "wall"), "banner_blue": (1, "wall"), "banner_green": (1, "wall"), "banner_yellow": (1, "wall"),
    "hole": (1, "wall"), "goo": (2, "wall"),
}
DECO_THEME = {  # (đứng sàn, treo tường) theo khu
    "gate": (["column", "crate", "column_wall"], ["banner_red", "banner_blue", "hole"]),
    "catacomb": (["skull", "crate", "skull"], ["goo", "hole", "banner_red"]),
    "vault": (["fountain_red", "column", "fountain_red"], ["banner_yellow", "banner_yellow", "hole"]),
    "archive": (["fountain_blue", "tome", "tome"], ["banner_green", "banner_blue", "banner_green"]),
}
DECO_BARE = 0.25   # xác suất một phòng thường không có trang trí


def add_decor():
    """Rải trang trí: ô phủ phải trống và hai cột bên cạnh cũng trống (không đè quái/bench/bàn thờ/cửa/lò lửa)."""
    import random
    for r in rooms:
        rng = random.Random(r.id)
        boss = any(e.startswith("boss:") for e in r.extra)
        taken = {int(e.split()[1]) for e in r.extra if e.startswith("torch:")}
        used = []

        def clear(x, y0, y1):
            return all(r.g[y][xx] == "." for y in range(y0, y1 + 1) for xx in (x - 1, x, x + 1))

        def place(kind, x, row):
            h, mode = DECO[kind]
            if not (4 <= x <= r.w - 5) or any(abs(x - u) < 3 for u in used + list(taken)):
                return False
            y0 = row - h + 1
            if y0 < 2 or not clear(x, y0, row):
                return False
            if mode == "floor" and r.g[r.F][x] not in "#=":
                return False
            used.append(x)
            r.extra.append("deco: %s %d %d" % (kind, x, row))
            return True

        floor, wall = DECO_THEME[r.area]
        n = 0
        if boss:   # cặp cột + cờ hai bên phòng boss
            fl = "column_wall" if r.area != "archive" else "column"
            for x in (7, r.w - 8):
                n += place(fl, x, r.F - 1)
            for x in (11, r.w - 12):
                n += place(wall[0], x, 4)
            if r.id == "sov_1":
                n += place("sigil", r.w // 2, r.F - 1)
            continue
        if rng.random() < DECO_BARE:   # một số phòng để trống cho thưa mắt
            continue
        # mỗi phòng: MỘT loại đứng sàn gom thành cụm quanh một điểm + MỘT loại treo tường (ít, không rải đều)
        fk = rng.choice(sorted(set(floor)))
        wk = rng.choice(sorted(set(wall)))
        anchor = rng.randint(8, max(8, r.w - 9))
        near = sorted(range(5, r.w - 5), key=lambda x: abs(x - anchor) + rng.random() * 3)
        cap_f = 1 if fk.startswith("fountain") else 3
        got = 0
        for x in near:
            if got >= cap_f or abs(x - anchor) > 10:
                break
            if place(fk, x, r.F - 1):
                got += 1
        xs = list(range(5, r.w - 5))
        rng.shuffle(xs)
        cap_w = 1 if wk in ("hole", "goo") else 2
        got = 0
        for x in xs:
            if got >= cap_w:
                break
            if place(wk, x, rng.randint(3, max(3, r.F - 6))):
                got += 1

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".txt"):
            os.remove(os.path.join(OUT, f))
    add_torches()
    add_decor()
    for r in rooms:
        r.save()
    print("wrote", len(rooms), "rooms")
