"""Pré-rend (et met en cache) les kaijus et décors utilisés par make.py."""
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art

KAIJUS = ["KingKaiju", "Toastzilla", "SushiRex", "Pigeonator", "Crabzooka", "Donutron", "OmegaSushiMech",
          "NuclearPigeon", "Frostodon", "Magmadillo", "Gloop", "Hydroblob", "KawaiiKraken", "Pizzapocalypse",
          "Kebabzilla", "SharktoastSupreme", "CosmoGoose", "Drakonda", "Egg_Legendary", "Egg_Secret", "Egg_Epic", "Egg_Common"]
SCENES = ["island", "crater", "wide", "horizon", "world:Candy", "world:Frost", "world:Volcano", "world:Cosmic"]

if __name__ == "__main__":
    for v in SCENES:
        t = time.time(); art.scene(v); print("scene", v, round(time.time() - t), "s", flush=True)
    for k in KAIJUS:
        t = time.time(); art.kaiju(k, 900); print("kaiju", k, round(time.time() - t), "s", flush=True)
    print("DONE", flush=True)
