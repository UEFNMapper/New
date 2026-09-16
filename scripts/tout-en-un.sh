#!/bin/bash
# Diagnostic + envoi du code vers GitHub, en une seule execution.
# Concu pour "Run command" de la console Oracle : aucune interaction, pas de
# couleurs (la console Oracle afficherait les codes d'echappement en clair).
#
#   GH_TOKEN=github_pat_xxx bash tout-en-un.sh
#
# Sans GH_TOKEN, seul le diagnostic tourne : rien n'est envoye.

set -uo pipefail

REPO_URL="https://github.com/UEFNMapper/New.git"
BRANCH="${BRANCH:-main}"
GH_TOKEN="${GH_TOKEN:-}"
FORCE="${FORCE:-0}"

titre() { echo; echo "########## $* ##########"; }

# ---------------------------------------------------------------- detection
est_un_bot() {
  [ -d "$1" ] || return 1
  case "$1" in /|/root|/home|/tmp|/usr|/etc|"") return 1;; esac
  for motif in "$1"/*.py "$1"/*.js "$1"/*.mjs "$1"/requirements.txt "$1"/package.json; do
    [ -e "$motif" ] && return 0
  done
  return 1
}

CANDIDATS=""
ajoute() {
  est_un_bot "$1" || return 0
  case " $CANDIDATS " in *" $1 "*) ;; *) CANDIDATS="$CANDIDATS $1";; esac
}

titre "1. SERVICE"
systemctl list-units --type=service --all --no-legend 2>/dev/null \
  | grep -iE 'bot|discord' | head -5
echo "(vide = le bot n'est pas lance par systemd)"

titre "2. PROCESSUS"
ps -eo pid,user,args 2>/dev/null | grep -Ei 'python|node' | grep -v grep | cut -c1-140 | head -5

titre "3. DOSSIER DU BOT"
for p in $(pgrep -f 'python|node' 2>/dev/null | head -10); do
  ajoute "$(readlink -f /proc/$p/cwd 2>/dev/null)"
  f=$(tr '\0' '\n' < /proc/$p/cmdline 2>/dev/null | grep -E '\.(py|js|mjs)$' | head -1)
  case "$f" in /*) ajoute "$(dirname "$f")";; esac
done
for f in $(find /home /opt /srv /var -maxdepth 4 \
             \( -name 'bot.py' -o -name 'main.py' -o -name 'index.js' -o -name 'bot.js' \) \
             -not -path '*/node_modules/*' 2>/dev/null | head -10); do
  ajoute "$(dirname "$f")"
done

BOT_DIR="${BOT_PATH:-$(echo $CANDIDATS | awk '{print $1}')}"
if [ -z "$CANDIDATS" ] && [ -z "${BOT_PATH:-}" ]; then
  echo "AUCUN dossier de bot trouve. Relancez avec BOT_PATH=/chemin/du/bot"
  exit 1
fi
echo "Candidats :$CANDIDATS"
echo "Retenu    : $BOT_DIR"

cd "$BOT_DIR" || { echo "Impossible d'entrer dans $BOT_DIR"; exit 1; }

titre "4. CONTENU"
ls -la | head -25
echo "--- taille ---"; du -sh . 2>/dev/null

titre "5. FICHIERS /niveau"
grep -rlin 'niveau\|creature\|tetard\|salamandre\|dragon' \
  . --include='*.py' --include='*.js' 2>/dev/null | head -10

titre "6. OUTILS"
echo "git: $(command -v git || echo ABSENT)  python3: $(python3 -V 2>&1)  node: $(node -v 2>/dev/null || echo absent)"
command -v git >/dev/null || { echo "git absent : installez-le (sudo dnf install -y git) puis relancez."; exit 1; }

# ---------------------------------------------------------------- gitignore
titre "7. PROTECTION DES SECRETS"
touch .gitignore
for motif in '.env' '.env.*' '*.env' 'config.json' 'token.txt' 'secrets.json' \
  '*.key' '*.pem' 'credentials*' '__pycache__/' '*.pyc' '.venv/' 'venv/' 'env/' \
  'node_modules/' '*.db' '*.sqlite' '*.sqlite3' '*.log' 'logs/' '.DS_Store'; do
  grep -qxF "$motif" .gitignore 2>/dev/null || echo "$motif" >> .gitignore
done
echo ".gitignore : $(wc -l < .gitignore) lignes"
[ -f .env ] && echo "OK : un .env existe, il restera sur le serveur" || echo "Note : pas de .env"

titre "8. PREPARATION DU DEPOT"
[ -d .git ] || git init -q
git config user.email "onepiece54830@gmail.com"
git config user.name  "UEFNMapper"
git checkout -q -B "$BRANCH" 2>/dev/null
git add -A
NB=$(git diff --cached --name-only | wc -l)
echo "$NB fichiers prets a partir"
[ "$NB" -eq 0 ] && { echo "Rien a envoyer."; exit 0; }
git diff --cached --name-only | head -30

titre "9. SCAN DE SECURITE"
HITS=$(git diff --cached --name-only | while read -r f; do
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue
  grep -nEH '[MNO][A-Za-z0-9_-]{22,27}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{25,}' "$f" 2>/dev/null | head -2
  grep -nEH '(TOKEN|SECRET|PASSWORD|API_?KEY)[A-Z_]*[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{12,}' "$f" 2>/dev/null | head -2
done | cut -c1-150)

if [ -n "$HITS" ]; then
  echo "SECRET DETECTE — rien ne sera envoye :"
  echo "$HITS"
  if [ "$FORCE" != "1" ]; then
    echo
    echo "Sortez la valeur dans .env, puis REGENEREZ le token sur"
    echo "https://discord.com/developers/applications"
    echo "(Relancer avec FORCE=1 pour passer outre, deconseille.)"
    exit 1
  fi
  echo "FORCE=1 : on continue malgre tout."
else
  echo "Aucun secret evident detecte."
fi

# ---------------------------------------------------------------- push
titre "10. ENVOI VERS GITHUB"
if [ -z "$GH_TOKEN" ]; then
  echo "Pas de GH_TOKEN fourni : diagnostic termine, rien envoye."
  echo "Pour envoyer, relancez la commande avec GH_TOKEN=github_pat_xxx devant."
  exit 0
fi

git commit -q -m "Import du bot Discord depuis l'instance Oracle" 2>/dev/null || true

git remote remove origin 2>/dev/null
git remote add origin "$REPO_URL"

ASKPASS=$(mktemp); chmod 700 "$ASKPASS"
cat > "$ASKPASS" <<'ASK'
#!/bin/sh
case "$1" in *Username*) echo "x-access-token";; *) echo "$GH_TOKEN";; esac
ASK
export GH_TOKEN GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0

i=0
until git push -u origin "$BRANCH" 2>&1; do
  i=$((i+1))
  [ "$i" -ge 4 ] && { rm -f "$ASKPASS"; echo "ECHEC apres 4 tentatives."; exit 1; }
  echo "Nouvelle tentative dans $((2**i))s..."
  sleep $((2**i))
done
rm -f "$ASKPASS"

echo
echo "=========================================="
echo " TERMINE — le code est sur GitHub."
echo " https://github.com/UEFNMapper/New"
echo "=========================================="
echo "Pensez a revoquer le token GitHub : il est visible"
echo "dans l'historique des commandes de la console Oracle."
