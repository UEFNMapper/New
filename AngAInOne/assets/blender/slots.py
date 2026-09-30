"""Slots de carte mère renforcés : PcieSlot (x16, blindage métal, loquet) et DimmSlot (DDR5, 2 loquets,
détrompeur aligné sur RamStick). python3 slots.py [PcieSlot|DimmSlot]"""
import sys
from hw_common import *


def slot(name, L, W, H, groove_w, key_x, latches, pitch, key_w=0.5, camera=(1.0, -1.5, 1.2)):
    reset()
    # ---------------------------------------------------------------- corps plastique
    body = rbox((L, W, H), (0, 0, H / 2), r=0.15, seg=2)
    cut = [rbox((L - 1.2, groove_w, H), (0, 0, H / 2 + 0.9)),
           rbox((L - 1.2 + 0.6, groove_w + 0.5, 0.5), (0, 0, H + 0.05), r=0.0)]    # chanfrein d'entrée
    bool_op(body, cut)
    key = rbox((key_w, groove_w + 0.1, H - 1.1), (key_x, 0, (H - 1.1) / 2 + 0.55))
    parts = [body, key]
    # pattes de soudure plastique
    for sx in (-1, 1):
        parts.append(rcyl(0.35, 0.6, (sx * (L / 2 - 1.5), 0, -0.1), verts=12))
    tag(merge(parts), "Body", "SmoothPlastic", GRAPHITE_0)
    # ---------------------------------------------------------------- contacts dorés dans la fente
    src = rbox((pitch * 0.5, 0.06, 1.4), (0, 0, 0))
    mats = []
    n = int((L - 2.4) / pitch)
    for k in range(n):
        x = -L / 2 + 1.2 + (k + 0.5) * (L - 2.4) / n
        if abs(x - key_x) < key_w:
            continue
        for sy in (-1, 1):
            mats.append(T((x, sy * (groove_w / 2 - 0.02), H - 1.6)))
    tag(instances(src, mats, "Contacts"), "Contacts", "Foil", GOLD)
    # ---------------------------------------------------------------- blindage métal (U + rebords + nervures)
    t = 0.18
    arm = []
    for sy in (-1, 1):
        side = rbox((L + 0.2, t, H - 0.6), (0, sy * (W / 2 + t / 2), (H - 0.6) / 2 + 0.3), r=0.05, seg=1)
        lip = rbox((L + 0.2, (W - groove_w) / 2 + t - 0.15, t), (0, sy * (W / 2 + t - ((W - groove_w) / 2 + t - 0.15) / 2), H + t / 2),
                   r=0.05, seg=1)
        arm += [side, lip]
        for k in range(int(L // 6)):  # nervures embouties
            x = -L / 2 + 3 + k * 6
            arm.append(rbox((3.4, 0.14, 0.9), (x, sy * (W / 2 + t + 0.05), H * 0.52), r=0.06, seg=1))
    for sx in (-1, 1):  # embouts et pattes de soudure métal
        arm.append(rbox((t, W + 2 * t, H - 0.6), (sx * (L / 2 + 0.1 + t / 2), 0, (H - 0.6) / 2 + 0.3), r=0.05, seg=1))
        arm.append(rbox((0.8, 0.5, 0.8), (sx * (L / 2 - 4.0), W / 2 + t + 0.25, 0.1), r=0.05, seg=1))
        arm.append(rbox((0.8, 0.5, 0.8), (sx * (L / 2 - 4.0), -W / 2 - t - 0.25, 0.1), r=0.05, seg=1))
    logo = side_text("A", 1.3, 0.1, -L / 2 + 6.0, H * 0.5, W / 2 + t, -1)
    tag(merge(arm + [logo]), "Armor", "Metal", ALU)
    # ---------------------------------------------------------------- loquets
    lat = []
    for lx in latches:
        s = 1 if lx > 0 else -1
        x0 = lx
        blk = rbox((1.6, W + 0.3, H + 0.6), (x0 + s * 0.8, 0, (H + 0.6) / 2), r=0.2, seg=2)
        tab = prism_y([(x0 + s * 0.2, H + 0.6), (x0 + s * 1.6, H + 0.6), (x0 + s * 2.8, H + 2.4), (x0 + s * 2.2, H + 2.8),
                       (x0 + s * 0.2, H + 1.6)], -W / 2 + 0.1, W / 2 - 0.1)
        bev(tab, 0.12, 2, 30)
        hook = rbox((0.6, groove_w * 0.9, 1.4), (x0 - s * 0.1, 0, H + 0.5), r=0.1, seg=1)
        grip = [rbox((0.12, W - 0.4, 0.5), (x0 + s * (2.0 + 0.2 * k), 0, H + 1.8 + 0.3 * k), r=0.03, seg=1,
                     rot=(0, s * math.radians(-50), 0)) for k in range(3)]
        lat += [blk, tab, hook] + grip
    tag(merge(lat), "Latch", "SmoothPlastic", GRAPHITE_2)
    done(name, camera=camera)


JOBS = {
    "PcieSlot": lambda: slot("PcieSlot", 38.0, 3.0, 4.0, 1.1, -38.0 / 2 + 4.3, [38.0 / 2], 0.5, camera=(0.8, -1.6, 1.1)),
    "DimmSlot": lambda: slot("DimmSlot", 44.0, 2.4, 3.2, 0.62, -1.2, [-44.0 / 2, 44.0 / 2], 0.3, key_w=0.36,
                             camera=(0.8, -1.6, 1.1)),
}
if __name__ == "__main__":
    for key in (sys.argv[1:] or JOBS):
        JOBS[key]()
