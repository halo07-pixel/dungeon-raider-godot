#!/usr/bin/env python3
"""Kiểm tra khả năng đi tới của 24 phòng HK bằng mô phỏng vật lý của người chơi (hk/player.gd).

Chạy: python3 tools/hk/validate_rooms.py [--quick] [--verbose]
Thoát 1 nếu có lỗi tiến trình (kỹ năng không lấy được theo thứ tự, phòng/vật phẩm không tới được, bẫy không thoát).

Cách làm: mỗi "bục đứng" (đoạn sàn liên tục) là một nút. Từ nút, thử hàng nghìn kịch bản bấm phím (chạy trái/phải, nhả nhảy
sớm/muộn, đổi hướng giữa không trung, dash, nhảy đôi, trèo tường), mô phỏng từng khung 1/60s với đúng hằng số của player.gd
(hộp 26x52, gravity 2400, nhảy -780, chạy 300, dash 760 trong 0.18s, nhảy tường 320/-741...) và ghi lại nơi tiếp đất / cửa thoát.
Không mô phỏng: pogo, spell, nhảy xuyên bục một chiều bằng Down, quái/boss.
Nới lỏng có chủ đích (shortcut): bước mẫu 1/60s, vị trí xuất phát mỗi 32px + hai mép, thời điểm bấm lấy mẫu rời rạc —
nên "không tới được" cần kiểm tay trước khi sửa phòng, còn "tới được" là chắc chắn (kịch bản có thật).
"""
import itertools
import os
import sys
import time

import numpy as np

ROOMS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "hk", "rooms")
TILE = 32
DT = 1.0 / 60.0
HALF_W, HALF_H = 13.0, 26.0
GRAVITY, MAX_FALL = 2400.0, 900.0
RUN, JUMP_V, JUMP_CUT = 300.0, -780.0, 0.4
DASH_V, DASH_T = 760.0, 0.18
COYOTE, WALL_SLIDE, WALL_LOCK, WALL_COYOTE = 0.1, 90.0, 0.18, 0.1
WALL_JUMP_VX, WALL_JUMP_VY = 320.0, JUMP_V * 0.95
DJ_V = JUMP_V * 0.92
MAX_STEPS = 300
EPS = 1e-3
INF = 1e9

TIERS = [("none", []), ("dash", ["dash"]), ("double_jump", ["dash", "double_jump"]),
         ("wall_cling", ["dash", "double_jump", "wall_cling"])]


# ---------------------------------------------------------------- đọc phòng
class Room:
    def __init__(self, rid, text):
        self.id = rid
        self.doors = {}
        self.altar = self.charm = self.boss = None
        head, grid = text.split("\n---\n", 1)
        for line in head.split("\n"):
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            k, v = k.strip(), v.strip()
            if k.startswith("door "):
                to, td = v.split()
                self.doors[k[5:].strip()] = (to, td)
            elif k in ("altar", "charm", "boss"):
                setattr(self, k, dict(kv.split("=") for kv in v.split()))
        lines = [l for l in grid.split("\n") if l != ""]
        self.cols = max(len(l) for l in lines)
        self.rows = len(lines)
        self.cells = [l.ljust(self.cols, "#") for l in lines]
        self.S = np.ones((self.rows + 2, self.cols + 2), bool)   # viền ngoài = đặc
        self.O = np.zeros_like(self.S)
        self.H = np.zeros_like(self.S)
        self.door_rects = {}
        self.items = []    # (kind, rect(x0,y0,x1,y1))
        self.spawn = None
        self.bench = None
        for y, row in enumerate(self.cells):
            for x, ch in enumerate(row):
                self.S[y + 1, x + 1] = ch in "#G"
                self.O[y + 1, x + 1] = ch == "="
                self.H[y + 1, x + 1] = ch == "^"
                px, py = x * TILE, y * TILE
                if ch.isdigit() and ch != "0":
                    r = self.door_rects.get(ch)
                    nr = (px, py, px + TILE, py + TILE)
                    self.door_rects[ch] = nr if r is None else (min(r[0], nr[0]), min(r[1], nr[1]), max(r[2], nr[2]), max(r[3], nr[3]))
                elif ch == "B":
                    self.items.append(("bench", (px - 20, py - 32, px + TILE + 20, py + TILE)))
                    self.bench = (px + TILE / 2, py + TILE - 27)
                elif ch == "M":
                    self.items.append(("merchant", (px - 24, py - 64, px + TILE + 24, py + TILE)))
                elif ch == "A":
                    self.items.append(("altar:" + (self.altar or {}).get("id", "?"), (px - 16, py - 48, px + TILE + 16, py + TILE)))
                elif ch == "C":
                    self.items.append(("charm:" + (self.charm or {}).get("id", "?"), (px - 16, py - 48, px + TILE + 16, py + TILE)))
                elif ch == "X":
                    self.items.append(("boss:" + (self.boss or {}).get("id", "?"), (px, py - 64, px + TILE, py + TILE)))
                elif ch == "@":
                    self.spawn = (px + TILE / 2, py + TILE - 27)
        for ch, r in self.door_rects.items():
            self.items.append(("door:" + ch, r))

    def cell(self, arr, x, y):  # x,y: ô (có thể ngoài lưới -> viền)
        return arr[np.clip(y + 1, 0, self.rows + 1), np.clip(x + 1, 0, self.cols + 1)]

    def spawn_for_door(self, d):
        r = self.door_rects[d]
        cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
        W, Hh = self.cols * TILE, self.rows * TILE
        dl, dr, dt, db = cx, W - cx, cy, Hh - cy
        m = min(dl, dr, dt, db)
        if m in (dl, dr):
            return (r[2] + 22.0 if m == dl else r[0] - 22.0, r[3] - 27.0)
        if m == dt:
            return (cx, r[3] + 40.0)
        col, row = int(r[0] / TILE) - 1, int(r[1] / TILE)
        while row > 0 and self.cells[row][col] == "#":
            row -= 1
        return (col * TILE + TILE / 2, (row + 1) * TILE - 27.0)

    def default_spawn(self):
        if self.spawn:
            return self.spawn
        k = next(iter(self.doors))
        return self.spawn_for_door(k)


# ---------------------------------------------------------------- va chạm (vector hoá)
def tiles_of(x, y):
    l, r, t, b = x - HALF_W, x + HALF_W, y - HALF_H, y + HALF_H
    c0 = np.floor(l / TILE).astype(int)
    c1 = np.floor((r - EPS) / TILE).astype(int)
    r0 = np.floor(t / TILE).astype(int)
    r1 = np.floor((b - EPS) / TILE).astype(int)
    return c0, c1, r0, r1


def hits_solid(room, x, y):
    c0, c1, r0, r1 = tiles_of(x, y)
    hit = np.zeros(x.shape, bool)
    for c in (c0, c1):
        for k in range(3):
            rr = r0 + k
            hit |= room.cell(room.S, c, rr) & (rr <= r1)
    return hit


def hits_hazard(room, x, y):
    c0, c1, r0, r1 = tiles_of(x, y)
    hit = np.zeros(x.shape, bool)
    l, r, t, b = x - HALF_W, x + HALF_W, y - HALF_H, y + HALF_H
    for c in (c0, c1):
        for k in range(3):
            rr = r0 + k
            h = room.cell(room.H, c, rr) & (rr <= r1)
            hx0, hx1, hy0, hy1 = c * TILE + 6, c * TILE + 26, rr * TILE + 16, rr * TILE + 30   # Rect(+4,+14,24,18) thu 2px
            hit |= h & (l < hx1) & (r > hx0) & (t < hy1) & (b > hy0)
    return hit


def in_rect(x, y, rc):
    return (x - HALF_W < rc[2]) & (x + HALF_W > rc[0]) & (y - HALF_H < rc[3]) & (y + HALF_H > rc[1])


# ---------------------------------------------------------------- bục đứng
def build_platforms(room):
    """[(feet_y, xmin, xmax)] — mọi đoạn x mà hộp đứng được trên sàn (đặc hoặc một chiều), không chạm tường/gai."""
    plats = []
    xs = np.arange(HALF_W, room.cols * TILE - HALF_W + 0.1, 2.0)
    for fr in range(2, room.rows + 1):
        F = fr * TILE
        y = np.full_like(xs, F - HALF_H - EPS)
        c0 = np.floor((xs - HALF_W) / TILE).astype(int)
        c1 = np.floor((xs + HALF_W - EPS) / TILE).astype(int)
        sup = np.zeros(xs.shape, bool)
        for c in (c0, c1):
            sup |= room.cell(room.S, c, fr) | room.cell(room.O, c, fr)
        ok = sup & ~hits_solid(room, xs, y) & ~hits_hazard(room, xs, y)
        i = 0
        while i < len(xs):
            if ok[i]:
                j = i
                while j + 1 < len(xs) and ok[j + 1]:
                    j += 1
                plats.append((float(F), float(xs[i]), float(xs[j])))
                i = j + 1
            else:
                i += 1
    return plats


def platform_of(plats, x, feet):
    best, bd = None, 1e9
    for i, (F, x0, x1) in enumerate(plats):
        if abs(F - feet) > 1.5:
            continue
        d = 0.0 if x0 - 2 <= x <= x1 + 2 else min(abs(x - x0), abs(x - x1))
        if d < bd:
            best, bd = i, d
    return best if bd <= 6 else None


# ---------------------------------------------------------------- bộ kịch bản
def make_combos(feat, only_new=None):
    """Mảng tham số các kịch bản. feat: tập kỹ năng. only_new: chỉ giữ kịch bản dùng kỹ năng này."""
    dirs = (-1, 0, 1)
    lean = len(feat) >= 2   # shortcut: nhiều kỹ năng cùng lúc thì lấy mẫu thưa hơn, tránh bùng nổ tổ hợp
    holds = (-1.0, 0.1, INF) if lean else (-1.0, 0.08, 0.16, INF)         # -1 = không nhảy
    delays = (0.0,) if lean else (0.0, 0.1)
    steers = [(INF, 0)] + ([(0.3, 0), (0.3, 1)] if lean else [(ts, s) for ts in (0.2, 0.4, 0.6) for s in (0, 1)])   # s: 0 = dừng, 1 = quay đầu
    tds = (0.12, 0.4) if lean else (0.0, 0.12, 0.3, 0.5)
    dashes = [(INF, 0)] + ([(td, dd) for td in tds for dd in (-1, 1)] if "dash" in feat else [])
    djs = [INF] + ([0.15, 0.4] if "double_jump" in feat else [])
    walls = [-1.0] + ([0.0, 0.2] if "wall_cling" in feat else [])
    rows = []
    for d1, hj, (ts, s), (td, dd), tdj, tw in itertools.product(dirs, holds, steers, dashes, djs, walls):
        if hj < 0 and (tdj < INF or tw >= 0):
            if not (tw >= 0 and d1 != 0):
                continue
        if only_new == "dash" and td >= INF:
            continue
        if only_new == "double_jump" and tdj >= INF:
            continue
        if only_new == "wall_cling" and tw < 0:
            continue
        if hj < 0 and d1 == 0:
            continue
        for tj in (delays if hj >= 0 else (0.0,)):
            rows.append((d1, hj, tj, ts, s, td, dd, tdj, tw))
    return np.array(rows, float)


# ---------------------------------------------------------------- mô phỏng
def simulate(room, feat, starts, combos):
    """starts: [(x, feet_y)] -> mỗi kịch bản (start x combo). Trả (status, x, y, door) mỗi lane.
    status: 1 = tiếp đất, 2 = ra cửa, 3 = chết (gai), 4 = hết giờ."""
    ns, nc = len(starts), len(combos)
    n = ns * nc
    sx = np.repeat(np.array([s[0] for s in starts], float), nc)
    sy = np.repeat(np.array([s[1] - HALF_H - EPS for s in starts], float), nc)
    P = np.tile(combos, (ns, 1))
    d1, hj, tj, ts, steer, td, dd, tdj, tw = [P[:, i] for i in range(9)]
    x, y = sx.copy(), sy.copy()
    vx = np.zeros(n)
    vy = np.zeros(n)
    status = np.zeros(n, int)
    door = np.full(n, -1)
    ground = np.ones(n, bool)
    last_ground = np.zeros(n)
    air_ever = np.zeros(n, bool)
    can_dash = np.ones(n, bool)
    air_jumps = np.ones(n, int)
    dash_t = np.zeros(n)
    dash_dir = np.zeros(n)
    dashed = np.zeros(n, bool)
    wall_lock = np.zeros(n)
    wall_coyote = np.full(n, -1.0)
    wall_dir = np.zeros(n)
    wall_contact = np.zeros(n, bool)
    wall_dir_c = np.zeros(n)
    wall_t0 = np.full(n, INF)
    wdir = np.zeros(n)           # hướng ép bởi chính sách bám tường (0 = theo kịch bản)
    jumped = np.zeros(n, bool)
    released = np.zeros(n, bool)
    djd = np.zeros(n, bool)
    has_wall, has_dj, has_dash = "wall_cling" in feat, "double_jump" in feat, "dash" in feat
    door_ids = sorted(room.door_rects)
    # lane đã chồng cửa ngay từ đầu
    for k, ch in enumerate(door_ids):
        m = (status == 0) & in_rect(x, y, room.door_rects[ch])
        status[m], door[m] = 2, k
    idx_all = np.arange(n)
    for step in range(MAX_STEPS):
        act = idx_all[status == 0]
        if act.size == 0:
            break
        t = step * DT
        a = act
        # ---- đầu vào theo kịch bản
        d = np.where(t < ts[a], d1[a], np.where(steer[a] == 0, 0.0, -d1[a]))
        d = np.where(wdir[a] != 0, wdir[a], d)
        wl = wall_lock[a] - DT
        wall_lock[a] = np.maximum(wl, 0.0)
        wall_coyote[a] -= DT
        g = ground[a]
        last_ground[a] = np.where(g, t, last_ground[a])
        can_dash[a] |= g
        air_jumps[a] = np.where(g, 1, air_jumps[a])
        facing = np.where(d != 0, d, dash_dir[a] if False else np.where(d1[a] != 0, d1[a], 1.0))
        # ---- dash
        start_dash = has_dash & (t >= td[a]) & ~dashed[a] & can_dash[a] & (dash_t[a] <= 0)
        dash_t[a] = np.where(start_dash, DASH_T, dash_t[a])
        dash_dir[a] = np.where(start_dash, dd[a], dash_dir[a])
        can_dash[a] &= ~start_dash
        dashed[a] |= start_dash
        dashing = dash_t[a] > 0
        # ---- vận tốc ngang / trọng lực
        free_x = wall_lock[a] <= 0
        vx[a] = np.where(free_x, d * RUN, vx[a])
        vy[a] = np.where(dashing, 0.0, np.minimum(vy[a] + GRAVITY * DT, MAX_FALL))
        vx[a] = np.where(dashing, dash_dir[a] * DASH_V, vx[a])
        # ---- bám tường
        if has_wall:
            on_wall = wall_contact[a] & ~ground[a] & ~dashing
            wall_dir[a] = np.where(on_wall, wall_dir_c[a], wall_dir[a])
            wall_coyote[a] = np.where(on_wall, WALL_COYOTE, wall_coyote[a])
            can_dash[a] |= on_wall
            air_jumps[a] = np.where(on_wall, 1, air_jumps[a])
            first = on_wall & (wall_t0[a] >= INF)
            wall_t0[a] = np.where(first, t, wall_t0[a])
            wdir[a] = np.where(on_wall & (tw[a] >= 0), wall_dir[a], wdir[a])
            cling = on_wall & (d == wall_dir[a]) & (vy[a] > 0)
            vy[a] = np.where(cling, np.minimum(vy[a], WALL_SLIDE), vy[a])
        # ---- nhảy mặt đất / coyote
        press = (hj[a] >= 0) & ~jumped[a] & (t >= tj[a])
        can_gj = (t - last_ground[a] <= COYOTE + 1e-9)
        gj = press & can_gj & ~dashing
        vy[a] = np.where(gj, JUMP_V, vy[a])
        jumped[a] |= gj
        # ---- nhảy tường
        if has_wall:
            want = (tw[a] >= 0) & (wall_coyote[a] > 0) & (t - wall_t0[a] >= tw[a] - 1e-9) & ~gj & ~dashing
            vy[a] = np.where(want, WALL_JUMP_VY, vy[a])
            vx[a] = np.where(want, -wall_dir[a] * WALL_JUMP_VX, vx[a])
            wall_lock[a] = np.where(want, WALL_LOCK, wall_lock[a])
            wdir[a] = np.where(want, -wall_dir[a], wdir[a])
            wall_coyote[a] = np.where(want, 0.0, wall_coyote[a])
            wall_t0[a] = np.where(want, INF, wall_t0[a])
            released[a] = np.where(want, False, released[a])
        # ---- nhảy đôi
        if has_dj:
            dj = (t >= tdj[a]) & ~djd[a] & ~can_gj & (air_jumps[a] > 0) & ~dashing
            vy[a] = np.where(dj, DJ_V, vy[a])
            air_jumps[a] = np.where(dj, air_jumps[a] - 1, air_jumps[a])
            djd[a] |= dj
        # ---- nhả nhảy sớm
        rel = jumped[a] & ~released[a] & (t >= tj[a] + hj[a]) & (vy[a] < 0)
        vy[a] = np.where(rel, vy[a] * JUMP_CUT, vy[a])
        released[a] |= rel
        dash_t[a] = np.where(dashing, dash_t[a] - DT, dash_t[a])
        # ---- di chuyển trục X
        ox = x[a]
        nx = ox + vx[a] * DT
        hit = hits_solid(room, nx, y[a])
        c0, c1, _, _ = tiles_of(nx, y[a])
        snap = np.where(vx[a] > 0, c1 * TILE - HALF_W - EPS, (c0 + 1) * TILE + HALF_W + EPS)
        nx = np.where(hit, snap, nx)
        x[a] = nx
        wall_contact[a] = hit & (vx[a] != 0)
        wall_dir_c[a] = np.where(vx[a] > 0, 1.0, -1.0)
        # ---- di chuyển trục Y
        oy = y[a]
        ny = oy + vy[a] * DT
        hit = hits_solid(room, x[a], ny)
        _, _, r0, r1 = tiles_of(x[a], ny)
        landed = hit & (vy[a] > 0)
        bump = hit & (vy[a] < 0)
        ny = np.where(landed, r1 * TILE - HALF_H - EPS, np.where(bump, (r0 + 1) * TILE + HALF_H + EPS, ny))
        # bục một chiều: chỉ khi đang rơi và đáy cũ nằm trên mặt bục
        obot = oy + HALF_H
        nbot = ny + HALF_H
        sr = np.floor(nbot / TILE).astype(int)
        surf = sr * TILE
        cc0 = np.floor((x[a] - HALF_W) / TILE).astype(int)
        cc1 = np.floor((x[a] + HALF_W - EPS) / TILE).astype(int)
        ow = (room.cell(room.O, cc0, sr) | room.cell(room.O, cc1, sr)) & (vy[a] > 0) & ~landed & (obot <= surf + 0.01) & (nbot >= surf)
        ny = np.where(ow, surf - HALF_H - EPS, ny)
        landed |= ow
        vy[a] = np.where(landed | bump, 0.0, vy[a])
        y[a] = ny
        ground[a] = landed
        air_ever[a] |= ~landed
        # ---- kết quả
        dead = hits_hazard(room, x[a], y[a])
        st = np.zeros(a.size, int)
        st[dead] = 3
        for k, ch in enumerate(door_ids):
            m = (st == 0) & in_rect(x[a], y[a], room.door_rects[ch])
            st[m] = 2
            door[a[m]] = k
        st[(st == 0) & landed & air_ever[a] & (t > 0.05)] = 1
        status[a] = np.where(st > 0, st, status[a])
    status[status == 0] = 4
    return status, x, y + HALF_H + EPS, door, door_ids


# ---------------------------------------------------------------- đồ thị
class Graph:
    def __init__(self, rooms, quick=False):
        self.rooms = rooms
        self.plats = {rid: build_platforms(r) for rid, r in rooms.items()}
        self.edges = {}     # (rid, i) -> set(node | ("door", rid, ch))
        self.sim_done = {}  # (rid, i) -> set(feat đã chạy)
        self.stride = 48.0 if quick else TILE

    def starts(self, rid, i):
        F, x0, x1 = self.plats[rid][i]
        xs = set(np.arange(x0, x1, self.stride).tolist()) | {x0, x1, (x0 + x1) / 2}
        return [(float(x), F) for x in sorted(xs)]

    def expand(self, rid, i, tier_feats, only_new):
        room = self.rooms[rid]
        combos = make_combos(tier_feats, only_new)
        if len(combos) == 0:
            return
        starts = self.starts(rid, i)
        # chia lô để giới hạn bộ nhớ
        out = self.edges.setdefault((rid, i), set())
        per = max(1, 120000 // len(combos))
        for k in range(0, len(starts), per):
            chunk = starts[k:k + per]
            status, lx, lfeet, door, door_ids = simulate(room, tier_feats, chunk, combos)
            for s, xx, ff, dr in zip(status, lx, lfeet, door):
                if s == 1:
                    j = platform_of(self.plats[rid], xx, ff)
                    if j is not None and j != i:
                        out.add((rid, j))
                elif s == 2:
                    out.add(("door", rid, door_ids[dr]))

    def arrival(self, rid, door_ch):
        room = self.rooms[rid]
        x, y = room.spawn_for_door(door_ch)
        return self.settle(rid, x, y)

    def settle(self, rid, x, y):
        room = self.rooms[rid]
        xs, ys = np.array([x]), np.array([y])
        for _ in range(MAX_STEPS):
            ny = ys + 900 * DT
            if hits_solid(room, xs, ny)[0]:
                break
            ys = ny
        # hạ từng px cho chính xác
        while not hits_solid(room, xs, ys + 1.0)[0] and ys[0] < room.rows * TILE:
            ys = ys + 1.0
        return platform_of(self.plats[rid], float(xs[0]), float(ys[0] + HALF_H))

    def explore(self):
        """Trả {tier_name: {node: tier_first_reached}} và cạnh cuối."""
        start_room = "gate_1"
        s = self.settle(start_room, *self.rooms[start_room].default_spawn())
        reached = {}
        order = []
        for tname, feats in TIERS:
            prev = TIERS[TIERS.index((tname, feats)) - 1][1] if tname != "none" else None
            frontier = [(start_room, s)] if s is not None and tname == "none" else []
            stack = list(reached.keys()) + frontier
            if tname == "none":
                reached[(start_room, s)] = tname
            seen_now = set()
            while stack:
                node = stack.pop()
                if node in seen_now:
                    continue
                seen_now.add(node)
                have = self.sim_done.get(node, set())
                if tname not in have:
                    full = not have
                    self.expand(node[0], node[1], feats, None if full else tname)
                    self.sim_done[node] = have | {tname}
                for tgt in self.edges.get(node, ()):
                    if tgt[0] == "door":
                        _, rid, ch = tgt
                        to, td = self.rooms[rid].doors[ch]
                        if to not in self.rooms or td not in self.rooms[to].door_rects:
                            continue
                        j = self.arrival(to, td)
                        if j is None:
                            continue
                        tgt = (to, j)
                    if tgt not in reached:
                        reached[tgt] = tname
                        order.append(tgt)
                    stack.append(tgt)
        return reached

    def resolved_edges(self):
        out = {}
        for node, tg in self.edges.items():
            lst = set()
            for t in tg:
                if t[0] == "door":
                    _, rid, ch = t
                    to, td = self.rooms[rid].doors[ch]
                    j = self.arrival(to, td) if to in self.rooms and td in self.rooms[to].door_rects else None
                    if j is not None:
                        lst.add((to, j))
                else:
                    lst.add(t)
            out[node] = lst
        return out


def load_rooms():
    rooms = {}
    for fn in sorted(os.listdir(ROOMS_DIR)):
        if fn.endswith(".txt"):
            rooms[fn[:-4]] = Room(fn[:-4], open(os.path.join(ROOMS_DIR, fn), encoding="utf-8").read())
    return rooms


def main():
    quick = "--quick" in sys.argv
    verbose = "--verbose" in sys.argv
    t0 = time.time()
    rooms = load_rooms()
    g = Graph(rooms, quick)
    reached = g.explore()
    tier_rank = {n: i for i, (n, _) in enumerate(TIERS)}
    fails = []

    def first_tier_of_room(rid):
        ts = [tier_rank[t] for (r, _), t in reached.items() if r == rid]
        return min(ts) if ts else None

    print("== Phòng: tầng kỹ năng sớm nhất tới được ==")
    for rid in rooms:
        ft = first_tier_of_room(rid)
        print("  %-9s %s" % (rid, TIERS[ft][0] if ft is not None else "KHÔNG TỚI ĐƯỢC"))
        if ft is None:
            fails.append("phòng %s không tới được" % rid)

    # vật phẩm / cửa / bench / boss trong mỗi phòng
    print("== Vật phẩm ==")
    item_tier = {}
    for rid, room in rooms.items():
        for kind, rc in room.items:
            best = None
            for (r2, i), t in reached.items():
                if r2 != rid:
                    continue
                F, x0, x1 = g.plats[rid][i]
                xs = np.array([x0, x1, (x0 + x1) / 2] + list(np.arange(x0, x1, 8.0)))
                ys = np.full_like(xs, F - HALF_H)
                if in_rect(xs, ys, rc).any():
                    best = tier_rank[t] if best is None else min(best, tier_rank[t])
            # cửa trên trần / cửa dưới: cũng tính nếu có lane thoát qua cửa đó
            if best is None and kind.startswith("door:"):
                ch = kind[5:]
                for (r2, i), t in reached.items():
                    if r2 == rid and ("door", rid, ch) in g.edges.get((r2, i), ()):
                        best = tier_rank[t] if best is None else min(best, tier_rank[t])
            item_tier[(rid, kind)] = best
            if best is None:
                fails.append("%s: %s không tới được" % (rid, kind))
            if verbose or not kind.startswith("door:"):
                print("  %-9s %-18s %s" % (rid, kind, TIERS[best][0] if best is not None else "KHÔNG TỚI ĐƯỢC"))

    # thứ tự tiến trình: mỗi kỹ năng phải lấy được bằng các kỹ năng trước
    need = {"altar:dash": 0, "altar:double_jump": 1, "altar:wall_cling": 2}
    for (rid, kind), tier in item_tier.items():
        if kind in need and tier is not None and tier > need[kind]:
            fails.append("%s %s cần tầng '%s' (chỉ được phép '%s')" % (rid, kind, TIERS[tier][0], TIERS[need[kind]][0]))
    # boss cuối chỉ cần kỹ năng đã có
    # ---- bẫy: nút không quay lại được điểm xuất phát (với đủ kỹ năng)
    edges = g.resolved_edges()
    rev = {}
    for a, bs in edges.items():
        for b in bs:
            rev.setdefault(b, set()).add(a)
    start = next(n for n, t in reached.items() if t == "none" and n[0] == "gate_1")
    back = {start}
    stack = [start]
    while stack:
        n = stack.pop()
        for p in rev.get(n, ()):
            if p not in back:
                back.add(p)
                stack.append(p)
    trapped = [n for n in reached if n not in back]
    print("== Bẫy (không thoát ra được dù đủ kỹ năng): %d nút ==" % len(trapped))
    for rid, i in trapped:
        F, x0, x1 = g.plats[rid][i]
        print("  %s bục %d (y=%d, x %d..%d)" % (rid, i, F, x0, x1))
        fails.append("bẫy: %s bục %d (y=%d, x %d..%d) vào được nhưng không ra được" % (rid, i, F, x0, x1))
    print("Thời gian: %.1fs, %d nút tới được" % (time.time() - t0, len(reached)))
    if fails:
        print("\nLỖI (%d):" % len(fails))
        for f in fails:
            print("  - " + f)
        sys.exit(1)
    print("\nOK: mọi phòng, vật phẩm, kỹ năng tới được theo đúng thứ tự.")


if __name__ == "__main__":
    main()
