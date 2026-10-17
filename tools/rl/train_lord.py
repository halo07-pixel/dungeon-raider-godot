"""Huấn luyện chính sách Dungeon Lord bằng Evolution Strategies (chỉ cần numpy).

Chạy:  python3 tools/rl/train_lord.py [--iters 60] [--pop 16] [--seed 1] [--out assets/ai/lord_policy.json]

Tối ưu: 3 hàng trọng số (MOVE_X, MOVE_Y, PICK) + bias + move_blend + pick_bias, xuất phát từ bộ tiên nghiệm
viết tay của rl_controller.gd. Mục tiêu = sát thương/giây gây cho các bot người chơi (huấn luyện),
NHƯNG bị chặn để Lord không khó vô lý: điểm bão hoà ở +MAX_GAIN so với tiên nghiệm, và bot giỏi nhất không
bị vượt quá SKILLED_CAP lần so với tiên nghiệm. Kết quả được kiểm tra trên bot KHÔNG dùng khi huấn luyện.
"""
import argparse
import json
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lord_sim as L  # noqa: E402

ROWS = [L.MOVE_X, L.MOVE_Y, L.PICK]
NW = L.FEAT
DIM = len(ROWS) * (NW + 1) + 2
MAX_DELTA = 1.0          # |trọng số - tiên nghiệm| tối đa khi huấn luyện
MAX_GAIN = 0.30          # điểm bão hoà: tối đa +30% sát thương/giây so với tiên nghiệm
SKILLED_CAP = 1.40       # bot giỏi nhất không bị khó hơn quá 40%
BLEND_RANGE = (0.1, 0.7)
BIAS_RANGE = (0.3, 2.2)

PRIOR = L.prior_policy()


def build(theta):
    th = theta
    w = PRIOR["weights"].copy()
    b = PRIOR["bias"].copy()
    i = 0
    for r in ROWS:
        w[r] = np.clip(w[r] + th[i:i + NW], PRIOR["weights"][r] - MAX_DELTA, PRIOR["weights"][r] + MAX_DELTA)
        i += NW
        b[r] = float(np.clip(b[r] + th[i], PRIOR["bias"][r] - MAX_DELTA, PRIOR["bias"][r] + MAX_DELTA))
        i += 1
    mb = float(np.clip(PRIOR["move_blend"] + th[i], *BLEND_RANGE))
    pb = float(np.clip(PRIOR["pick_bias"] + th[i + 1], *BIAS_RANGE))
    return {"weights": w, "bias": b, "move_blend": mb, "pick_bias": pb}


def _eval(args):
    theta, seeds = args
    r = L.evaluate(build(theta), L.TRAIN_BOTS, seeds)
    return {k: v["dps"] for k, v in r.items()}


def fitness(res, prior_res, theta):
    mean = float(np.mean(list(res.values())))
    pmean = float(np.mean(list(prior_res.values())))
    score = min(mean, pmean * (1.0 + MAX_GAIN))
    over = max(0.0, res["skilled"] - prior_res["skilled"] * SKILLED_CAP)
    score -= 3.0 * over
    score -= 0.05 * float(np.mean(theta ** 2))
    return score


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=60)
    ap.add_argument("--pop", type=int, default=16)
    ap.add_argument("--sigma", type=float, default=0.15)
    ap.add_argument("--lr", type=float, default=0.08)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ai", "lord_policy.json"))
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    theta = np.zeros(DIM)
    t0 = time.time()
    log = []
    with Pool(2) as pool:
        for it in range(a.iters):
            seeds = [int(x) for x in rng.integers(1, 10**6, 8)]   # cùng seed cho cả quần thể (giảm nhiễu)
            prior_res = _eval((np.zeros(DIM), seeds))
            eps = rng.normal(0.0, 1.0, (a.pop, DIM))
            cands = [theta + a.sigma * e for e in eps] + [theta - a.sigma * e for e in eps]
            outs = pool.map(_eval, [(c, seeds) for c in cands])
            fit = np.array([fitness(o, prior_res, c) for o, c in zip(outs, cands)])
            f_pos, f_neg = fit[:a.pop], fit[a.pop:]
            adv = (f_pos - f_neg)
            if np.std(adv) > 1e-9:
                adv = adv / (np.std(adv) + 1e-9)
            grad = (adv[:, None] * eps).mean(axis=0)
            theta = theta + a.lr * grad * 3.0
            cur = _eval((theta, seeds))
            gain = np.mean(list(cur.values())) / np.mean(list(prior_res.values())) - 1.0
            log.append(float(gain))
            print("iter %3d  gain vs prior (train bots) %+5.1f%%  skilled %.2f (prior %.2f)  %.0fs" % (
                it, gain * 100, cur["skilled"], prior_res["skilled"], time.time() - t0), flush=True)
    pol = build(theta)

    # ---- kiểm tra độc lập (seed mới, cả bot huấn luyện lẫn bot giữ lại)
    seeds = list(range(5000, 5030))
    base = L.evaluate(PRIOR, list(L.BOTS), seeds)
    new = L.evaluate(pol, list(L.BOTS), seeds)
    report = {}
    print("\nKIỂM TRA (30 seed mới, 60s/trận):  bot | tiên nghiệm dps | đã học dps | thay đổi | lần chết/phút")
    for b in L.BOTS:
        tag = "(giữ lại)" if b in L.HOLDOUT_BOTS else ""
        ch = new[b]["dps"] / base[b]["dps"] - 1.0
        report[b] = {"prior_dps": round(base[b]["dps"], 3), "trained_dps": round(new[b]["dps"], 3),
                     "change_pct": round(ch * 100, 1), "prior_deaths": round(base[b]["deaths"], 2),
                     "trained_deaths": round(new[b]["deaths"], 2), "holdout": b in L.HOLDOUT_BOTS}
        print("  %-8s %-9s %5.2f -> %5.2f  (%+5.1f%%)  chết %.2f -> %.2f" % (
            b, tag, base[b]["dps"], new[b]["dps"], ch * 100, base[b]["deaths"], new[b]["deaths"]))
    out = {
        "version": 1, "kind": "lord", "obs_size": L.OBS_SIZE, "feat_size": L.FEAT,
        "weights": [[round(float(x), 5) for x in row] for row in pol["weights"]],
        "bias": [round(float(x), 5) for x in pol["bias"]],
        "move_blend": round(pol["move_blend"], 4), "pick_bias": round(pol["pick_bias"], 4),
        "trained_with": "tools/rl/train_lord.py (Evolution Strategies, trình mô phỏng tools/rl/lord_sim.py)",
        "report": report,
    }
    path = os.path.abspath(a.out)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("\nĐã ghi", path)


if __name__ == "__main__":
    main()
