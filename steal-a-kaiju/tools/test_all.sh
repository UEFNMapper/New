#!/usr/bin/env bash
# Batterie complète : analyse statique, tests unitaires, playtests simulés, équilibrage.
set -u
cd "$(dirname "$0")/.."
status=0
step() { echo; echo "===== $1 ====="; }

step "Analyse statique (types Luau, registre, API Roblox)"
out=$(./tools/check.sh 2>&1 | grep -v "^\[" )
echo "$out" | grep -E "registry|api ok|méthode|n'existe" 
if echo "$out" | grep -E "SyntaxError|UnknownGlobal|n'existe pas|méthode inconnue" >/dev/null; then status=1; fi

step "Tests unitaires"
lune run tests/unit.luau 2>&1 | tail -3 || status=1

step "Playtest serveur (3 joueurs, 2 h simulées)"
res=$(lune run tests/sim/playtest.luau 2>&1 | grep -E "RÉSULTAT|❌")
echo "$res"; echo "$res" | grep -q "0 échouées, 0 erreurs" || status=1

step "Playtest client (vrai client contre vrai serveur)"
res=$(lune run tests/sim/client_playtest.luau 2>&1 | grep -E "RÉSULTAT|❌|API ROBLOX")
echo "$res"; echo "$res" | grep -q "0 échouées, 0 erreurs" || status=1

step "Compagnon (Buddy) : serveur + client"
res=$(lune run tests/sim/buddy.luau 2>&1 | grep -E "RÉSULTAT|❌|API ROBLOX")
echo "$res"; echo "$res" | grep -q "0 échouées, 0 erreurs" || status=1

step "Défense de l'île (vagues, tours, bonk, fuites, Alpha, HUD client)"
res=$(lune run tests/sim/siege.luau 2>&1 | grep -E "RÉSULTAT|❌")
echo "$res"; echo "$res" | grep -q "0 échouées, 0 erreurs" || status=1

step "Équilibrage (bot solo, 6 h simulées)"
lune run tests/sim/economy.luau 6 2>&1 | grep -E "^\[|Erreurs"

echo
if [ $status -eq 0 ]; then echo "✅ TOUT EST VERT"; else echo "❌ ÉCHECS DÉTECTÉS"; fi
exit $status
