#!/bin/bash
# Lecture seule : ne modifie rien sur le serveur.
echo "########## 1. SERVICE ##########"
systemctl list-units --type=service --all --no-legend 2>/dev/null \
  | grep -iE 'bot|discord|py' | head -5
echo
echo "########## 2. PROCESSUS ##########"
ps -eo pid,user,args 2>/dev/null | grep -Ei 'python|node' | grep -v grep | cut -c1-140 | head -5
echo
echo "########## 3. DOSSIER DU BOT ##########"

# Un dossier n'est retenu que s'il contient vraiment du code de bot.
est_un_bot() {
  [ -d "$1" ] || return 1
  case "$1" in /|/root|/home|/tmp|/usr|/etc) return 1;; esac
  # Chaque motif est teste separement : "ls a.py b.js" echoue en bloc
  # des qu'un seul des deux manque, ce qui invaliderait un dossier valide.
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

# a) dossier de travail des processus python/node en cours
for p in $(pgrep -f 'python|node' 2>/dev/null | head -10); do
  ajoute "$(readlink -f /proc/$p/cwd 2>/dev/null)"
done

# b) dossier du fichier reellement execute par le processus
for p in $(pgrep -f 'python|node' 2>/dev/null | head -10); do
  f=$(tr '\0' '\n' < /proc/$p/cmdline 2>/dev/null | grep -E '\.(py|js|mjs)$' | head -1)
  case "$f" in
    /*) ajoute "$(dirname "$f")" ;;
    ?*) ajoute "$(readlink -f /proc/$p/cwd 2>/dev/null)" ;;
  esac
done

# c) recherche sur disque, en dernier recours
for f in $(find /home /opt /srv /var -maxdepth 4 \
             \( -name 'bot.py' -o -name 'main.py' -o -name 'index.js' -o -name 'bot.js' \) \
             -not -path '*/node_modules/*' 2>/dev/null | head -10); do
  ajoute "$(dirname "$f")"
done

if [ -z "$CANDIDATS" ]; then
  echo "AUCUN dossier de bot trouve automatiquement."
else
  echo "Candidats :"
  for c in $CANDIDATS; do
    n=$(ls -1 "$c" 2>/dev/null | wc -l)
    echo "   $c   ($n fichiers)"
  done
fi
BOT=$(echo $CANDIDATS | awk '{print $1}')
echo "Retenu pour la suite : ${BOT:-aucun}"

echo
if [ -n "$BOT" ] && [ -d "$BOT" ]; then
  echo "########## 4. CONTENU de $BOT ##########"
  ls -la "$BOT" | head -25
  echo
  echo "--- sous-dossiers ---"
  find "$BOT" -maxdepth 2 -type d -not -path '*/.git*' -not -name '__pycache__' \
    -not -path '*node_modules*' 2>/dev/null | head -15
  echo
  echo "--- taille ---"
  du -sh "$BOT" 2>/dev/null
  echo
  echo "########## 5. SECRETS ##########"
  [ -f "$BOT/.env" ] && echo "OK: un fichier .env existe (le token est probablement dedans)" \
                     || echo "ATTENTION: pas de .env"
  echo "Token ecrit en dur dans le code ?"
  grep -rlnE '[MNO][A-Za-z0-9_-]{22,27}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{25,}' \
    "$BOT" --include='*.py' --include='*.js' --include='*.json' 2>/dev/null | head -5 \
    || true
  echo "(aucun nom de fichier ci-dessus = rien trouve, c'est bon)"
  echo
  echo "########## 6. GIT ##########"
  [ -d "$BOT/.git" ] && { echo "depot git deja present:"; git -C "$BOT" remote -v 2>/dev/null | head -3; } \
                     || echo "pas encore de depot git"
  echo
  echo "########## 7. FICHIERS /niveau ##########"
  grep -rlin 'niveau\|level\|creature\|tetard\|salamandre\|dragon' \
    "$BOT" --include='*.py' --include='*.js' 2>/dev/null | head -10
fi
echo
echo "########## 8. OUTILS ##########"
echo "git: $(command -v git || echo ABSENT)   python3: $(python3 -V 2>&1 | head -1)   node: $(node -v 2>/dev/null || echo absent)"
echo
echo "########## FIN ##########"
