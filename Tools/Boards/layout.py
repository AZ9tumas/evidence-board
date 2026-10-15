"""Places the board's cards so strings cross as few cards as possible, no label lands on a
card, and each cluster stays grouped under its heading. Cards stay inside their cluster's
region and never overlap. Simulated annealing over card positions."""
import math
import random

import numpy as np

K = 36  # samples along each string
TOP_BAND = 30  # a card's pin margin, where strings may cross their own card
MARGIN = 56  # space kept between cards


def optimize(cards, strings, regions, iterations=40000, seed=3):
    """`regions`: cluster -> (x0, y0, x1, y1). Cards in cluster "fixed" keep their frames."""
    rng = random.Random(seed)
    index = {c["id"]: i for i, c in enumerate(cards)}
    n = len(cards)
    pos = np.array([[c["frame"]["x"], c["frame"]["y"]] for c in cards], float)
    size = np.array([[c["frame"]["width"], c["frame"]["height"]] for c in cards], float)
    cluster = [c["_cluster"] for c in cards]
    movable = [i for i in range(n) if cluster[i] != "fixed"]
    anchor = np.array([[(regions[k][0] + regions[k][2]) / 2, (regions[k][1] + regions[k][3]) / 2] if k in regions else [0, 0]
                       for k in cluster])
    is_movable = np.array([k != "fixed" for k in cluster])
    a_idx = np.array([index[s["from"]] for s in strings])
    b_idx = np.array([index[s["to"]] for s in strings])
    sag = np.array([s["sag"] for s in strings])
    labelled = np.array([bool(s.get("label")) for s in strings])
    label_w = np.array([len(s.get("label") or "") * 7.2 + 36 for s in strings])
    t = np.linspace(0.04, 0.96, K)
    u = 1 - t
    w0, w1, w2, w3 = u**3, 3 * u * u * t, 3 * u * t * t, t**3
    endpoint = np.zeros((len(strings), n), bool)
    endpoint[np.arange(len(strings)), a_idx] = True
    endpoint[np.arange(len(strings)), b_idx] = True

    def cost(p):
        pins = np.stack([p[:, 0] + size[:, 0] / 2, p[:, 1] + 10], 1)
        A, B = pins[a_idx], pins[b_idx]
        d = B - A
        length = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1)
        droop = np.minimum(length * 0.18, 140) * (0.25 + sag)
        down = np.stack([np.zeros_like(droop), droop], 1)
        c1, c2 = A + d / 3 + down, A + 2 * d / 3 + down
        P = (w0[None, :, None] * A[:, None] + w1[None, :, None] * c1[:, None]
             + w2[None, :, None] * c2[:, None] + w3[None, :, None] * B[:, None])
        x0, y0 = p[:, 0], p[:, 1]
        x1, y1 = x0 + size[:, 0], y0 + size[:, 1]
        px, py = P[:, :, 0, None], P[:, :, 1, None]
        inx = (px > x0 + 4) & (px < x1 - 4)
        body = inx & (py > y0 + 4) & (py < y1 - 4)
        text = inx & (py > y0 + TOP_BAND) & (py < y1 - 4)
        other = (body & ~endpoint[:, None, :]).sum()
        own = (text & endpoint[:, None, :]).sum()
        mid = 0.125 * A + 0.375 * c1 + 0.375 * c2 + 0.125 * B
        lx0, lx1 = mid[:, 0] - label_w / 2, mid[:, 0] + label_w / 2
        ly0, ly1 = mid[:, 1] - 13, mid[:, 1] + 13
        hit = (lx0[:, None] < x1) & (x0 < lx1[:, None]) & (ly0[:, None] < y1) & (y0 < ly1[:, None])
        labels = (hit & labelled[:, None]).sum()
        centre = p + size / 2
        pull = np.hypot(*(centre - anchor).T)[is_movable].sum()
        value = other * 1.5 + own * 0.9 + labels * 30 + length.sum() * 0.012 + pull * 0.01
        return value, (other, own, labels)

    def fits(p, i):
        x0, y0, x1, y1 = regions[cluster[i]]
        if p[i, 0] < x0 or p[i, 1] < y0 or p[i, 0] + size[i, 0] > x1 or p[i, 1] + size[i, 1] > y1:
            return False
        sep = ((p[i, 0] + size[i, 0] + MARGIN < p[:, 0]) | (p[:, 0] + size[:, 0] + MARGIN < p[i, 0])
               | (p[i, 1] + size[i, 1] + MARGIN < p[:, 1]) | (p[:, 1] + size[:, 1] + MARGIN < p[i, 1]))
        sep[i] = True
        return bool(np.all(sep))

    # Start: shelf-pack each cluster into its region, row by row.
    for name, (x0, y0, x1, y1) in regions.items():
        members = [i for i in movable if cluster[i] == name]
        x, y, row = x0, y0, 0.0
        for i in members:
            if x + size[i, 0] > x1:
                x, y, row = x0, y + row + MARGIN + 2, 0.0
            pos[i] = [x, y]
            x += size[i, 0] + MARGIN + 2
            row = max(row, size[i, 1])
            if y + size[i, 1] > y1:
                raise SystemExit(f"no room for {cards[i]['_name']} in {name}")

    current, parts = cost(pos)
    best, best_pos = current, pos.copy()
    for step in range(iterations):
        heat = 1 - step / iterations
        temperature = 30 * heat + 0.1
        i = rng.choice(movable)
        trial = pos.copy()
        if rng.random() < 0.2:
            j = rng.choice([k for k in movable if cluster[k] == cluster[i] and k != i])
            trial[i] = pos[j] + (size[j] - size[i]) * [0.5, 0]
            trial[j] = pos[i] + (size[i] - size[j]) * [0.5, 0]
            ok = fits(trial, i) and fits(trial, j)
        else:
            spread = 20 + 350 * heat
            trial[i] += [rng.gauss(0, spread), rng.gauss(0, spread)]
            ok = fits(trial, i)
        if not ok:
            continue
        value, trial_parts = cost(trial)
        if value < current or rng.random() < math.exp((current - value) / temperature):
            pos, current, parts = trial, value, trial_parts
            if value < best:
                best, best_pos = value, pos.copy()
        if step % 10000 == 0:
            print(f"step {step}: cost {current:.0f} (crossings {parts[0]}, own {parts[1]}, labels {parts[2]})")
    final, parts = cost(best_pos)
    print(f"final cost {final:.0f}: crossing other cards {parts[0]}, own text {parts[1]}, labels on cards {parts[2]}")
    for i, c in enumerate(cards):
        c["frame"]["x"], c["frame"]["y"] = float(round(best_pos[i, 0] / 10) * 10), float(round(best_pos[i, 1] / 10) * 10)
