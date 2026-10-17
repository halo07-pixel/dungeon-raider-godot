"""Mô phỏng đơn giản trận Dungeon Lord để huấn luyện chính sách của RLController (offline).

Đây là bản GẦN ĐÚNG của boss.gd: cùng đấu trường, cùng bảng cooldown/telegraph theo pha, cùng
pool đòn, cùng công thức chọn đòn có thiên lệch (exp(pick*dấu*BIAS)), cùng vector quan sát
16 + 2 đặc trưng và cùng chính sách tuyến tính tanh(W·f+b)+nhiễu. Hình học các đòn được đơn giản
hoá (xem từng hàm atk_*). Người chơi là các "bot" kiểu khác nhau, không phải người thật.

Chỉ cần numpy. Không dùng chung code với game; hằng số lấy tay từ scripts/boss.gd (xem README.md).
"""
import math
import random

import numpy as np

# ---------------------------------------------------------------- hằng số (khớp boss.gd / player.gd)
ARENA_W, ARENA_H = 704.0, 448.0          # 24x16 ô trừ tường (xấp xỉ)
DT = 0.05
HORIZON = 60.0                           # giây mỗi episode (4 pha x 15s)
PHASE_LEN = 15.0
COOLDOWN = [1.6, 1.15, 0.7, 0.5]
SPEED_MULT = [0.85, 0.7, 0.5, 0.4]
BODY_RADIUS = 34.0 * 1.25
PLAYER_R = 12.0
PLAYER_SPEED = 230.0
ROLL_SPEED, ROLL_TIME, ROLL_CD = 560.0, 0.25, 0.8
HURT_INVULN = 0.4
SHIELD_MAX, SHIELD_DELAY, SHIELD_RATE = 56.0, 2.5, 10.0
HP_MAX = 160.0
RL_INTERVAL = 0.25
LORD_RING_COUNT, LORD_RING_VOLLEYS, LORD_RING_GAP = 14, [3, 4, 5, 5], 0.3
AOE = 1.35
OBS_SIZE, ACTION_SIZE = 16, 4
FEAT = OBS_SIZE + 2
NOISE_STD = 0.12
MOVE_X, MOVE_Y, ATTACK, PICK = 0, 1, 2, 3
POOLS = {
    1: ["charge", "ring", "ring"],
    2: ["necro_bolt", "necro_bolt", "necro_curse", "necro_summon", "charge"],
    3: ["frost_breath", "spike_field", "frost_charge", "ice_prison", "necro_bolt"],
    4: ["judgement", "lord_summon_all", "ring", "necro_bolt", "ice_prison"],
}
AREA = {"ring", "slam", "blizzard", "spike_field", "ice_prison", "judgement", "frost_breath", "necro_curse"}
DIRECT = {"charge", "necro_bolt", "frost_charge"}


# ---------------------------------------------------------------- chính sách (khớp rl_controller.gd)
def prior_policy():
    """Bộ trọng số tiên nghiệm viết tay — bản sao của RLController.reset_policy()."""
    w = np.zeros((ACTION_SIZE, FEAT))
    b = np.zeros(ACTION_SIZE)
    S, P, ST, WL = 1.5, 0.5, 0.4, 0.6
    w[MOVE_X][0], w[MOVE_X][1], w[MOVE_X][10], w[MOVE_X][12], w[MOVE_X][14] = S, -ST, -P, WL, -WL
    w[MOVE_Y][1], w[MOVE_Y][0], w[MOVE_Y][11], w[MOVE_Y][13], w[MOVE_Y][15] = S, ST, -P, WL, -WL
    b[ATTACK] = 0.3
    w[ATTACK][8], w[ATTACK][7] = -0.8, -0.3
    b[PICK] = -1.02
    w[PICK][16], w[PICK][17] = 1.5, 2.0
    return {"weights": w, "bias": b, "move_blend": 0.35, "pick_bias": 0.7}


# ---------------------------------------------------------------- bot người chơi
class Bot:
    """Người chơi giả. react = độ trễ nhìn thấy mối đe doạ; skill = xác suất lăn đúng lúc."""

    def __init__(self, name, keep, react, skill, brawl, rng):
        self.name, self.keep, self.react, self.skill, self.brawl = name, keep, react, skill, brawl
        self.react_j = max(0.05, rng.gauss(react, react * 0.2))
        self.rng = rng
        self.strafe = rng.choice([-1.0, 1.0])
        self.strafe_t = 0.0


BOTS = {
    # tên: (khoảng cách giữ, phản xạ s, kỹ năng lăn, cận chiến?)
    "skilled": (190.0, 0.18, 0.85, False),
    "kiter": (290.0, 0.25, 0.7, False),
    "brawler": (70.0, 0.30, 0.55, True),
    "novice": (220.0, 0.45, 0.25, False),
    # tập giữ lại để kiểm tra (KHÔNG dùng khi huấn luyện)
    "dancer": (210.0, 0.30, 0.6, False),
    "camper": (140.0, 0.35, 0.5, False),
}
TRAIN_BOTS = ["skilled", "kiter", "brawler", "novice"]
HOLDOUT_BOTS = ["dancer", "camper"]


def _unit(v):
    n = math.hypot(v[0], v[1])
    return (v[0] / n, v[1] / n) if n > 1e-6 else (0.0, 0.0)


class Sim:
    def __init__(self, policy, bot_name, seed, use_noise=True):
        self.rng = random.Random(seed)
        self.nrng = np.random.default_rng(seed)
        self.pol = policy
        self.use_noise = use_noise
        keep, react, skill, brawl = BOTS[bot_name]
        self.bot = Bot(bot_name, keep, react, skill, brawl, self.rng)
        self.t = 0.0
        self.boss = [ARENA_W * 0.5, ARENA_H * 0.35]
        self.bvel = [0.0, 0.0]
        self.player = [ARENA_W * 0.5, ARENA_H * 0.8]
        self.pvel = [0.0, 0.0]
        self.hp, self.shield = HP_MAX, SHIELD_MAX
        self.since_hit = 99.0
        self.hurt_t = 0.0
        self.roll_t, self.roll_cd, self.roll_dir = 0.0, 0.0, (0.0, 0.0)
        self.stun_t = 0.0
        self.slow_t = 0.0
        self.rl_t = 0.0
        self.last_action = [0.0, 0.0, 0.0, 0.0]
        self.busy = False
        self.charging = False
        self.charge_dir = (0.0, 0.0)
        self.tele = None            # (kind, dir) cho đòn đường thẳng
        self.cool_t = 1.0
        self.gen = None
        self.wait = 0.0
        self.zones = []             # mỗi zone là dict
        self.bullets = []           # [x,y,vx,vy,dmg,life,homing]
        self.minions = []           # [x,y,life,cd]
        self.damage = 0.0
        self.deaths = 0
        self.hits = 0
        self.heavy = 0
        self.attack_log = {}
        self.dmg_src = {}

    # ------------------------------------------------------------ tiện ích
    @property
    def phase(self):
        return 1 + min(3, int(self.t / PHASE_LEN))

    def sm(self):
        return SPEED_MULT[self.phase - 1]

    def hurt(self, dmg, push_from=None, push=0.0, stun=0.0, src="?"):
        if self.roll_t > 0.0 or self.hurt_t > 0.0:
            return
        self.hurt_t = HURT_INVULN
        self.hits += 1
        if dmg >= 25:
            self.heavy += 1
        self.since_hit = 0.0
        absorbed = min(self.shield, dmg)
        self.shield -= absorbed
        rest = dmg - absorbed
        self.hp -= rest
        self.damage += dmg
        self.dmg_src[src] = self.dmg_src.get(src, 0.0) + dmg
        if push_from is not None and push > 0:
            u = _unit((self.player[0] - push_from[0], self.player[1] - push_from[1]))
            self.player[0] += u[0] * push * 0.12
            self.player[1] += u[1] * push * 0.12
        if stun > 0:
            self.stun_t = max(self.stun_t, stun)
        if self.hp <= 0:
            self.deaths += 1
            self.hp, self.shield = HP_MAX, SHIELD_MAX

    # ------------------------------------------------------------ quan sát + chính sách
    def wall_rays(self):
        out = []
        x, y = self.boss
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            d = 400.0
            if dx > 0:
                d = min(d, ARENA_W - x)
            if dx < 0:
                d = min(d, x)
            if dy > 0:
                d = min(d, ARENA_H - y)
            if dy < 0:
                d = min(d, y)
            out.append(max(0.0, d) / 400.0)
        return out

    def obs(self):
        rel = (self.player[0] - self.boss[0], self.player[1] - self.boss[1])
        o = [0.0] * OBS_SIZE
        o[0] = max(-1.0, min(1.0, rel[0] / 600.0))
        o[1] = max(-1.0, min(1.0, rel[1] / 600.0))
        o[2] = max(-1.0, min(1.0, self.pvel[0] / 400.0))
        o[3] = max(-1.0, min(1.0, self.pvel[1] / 400.0))
        o[4] = max(-1.0, min(1.0, self.bvel[0] / 400.0))
        o[5] = max(-1.0, min(1.0, self.bvel[1] / 400.0))
        o[6] = max(0.0, 1.0 - self.t / HORIZON)
        o[7] = max(0.0, min(1.0, self.hp / HP_MAX))
        o[8] = 1.0 if self.roll_t > 0 else 0.0
        o[9] = self.phase / 4.0
        u = _unit(rel)
        o[10], o[11] = u
        o[12:16] = self.wall_rays()
        return o

    def decide(self):
        o = self.obs()
        f = np.array(o + [math.hypot(o[2], o[3]), math.hypot(o[0], o[1])])
        z = self.pol["weights"] @ f + self.pol["bias"]
        out = np.tanh(z)
        if self.use_noise:
            out = out + self.nrng.normal(0.0, NOISE_STD, ACTION_SIZE)
        self.last_action = [max(-1.0, min(1.0, float(v))) for v in out]

    # ------------------------------------------------------------ các đòn (generator: yield = chờ giây)
    def _prep_line(self):
        self.charge_dir = _unit((self.player[0] - self.boss[0], self.player[1] - self.boss[1]))
        self.tele = ("line", self.charge_dir, self.t)

    def atk_charge(self, tele_t=0.85, dmg=26, speed=640.0):
        self._prep_line()
        yield tele_t * self.sm()
        self.tele = None
        self.charging = True
        self.charge_t = 0.5
        yield 0.5
        self.charging = False
        yield 0.35

    def atk_frost_charge(self):
        self._prep_line()
        yield 1.1 * self.sm()
        self.tele = None
        self.charging = True
        yield 0.5
        self.charging = False
        yield 0.35

    def fire_ring(self, count, off, dmg=10, speed=230.0, life=3.0):
        for i in range(count):
            a = off + math.tau * i / count
            c, s = math.cos(a), math.sin(a)
            self.bullets.append([self.boss[0] + c * (BODY_RADIUS + 6), self.boss[1] + s * (BODY_RADIUS + 6),
                                 c * speed, s * speed, dmg, life, False])

    def atk_ring(self):
        yield 0.7 * self.sm()
        vol = LORD_RING_VOLLEYS[self.phase - 1]
        step = math.tau / LORD_RING_COUNT
        offs = [0.0, step * 0.5, step * 0.25]
        for v in range(vol):
            self.fire_ring(LORD_RING_COUNT, offs[v % 3])
            yield LORD_RING_GAP

    def atk_necro_bolt(self):
        yield 0.5 * self.sm()
        n = 3 if self.phase >= 3 else 1
        base = _unit((self.player[0] - self.boss[0], self.player[1] - self.boss[1]))
        for i in range(n):
            ang = 0.0 if n == 1 else math.radians(-18 + 36 * i / (n - 1))
            c, s = math.cos(ang), math.sin(ang)
            d = (base[0] * c - base[1] * s, base[0] * s + base[1] * c)
            self.bullets.append([self.boss[0] + d[0] * (BODY_RADIUS + 10), self.boss[1] + d[1] * (BODY_RADIUS + 10),
                                 d[0] * 190, d[1] * 190, 16, 3.5, True])
        yield 0.3

    def add_zone(self, x, y, r, tele, dmg, dot=0.0, tick=0.6, stun=0.0, follow=0.0):
        self.zones.append({"x": x, "y": y, "r": r, "tele": tele, "dmg": dmg, "dot": dot, "tick": tick, "tt": 0.0,
                           "stun": stun, "follow": follow, "born": self.t, "fired": False})

    def atk_necro_curse(self):
        self.add_zone(self.player[0], self.player[1], 70 * AOE, 0.7 * self.sm(), 8, dot=3.2)
        yield 0.7 * self.sm() + 0.1

    def atk_spike_field(self):
        yield 0.8 * self.sm()
        cx = self.player[0] + self.pvel[0] * 0.65
        cy = self.player[1] + self.pvel[1] * 0.65
        for i in range(7):
            a = math.tau * i / 7 + self.rng.random() * 0.4
            d = self.rng.uniform(20, 150)
            self.add_zone(cx + math.cos(a) * d, cy + math.sin(a) * d, 34 * AOE, 0.65, 18)
        yield 0.7

    def atk_ice_prison(self):
        yield 0.5 * self.sm()
        tx = self.player[0] + self.pvel[0] * 0.4
        ty = self.player[1] + self.pvel[1] * 0.4
        r = 46 * AOE
        self.add_zone(tx, ty, r, 0.85 * self.sm(), 24, stun=1.3)
        side = _unit((-(ty - self.boss[1]), tx - self.boss[0]))
        for sg in (-1, 1):
            self.add_zone(tx + side[0] * 120 * sg, ty + side[1] * 120 * sg, r, 0.85 * self.sm(), 24, stun=1.3)
        yield 0.85 * self.sm() + 0.2

    def atk_frost_breath(self):
        self.tele = ("cone", _unit((self.player[0] - self.boss[0], self.player[1] - self.boss[1])), self.t)
        yield 0.8 * self.sm()
        d = self.tele[1]
        self.tele = None
        for _ in range(3):
            rel = (self.player[0] - self.boss[0], self.player[1] - self.boss[1])
            dist = math.hypot(*rel)
            if dist < 280 and dist > 1:
                cosang = (rel[0] * d[0] + rel[1] * d[1]) / dist
                if cosang > math.cos(math.radians(32)):
                    self.hurt(8, src="breath")
            yield 0.3
        yield 0.3

    def atk_summon(self, n):
        yield 0.6 * self.sm()
        for i in range(n):
            a = math.tau * i / n + self.rng.random() * 0.5
            self.minions.append([self.boss[0] + math.cos(a) * 60, self.boss[1] + math.sin(a) * 60, 9.0, 0.0])
        yield 0.5

    def atk_judgement(self):
        yield 0.3
        self.add_zone(self.player[0], self.player[1], 230.0, 1.3, 55, follow=0.8)
        yield 1.5
        for _ in range(3):
            cx = self.player[0] + self.pvel[0] * 0.4
            cy = self.player[1] + self.pvel[1] * 0.4
            self.add_zone(cx, cy, 110.0, 0.4, 28)
            yield 0.5
        for r in range(2):
            self.fire_ring(16, (math.pi / 16) * r, dmg=12)
            yield LORD_RING_GAP

    # ------------------------------------------------------------ chọn & chạy đòn
    def pick_attack(self):
        pool = POOLS[self.phase]
        pick = self.last_action[PICK]
        bias = self.pol["pick_bias"]
        w = []
        for a in pool:
            s = 1.0 if a in AREA else (-1.0 if a in DIRECT else 0.0)
            w.append(math.exp(pick * s * bias))
        r = self.rng.random() * sum(w)
        for a, wi in zip(pool, w):
            r -= wi
            if r <= 0:
                return a
        return pool[-1]

    def start_attack(self):
        a = self.pick_attack()
        self.attack_log[a] = self.attack_log.get(a, 0) + 1
        self.busy = True
        self.gen = {
            "charge": self.atk_charge, "ring": self.atk_ring, "necro_bolt": self.atk_necro_bolt,
            "necro_curse": self.atk_necro_curse, "necro_summon": lambda: self.atk_summon(2),
            "frost_breath": self.atk_frost_breath, "spike_field": self.atk_spike_field,
            "frost_charge": self.atk_frost_charge, "ice_prison": self.atk_ice_prison,
            "judgement": self.atk_judgement, "lord_summon_all": lambda: self.atk_summon(4),
        }[a]()
        self.wait = 0.0

    def step_attack(self):
        if self.gen is None:
            return
        self.wait -= DT
        while self.wait <= 0.0:
            try:
                self.wait += float(next(self.gen))
            except StopIteration:
                self.gen = None
                self.busy = False
                self.charging = False
                self.tele = None
                self.cool_t = COOLDOWN[self.phase - 1]
                return

    # ------------------------------------------------------------ bot người chơi
    def threats_visible(self):
        r = self.bot.react_j
        zs = [z for z in self.zones if self.t - z["born"] >= r]
        return zs

    def bot_move(self):
        b = self.bot
        px, py = self.player
        rel = (px - self.boss[0], py - self.boss[1])
        dist = math.hypot(*rel) or 1.0
        away = (rel[0] / dist, rel[1] / dist)
        # mục tiêu: giữ khoảng cách `keep`, lách vòng
        b.strafe_t -= DT
        if b.strafe_t <= 0:
            b.strafe_t = self.rng.uniform(0.8, 2.0)
            if self.rng.random() < 0.4:
                b.strafe = -b.strafe
        tang = (-away[1] * b.strafe, away[0] * b.strafe)
        radial = (dist - b.keep) / 120.0
        radial = max(-1.0, min(1.0, radial))
        dirx = -away[0] * radial + tang[0] * 0.8
        diry = -away[1] * radial + tang[1] * 0.8
        # né vùng nguy hiểm
        danger = False
        for z in self.threats_visible():
            dx, dy = px - z["x"], py - z["y"]
            d = math.hypot(dx, dy)
            if d < z["r"] + 45:
                u = (dx / d, dy / d) if d > 1 else (1.0, 0.0)
                dirx += u[0] * 6.0
                diry += u[1] * 6.0
                danger = True
        # né đường lao / hình nón
        if self.tele is not None and self.t - self.tele[2] >= b.react_j:
            kind, d, _ = self.tele
            relx, rely = px - self.boss[0], py - self.boss[1]
            along = relx * d[0] + rely * d[1]
            perp = -relx * d[1] + rely * d[0]
            lim = 70 if kind == "line" else 280 * math.sin(math.radians(32)) + 30
            if along > -50 and abs(perp) < lim:
                sgn = 1.0 if perp >= 0 else -1.0
                dirx += -d[1] * sgn * 3.0
                diry += d[0] * sgn * 3.0
                danger = True
        # né đạn
        roll_now = False
        for bl in self.bullets:
            rx, ry = bl[0] - px, bl[1] - py
            d = math.hypot(rx, ry)
            if d > 170:
                continue
            vx, vy = bl[2], bl[3]
            sp = math.hypot(vx, vy) or 1.0
            closing = -(rx * vx + ry * vy) / (d * sp + 1e-6)
            if closing > 0.3:
                perp = abs(rx * vy - ry * vx) / sp
                if perp < 30:
                    sgn = 1.0 if (rx * vy - ry * vx) >= 0 else -1.0
                    dirx += (vy / sp) * sgn * 2.0
                    diry += (-vx / sp) * sgn * 2.0
                    danger = True
                    if d / sp < 0.22:
                        roll_now = True
        if self.hurt_t <= 0 and danger and roll_now and self.roll_cd <= 0 and self.rng.random() < b.skill:
            u = _unit((dirx, diry))
            if u != (0.0, 0.0):
                self.roll_t, self.roll_cd, self.roll_dir = ROLL_TIME, ROLL_CD, u
        # tránh tường (người chơi biết không tự dồn mình vào góc)
        wm = 110.0
        if not b.brawl:
            if px < wm:
                dirx += (wm - px) / wm * 2.0
            if px > ARENA_W - wm:
                dirx -= (px - (ARENA_W - wm)) / wm * 2.0
            if py < wm:
                diry += (wm - py) / wm * 2.0
            if py > ARENA_H - wm:
                diry -= (py - (ARENA_H - wm)) / wm * 2.0
        # boss áp sát: bỏ chạy, lăn nếu quá gần
        if not b.brawl and dist < BODY_RADIUS + 60:
            dirx += away[0] * 3.0
            diry += away[1] * 3.0
            danger = True
            if dist < BODY_RADIUS + 25 and self.hurt_t <= 0 and self.roll_cd <= 0 and self.rng.random() < b.skill:
                u = _unit((dirx, diry))
                self.roll_t, self.roll_cd, self.roll_dir = ROLL_TIME, ROLL_CD, u
        # lính triệu hồi: bỏ chạy nhẹ
        for m in self.minions:
            d = math.hypot(m[0] - px, m[1] - py)
            if d < 90:
                dirx += (px - m[0]) / d
                diry += (py - m[1]) / d
        u = _unit((dirx, diry))
        spd = PLAYER_SPEED * (0.55 if self.slow_t > 0 else 1.0)
        return (u[0] * spd, u[1] * spd)

    # ------------------------------------------------------------ vòng lặp
    def clamp(self, p, m=14.0):
        p[0] = max(m, min(ARENA_W - m, p[0]))
        p[1] = max(m, min(ARENA_H - m, p[1]))

    def tick(self):
        t0 = self.t
        # chính sách
        self.rl_t -= DT
        if self.rl_t <= 0:
            self.rl_t = RL_INTERVAL
            self.decide()
        # boss
        if self.charging:
            self.bvel = [self.charge_dir[0] * 640.0, self.charge_dir[1] * 640.0]
        elif not self.busy:
            rel = _unit((self.player[0] - self.boss[0], self.player[1] - self.boss[1]))
            mv = (self.last_action[MOVE_X], self.last_action[MOVE_Y])
            steer = rel
            if math.hypot(*mv) > 0.05:
                bl = self.pol["move_blend"]
                m = _unit(mv)
                steer = _unit((rel[0] * (1 - bl) + m[0] * bl, rel[1] * (1 - bl) + m[1] * bl))
            sp = 55.0 + 20.0 * self.phase
            self.bvel = [steer[0] * sp, steer[1] * sp]
        else:
            self.bvel = [0.0, 0.0]
        self.boss[0] += self.bvel[0] * DT
        self.boss[1] += self.bvel[1] * DT
        self.clamp(self.boss, BODY_RADIUS)
        if self.charging and (self.boss[0] in (BODY_RADIUS, ARENA_W - BODY_RADIUS) or
                              self.boss[1] in (BODY_RADIUS, ARENA_H - BODY_RADIUS)):
            self.charging = False  # đâm tường -> dừng
        # lượt đòn
        if self.gen is None and not self.busy:
            self.cool_t -= DT
            if self.cool_t <= 0:
                self.start_attack()
        self.step_attack()
        # người chơi
        if self.stun_t > 0:
            self.stun_t -= DT
            self.pvel = [0.0, 0.0]
        elif self.roll_t > 0:
            self.roll_t -= DT
            self.pvel = [self.roll_dir[0] * ROLL_SPEED, self.roll_dir[1] * ROLL_SPEED]
        else:
            v = self.bot_move()
            self.pvel = [v[0], v[1]]
        self.player[0] += self.pvel[0] * DT
        self.player[1] += self.pvel[1] * DT
        self.clamp(self.player)
        self.roll_cd = max(0.0, self.roll_cd - DT)
        self.hurt_t = max(0.0, self.hurt_t - DT)
        self.slow_t = max(0.0, self.slow_t - DT)
        self.since_hit += DT
        if self.since_hit > SHIELD_DELAY:
            self.shield = min(SHIELD_MAX, self.shield + SHIELD_RATE * DT)
        # chạm thân boss
        d = math.hypot(self.player[0] - self.boss[0], self.player[1] - self.boss[1])
        if d < BODY_RADIUS + 5:
            if self.charging:
                self.hurt(26, self.boss, 600, src="charge")
            else:
                self.hurt(15, self.boss, 350, src="contact")
        # đạn
        keep = []
        for bl in self.bullets:
            if bl[6]:  # homing
                to = _unit((self.player[0] - bl[0], self.player[1] - bl[1]))
                sp = math.hypot(bl[2], bl[3]) or 1.0
                cur = (bl[2] / sp, bl[3] / sp)
                ang = math.atan2(cur[0] * to[1] - cur[1] * to[0], cur[0] * to[0] + cur[1] * to[1])
                turn = max(-2.5 * DT, min(2.5 * DT, ang))
                c, s = math.cos(turn), math.sin(turn)
                nd = (cur[0] * c - cur[1] * s, cur[0] * s + cur[1] * c)
                bl[2], bl[3] = nd[0] * sp, nd[1] * sp
            bl[0] += bl[2] * DT
            bl[1] += bl[3] * DT
            bl[5] -= DT
            if bl[5] <= 0 or not (0 <= bl[0] <= ARENA_W and 0 <= bl[1] <= ARENA_H):
                continue
            if math.hypot(bl[0] - self.player[0], bl[1] - self.player[1]) < PLAYER_R + 7:
                self.hurt(bl[4], src="bullet%d" % int(bl[4]))
                continue
            keep.append(bl)
        self.bullets = keep
        # vùng
        kz = []
        for z in self.zones:
            if not z["fired"]:
                if z["follow"] > 0 and self.t - z["born"] < z["follow"]:
                    z["x"], z["y"] = self.player[0], self.player[1]
                z["tele"] -= DT
                if z["tele"] <= 0:
                    z["fired"] = True
                    inside = math.hypot(self.player[0] - z["x"], self.player[1] - z["y"]) < z["r"] + PLAYER_R
                    if z["dot"] <= 0:
                        if inside:
                            self.hurt(z["dmg"], stun=z["stun"], src="zone%d" % int(z["dmg"]))
                        continue
                    z["left"] = z["dot"]
                kz.append(z)
            else:
                z["left"] -= DT
                z["tt"] += DT
                if z["tt"] >= z["tick"]:
                    z["tt"] = 0.0
                    if math.hypot(self.player[0] - z["x"], self.player[1] - z["y"]) < z["r"] + PLAYER_R:
                        self.hurt(z["dmg"], src="curse")
                if z["left"] > 0:
                    kz.append(z)
        self.zones = kz
        # lính
        km = []
        for m in self.minions:
            u = _unit((self.player[0] - m[0], self.player[1] - m[1]))
            m[0] += u[0] * 90 * DT
            m[1] += u[1] * 90 * DT
            m[2] -= DT
            m[3] -= DT
            if math.hypot(m[0] - self.player[0], m[1] - self.player[1]) < 26 and m[3] <= 0:
                self.hurt(6, src="minion")
                m[3] = 1.0
            if m[2] > 0:
                km.append(m)
        self.minions = km
        self.t = t0 + DT

    def run(self):
        while self.t < HORIZON:
            self.tick()
        return {"dps": self.damage / HORIZON, "deaths": self.deaths, "hits": self.hits, "heavy": self.heavy,
                "attacks": self.attack_log}


def evaluate(policy, bots, seeds, use_noise=True):
    """Trả về dict bot -> dps trung bình (sát thương gây cho người chơi mỗi giây)."""
    res = {}
    for b in bots:
        vals, deaths, hits = [], [], []
        for s in seeds:
            r = Sim(policy, b, s, use_noise).run()
            vals.append(r["dps"])
            deaths.append(r["deaths"])
            hits.append(r["hits"])
        res[b] = {"dps": float(np.mean(vals)), "deaths": float(np.mean(deaths)), "hits": float(np.mean(hits))}
    return res
