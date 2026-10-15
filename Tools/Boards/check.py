"""Reports strings that cross cards and labels that land on cards. Usage: check.py board.evboard"""
import json, math, sys
b = json.load(open(sys.argv[1]))
cards = {c["id"]: c for c in b["cards"]}
name = {c["id"]: (c.get("text", {}).get("content") or c.get("web", {}).get("snapshot", {}).get("title") or c.get("image", {}).get("caption") or "?")[:28].replace("\n", " ") for c in b["cards"]}
def pin(c):
    f = c["frame"]; return (f["x"] + f["width"] / 2, f["y"] + 10)
def inside(p, f, pad=6):
    return f["x"] + pad < p[0] < f["x"] + f["width"] - pad and f["y"] + 24 < p[1] < f["y"] + f["height"] - pad
total_cross = 0; label_hits = 0
for s in b["strings"]:
    a, z = cards[s["from"]], cards[s["to"]]
    A, B = pin(a), pin(z)
    dx, dy = B[0] - A[0], B[1] - A[1]; L = max(math.hypot(dx, dy), 1)
    droop = min(L * 0.18, 140) * (0.25 + s["sag"])
    c1 = (A[0] + dx / 3, A[1] + dy / 3 + droop); c2 = (A[0] + 2 * dx / 3, A[1] + 2 * dy / 3 + droop)
    def P(t):
        u = 1 - t
        return (u**3 * A[0] + 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t**3*B[0], u**3 * A[1] + 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t**3*B[1])
    crossed = set()
    for i in range(1, 80):
        p = P(i / 80)
        for cid, c in cards.items():
            if cid in (s["from"], s["to"]): continue
            if inside(p, c["frame"]): crossed.add(cid)
    total_cross += len(crossed)
    msg = []
    if crossed: msg.append("crosses " + ", ".join(name[c] for c in crossed))
    if s.get("label"):
        m = P(0.5); w = len(s["label"]) * 7 + 34; box = (m[0] - w / 2, m[1] - 12, m[0] + w / 2, m[1] + 12)
        for cid, c in cards.items():
            f = c["frame"]
            if box[0] < f["x"] + f["width"] and f["x"] < box[2] and box[1] < f["y"] + f["height"] and f["y"] < box[3]:
                msg.append(f"LABEL '{s['label']}' on {name[cid]}"); label_hits += 1
    if msg: print(f"{name[s['from']]} -> {name[s['to']]}: " + "; ".join(msg))
print("TOTAL crossings", total_cross, "label hits", label_hits)
