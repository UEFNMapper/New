#!/usr/bin/env bash
# Envoie le code du bot Discord (instance Oracle) vers GitHub.
# A lancer SUR L'INSTANCE ORACLE, une seule fois.
#
#   bash push-bot.sh [chemin_du_bot]
#
# Le script ne pousse rien tant qu'il n'a pas votre confirmation,
# et il refuse de pousser s'il detecte un secret dans les fichiers.

set -euo pipefail

REPO_URL="https://github.com/UEFNMapper/New.git"
BRANCH="${BRANCH:-main}"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- 1. dossier
step "1/6  Localisation du bot"

BOT_DIR="${1:-}"
if [ -z "$BOT_DIR" ]; then
  # On tente de deduire le dossier depuis le processus en cours d'execution.
  pid=$(pgrep -f -n 'python.*\.py|node.*\.(js|mjs|ts)' 2>/dev/null | head -1 || true)
  if [ -n "$pid" ] && [ -r "/proc/$pid/cwd" ]; then
    BOT_DIR=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
    [ -n "$BOT_DIR" ] && ylw "Detecte via le processus $pid : $BOT_DIR"
  fi
fi

if [ -z "$BOT_DIR" ]; then
  red "Impossible de trouver le dossier du bot automatiquement."
  echo "Relancez avec le chemin, par exemple :   bash $0 ~/mon-bot"
  echo
  echo "Pour le retrouver :"
  echo "  ps -eo pid,args | grep -Ei 'python|node' | grep -v grep"
  echo "  systemctl status '*bot*' 2>/dev/null | head -20"
  exit 1
fi

BOT_DIR=$(readlink -f "$BOT_DIR")
[ -d "$BOT_DIR" ] || { red "Dossier introuvable : $BOT_DIR"; exit 1; }
cd "$BOT_DIR"
grn "Dossier du bot : $BOT_DIR"
echo "Contenu :"
ls -la | head -25

# ---------------------------------------------------------------- 2. gitignore
step "2/6  Protection des secrets (.gitignore)"

# On n'ecrase pas un .gitignore existant, on complete.
touch .gitignore
add_ignore() {
  grep -qxF "$1" .gitignore 2>/dev/null || echo "$1" >> .gitignore
}
for pattern in \
  '.env' '.env.*' '*.env' 'config.json' 'token.txt' 'secrets.json' \
  '*.key' '*.pem' 'credentials*' \
  '__pycache__/' '*.pyc' '.venv/' 'venv/' 'env/' \
  'node_modules/' 'package-lock.json.bak' \
  '*.db' '*.sqlite' '*.sqlite3' 'data/*.json.bak' \
  '*.log' 'logs/' '.DS_Store'
do
  add_ignore "$pattern"
done
grn ".gitignore mis a jour ($(wc -l < .gitignore) lignes)"
ylw "ATTENTION : si votre token est en dur dans un .py ou .js, le .gitignore ne le protege PAS."
ylw "L'etape 4 le detectera."

# ---------------------------------------------------------------- 3. git init
step "3/6  Preparation du depot"

if [ ! -d .git ]; then
  git init -q
  grn "Depot git initialise."
else
  ylw "Depot git deja present, on reutilise."
fi

git config user.email "${GIT_EMAIL:-onepiece54830@gmail.com}"
git config user.name  "${GIT_NAME:-UEFNMapper}"
git checkout -q -B "$BRANCH"
git add -A

if git diff --cached --quiet; then
  red "Aucun fichier a envoyer (tout est ignore ou deja commite)."
  exit 1
fi

# ---------------------------------------------------------------- 4. secrets
step "4/6  Scan de securite"

FOUND=0
TMP_HITS=$(mktemp)
trap 'rm -f "$TMP_HITS" "$TMP_HITS.files"' EXIT

# Fichiers reellement sur le point d'etre envoyes, texte uniquement.
git diff --cached --name-only -z | while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue   # saute les binaires
  printf '%s\0' "$f"
done > "$TMP_HITS.files"

scan() {
  local label="$1" pattern="$2"
  while IFS= read -r -d '' f; do
    grep -nEH "$pattern" "$f" 2>/dev/null | head -3 \
      | sed "s/^/[$label] /" >> "$TMP_HITS" || true
  done < "$TMP_HITS.files"
}

scan "token discord" '[MNO][A-Za-z0-9_-]{22,27}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{25,}'
scan "secret en dur"  '(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|WEBHOOK)[A-Z_]*[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{12,}'

if [ -s "$TMP_HITS" ]; then
  red "SECRET POTENTIEL DETECTE — rien n'a ete envoye :"
  echo
  sed 's/^/   /' "$TMP_HITS" | cut -c1-160 | sort -u
  echo
  ylw "Corrigez d'abord : sortez la valeur dans un fichier .env (deja ignore),"
  ylw "remplacez-la dans le code par os.getenv(\"DISCORD_TOKEN\") ou process.env.DISCORD_TOKEN,"
  ylw "puis REGENEREZ le token sur https://discord.com/developers/applications"
  ylw "(il est considere comme compromis des qu'il a traine en clair)."
  echo
  read -r -p "Ignorer cet avertissement et pousser quand meme ? (tapez OUI) " force
  [ "$force" = "OUI" ] || { echo "Annule."; exit 1; }
else
  grn "Aucun secret evident detecte."
fi

# ---------------------------------------------------------------- 5. resume
step "5/6  Resume avant envoi"

echo "Branche      : $BRANCH"
echo "Destination  : $REPO_URL"
echo "Fichiers     : $(git diff --cached --name-only | wc -l)"
echo "Taille       : $(du -sh --exclude=.git . 2>/dev/null | cut -f1)"
echo
echo "Liste (30 premiers) :"
git diff --cached --name-only | head -30 | sed 's/^/   /'
echo
ylw "Verifiez que le depot GitHub est bien en PRIVE avant de continuer."
read -r -p "Envoyer ? (o/N) " ok
case "$ok" in o|O|oui|OUI) ;; *) echo "Annule."; exit 0;; esac

git commit -q -m "Import du bot Discord depuis l'instance Oracle"
grn "Commit cree."

# ---------------------------------------------------------------- 6. push
step "6/6  Envoi vers GitHub"

echo "Il faut un token GitHub (Personal Access Token, 'fine-grained') :"
echo "  github.com > Settings > Developer settings > Personal access tokens"
echo "  > Fine-grained tokens > Generate new token"
echo "  Repository access : UEFNMapper/New     Permissions : Contents = Read and write"
echo
read -r -s -p "Collez le token (invisible a la saisie) : " GH_TOKEN
echo

[ -n "$GH_TOKEN" ] || { red "Token vide."; exit 1; }

git remote remove origin 2>/dev/null || true
git remote add origin "$REPO_URL"

# Le token passe par une variable d'env, jamais dans l'URL du remote
# (sinon il resterait en clair dans .git/config).
ASKPASS=$(mktemp)
chmod 700 "$ASKPASS"
cat > "$ASKPASS" <<'ASK'
#!/bin/sh
case "$1" in
  *Username*) echo "x-access-token" ;;
  *)          echo "$GH_TOKEN" ;;
esac
ASK
export GH_TOKEN
export GIT_ASKPASS="$ASKPASS"
export GIT_TERMINAL_PROMPT=0

attempt=0
until GIT_ASKPASS="$ASKPASS" git push -u origin "$BRANCH"; do
  attempt=$((attempt+1))
  [ "$attempt" -ge 4 ] && { rm -f "$ASKPASS"; red "Echec apres 4 tentatives."; exit 1; }
  delay=$((2 ** attempt))
  ylw "Echec, nouvelle tentative dans ${delay}s..."
  sleep "$delay"
done

rm -f "$ASKPASS"
unset GH_TOKEN

echo
grn "==========================================="
grn " Termine. Le code est sur GitHub."
grn " https://github.com/UEFNMapper/New"
grn "==========================================="
echo
echo "Vous pouvez maintenant demander des modifications depuis votre telephone."
echo "Pensez a supprimer le token GitHub s'il ne doit pas rester actif."
