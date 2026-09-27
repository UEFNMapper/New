#!/usr/bin/env bash
# Vérifications statiques : types Luau (luau-lsp), lint (selene).
set -u
cd "$(dirname "$0")/.."
LSP="${LUAU_LSP:-/home/user/tools/luau-lsp/build/luau-lsp}"
rojo sourcemap default.project.json -o sourcemap.json >/dev/null
echo "== luau-lsp analyze =="
"$LSP" analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox=tools/globalTypes.d.luau \
  --ignore="**/Vendor/**" --flag:LuauSolverV2=false src 2>&1 | grep -v "^$" 
python3 "$(dirname "$0")/lint_registry.py"
python3 "$(dirname "$0")/lint_api.py"
