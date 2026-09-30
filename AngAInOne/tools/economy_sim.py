#!/usr/bin/env python3
"""AngAInOne - simulateur d'economie (pacing du GDD).

Joueur "glouton" : achete toujours l'upgrade au meilleur ratio gain/cout
(retour sur investissement < 15 min), debloque la zone suivante des qu'il peut,
et fait un Reboot 1 h apres son dernier deblocage de zone.
Ce joueur est optimal : un vrai joueur mettra environ 1,3 a 1,5x plus de temps.

Usage : python3 economy_sim.py
Ce modele sera porte en Luau (EconomyFormulas) et teste avec Lune a l'etape 2.
"""

ZONES = ["PSU", "RAM", "SSD", "Cooling", "CPU", "GPU", "AICore"]
UNLOCK_COST = [0, 2.5e4, 2.5e7, 2.5e9, 7.5e10, 3e12, 1e14]
SINGULARITY_COST = 1e17  # fin du jeu : construire la puce "Singularite" dans l'AI Core

LEVEL_GROWTH = 1.12            # cout(niveau) = baseCost * 1.12^niveau
ZONE_COST_SCALE = 20           # le module de base de chaque zone coute x20 celui de la zone precedente
ZONE_PROD_SCALE = 15           # ... et produit x15
MILESTONES = (10, 25, 50, 100)  # production x2 a chacun de ces niveaux
MODULE_TIERS = (1, 6, 36)       # 3 modules par zone (cout/prod relatifs)

FIRMWARE_PER_POINT = 0.05      # +5 % de production par point de Firmware (additif)
FIRMWARE_DIVISOR = 1e11        # Firmware gagne = floor(sqrt(BitsGagnesDuRun / 1e11))


def modules(zone: int):
    base_cost = 10 * ZONE_COST_SCALE ** zone
    base_prod = 1 * ZONE_PROD_SCALE ** zone
    return [(base_cost * k, base_prod * k * 0.9) for k in MODULE_TIERS]


def production(base_prod: float, level: int) -> float:
    mult = 1
    for m in MILESTONES:
        if level >= m:
            mult *= 2
    return base_prod * level * mult


def run(mult: float, horizon: int, stop_at: float | None = None):
    mods = [modules(z) for z in range(7)]
    money = earned = 0.0
    zone, t = 0, 0
    levels = {(z, j): 0 for z in range(7) for j in range(3)}
    levels[(0, 0)] = 1
    unlocked = {}
    step = 10
    while t < horizon:
        rate = sum(production(mods[z][j][1], levels[(z, j)]) for z in range(zone + 1) for j in range(3)) * mult
        money += rate * step
        earned += rate * step
        t += step
        if zone == 6 and money >= SINGULARITY_COST:
            unlocked["SINGULARITE"] = t
            break
        if stop_at is not None and t >= stop_at:
            break
        if zone < 6 and money >= UNLOCK_COST[zone + 1]:
            money -= UNLOCK_COST[zone + 1]
            zone += 1
            levels[(zone, 0)] = max(levels[(zone, 0)], 1)
            unlocked[ZONES[zone]] = t
            continue
        while True:
            best = None
            for z in range(zone + 1):
                for j in range(3):
                    base_cost, base_prod = mods[z][j]
                    lvl = levels[(z, j)]
                    cost = base_cost * LEVEL_GROWTH ** lvl
                    gain = production(base_prod, lvl + 1) - production(base_prod, lvl)
                    payback_limit = 900 if zone < 6 else 3600
                    if cost <= money and cost / gain < payback_limit:
                        if best is None or gain / cost > best[0]:
                            best = (gain / cost, z, j, cost)
            if best is None:
                break
            _, z, j, cost = best
            money -= cost
            levels[(z, j)] += 1
    return unlocked, t, earned


def main():
    total, firmware = 0, 0
    for gen in range(1, 16):
        mult = 1 + FIRMWARE_PER_POINT * firmware
        unlocked, t, _ = run(mult, 8 * 3600)
        if "SINGULARITE" in unlocked:
            print(f"Gen {gen} (x{mult:.2f}) : Singularite en {unlocked['SINGULARITE'] / 3600:.1f} h"
                  f" -> temps cumule {(total + unlocked['SINGULARITE']) / 3600:.1f} h")
            return
        last = max(unlocked.values()) if unlocked else t
        unlocked, t, earned = run(mult, 8 * 3600, stop_at=min(last + 3600, 8 * 3600))
        total += t
        firmware += int((earned / FIRMWARE_DIVISOR) ** 0.5)
        zones = ", ".join(f"{k} {v / 60:.0f}min" for k, v in unlocked.items())
        print(f"Gen {gen} (x{mult:.2f}) : {zones} | Reboot apres {t / 3600:.1f} h,"
              f" Firmware total {firmware}, cumul {total / 3600:.1f} h")


if __name__ == "__main__":
    main()
