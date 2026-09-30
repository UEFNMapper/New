#!/usr/bin/env bash
# Vérification complète du projet : types stricts, lint, format, tests, build.
# Usage : ./scripts/verify.sh   (depuis le dossier AngAInOne)
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLING=".tooling"
mkdir -p "$TOOLING"
DEFS="$TOOLING/globalTypes.None.d.luau"
DOCS="$TOOLING/api-docs.json"
if [ ! -f "$DEFS" ]; then
	echo "→ Téléchargement des définitions de types Roblox"
	curl -sSLf -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi
if [ ! -f "$DOCS" ]; then
	curl -sSLf -o "$DOCS" https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/api-docs/en-us.json || true
fi

echo "→ Sourcemap Rojo"
rojo sourcemap default.project.json -o sourcemap.json

echo "→ Analyse de types (luau-lsp, mode strict)"
luau-lsp analyze \
	--definitions=@roblox="$DEFS" \
	--sourcemap=sourcemap.json \
	--base-luaurc=.luaurc \
	--ignore="src/server/Packages/**" \
	--ignore="src/shared/Packages/**" \
	--flag:LuauSolverV2=false \
	src

echo "→ Lint (selene)"
if [ ! -f roblox.yml ]; then
	# Génère la bibliothèque standard Roblox pour selene ; repli sur une version minimale hors ligne.
	selene generate-roblox-std >/dev/null 2>&1 || cp scripts/roblox_lite.yml roblox.yml
fi
selene src

echo "→ Format (stylua --check)"
stylua --check src tests

echo "→ Build (rojo)"
rojo build default.project.json -o AngAInOne.rbxl

echo "→ Tests (lune)"
lune run tests/run.luau
echo "✔ Tout est vert."
