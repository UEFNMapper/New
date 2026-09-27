# Licences des icônes (`assets/icons/`)

Toutes les icônes de ce dossier proviennent de banques d'icônes publiques, sous
licences permissives. La provenance exacte de chaque fichier est dans
`MANIFEST.json` (champs `source`, `sourceName`, `license`, `attribution`).

| Source | Fichiers | Licence |
|---|---|---|
| Microsoft Fluent Emoji — style « 3D » | 115 icônes (`source: "fluent-3d"`) | MIT |
| game-icons.net | `robux.png`, `robux_white.png` (`source: "game-icons"`) | CC BY 3.0 |
| Kenney | *(aucune utilisée)* | CC0 |

Modifications apportées : les fichiers Fluent sont utilisés tels quels (256 × 256, PNG
RGBA), sauf `blood_moon` (teinté rouge) et `egg_rare` / `egg_epic` / `egg_legendary` /
`egg_mythic` / `egg_celestial` / `egg_secret` (recolorés, `egg_secret` reçoit en plus des
étincelles blanches). L'icône game-icons est rendue de SVG vers PNG en version blanche et
en version colorée (dégradé radial doré, ombre interne, contour), pour se fondre dans le
style glossy du reste du pack.

---

## 1. Microsoft Fluent Emoji (MIT)

Dépôt : <https://github.com/microsoft/fluentui-emoji> — fichiers `assets/<Nom>/3D/<nom>_3d.png`.

```
MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE
```

## 2. game-icons.net (CC BY 3.0)

Licence : Creative Commons Attribution 3.0 Unported —
<https://creativecommons.org/licenses/by/3.0/>. L'attribution ci-dessous doit être
conservée (par exemple dans la description du jeu ou un écran « Crédits »).

| Fichier | Icône | Auteur | Page |
|---|---|---|---|
| `robux.png`, `robux_white.png` | *Gold stack* (pile de lingots d'or) | **Delapouite** | <https://game-icons.net/1x1/delapouite/gold-stack.html> |

Texte d'attribution suggéré : « Icône *Gold stack* par Delapouite (game-icons.net), CC BY 3.0. »

## 3. Kenney (CC0)

Les packs Kenney (<https://kenney.nl/assets/game-icons>) sont sous licence CC0 1.0
(domaine public, aucune attribution requise). Aucun fichier Kenney n'est utilisé dans la
version actuelle du pack ; si tu en ajoutes, indique-le dans `MANIFEST.json` avec
`"source": "kenney"`, `"license": "CC0 1.0"`.
