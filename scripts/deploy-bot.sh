#!/usr/bin/env bash
# Recupere les modifications depuis GitHub et redemarre le bot.
# A lancer SUR L'INSTANCE ORACLE, a chaque fois que vous voulez deployer.
#
#   bash deploy-bot.sh [branche]
#
# Sauvegarde l'etat courant avant de changer quoi que ce soit,
# et propose un retour arriere si le bot ne redemarre pas.

set -euo pipefail

BRANCH="${1:-main}"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

[ -d .git ] || { red "Lancez ce script depuis le dossier du bot."; exit 1; }

step "1/4  Etat actuel"
BEFORE=$(git rev-parse HEAD)
echo "Commit actuel : ${BEFORE:0:8}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  ylw "Des modifications locales non commitees existent."
  git status --short | sed 's/^/   /'
  read -r -p "Les mettre de cote (git stash) ? (o/N) " s
  case "$s" in o|O|oui|OUI) git stash push -u -m "avant deploiement $(date +%F-%H%M)"; grn "Mises de cote.";;
    *) red "Annule — commitez ou supprimez ces changements d'abord."; exit 1;; esac
fi

step "2/4  Recuperation depuis GitHub"
attempt=0
until git fetch origin "$BRANCH"; do
  attempt=$((attempt+1))
  [ "$attempt" -ge 4 ] && { red "Echec du fetch apres 4 tentatives."; exit 1; }
  delay=$((2 ** attempt)); ylw "Nouvelle tentative dans ${delay}s..."; sleep "$delay"
done

echo "Changements a appliquer :"
git log --oneline "HEAD..origin/$BRANCH" | head -20 | sed 's/^/   /'
if [ -z "$(git log --oneline "HEAD..origin/$BRANCH")" ]; then
  grn "Deja a jour, rien a faire."; exit 0
fi

read -r -p "Appliquer ? (o/N) " ok
case "$ok" in o|O|oui|OUI) ;; *) echo "Annule."; exit 0;; esac
git merge --ff-only "origin/$BRANCH"
AFTER=$(git rev-parse HEAD)
grn "Passe de ${BEFORE:0:8} a ${AFTER:0:8}"

step "3/4  Dependances"
if [ -f requirements.txt ] && [ -n "$(git diff --name-only "$BEFORE" "$AFTER" -- requirements.txt)" ]; then
  ylw "requirements.txt a change, installation..."
  if [ -d .venv ]; then .venv/bin/pip install -q -r requirements.txt
  elif [ -d venv ]; then venv/bin/pip install -q -r requirements.txt
  else pip3 install -q --user -r requirements.txt; fi
  grn "Dependances Python a jour."
fi
if [ -f package.json ] && [ -n "$(git diff --name-only "$BEFORE" "$AFTER" -- package.json)" ]; then
  ylw "package.json a change, installation..."
  npm install --silent
  grn "Dependances Node a jour."
fi

step "4/4  Redemarrage"

SERVICE=$(systemctl list-units --type=service --all --no-legend 2>/dev/null \
          | awk '{print $1}' | grep -iE 'bot|discord' | head -1 || true)

restart_ok=0
if [ -n "$SERVICE" ]; then
  echo "Service detecte : $SERVICE"
  sudo systemctl restart "$SERVICE"
  sleep 5
  if systemctl is-active --quiet "$SERVICE"; then
    grn "Le bot tourne."
    restart_ok=1
  else
    red "Le bot NE redemarre PAS. 30 dernieres lignes :"
    sudo journalctl -u "$SERVICE" -n 30 --no-pager | sed 's/^/   /'
  fi
elif command -v pm2 >/dev/null 2>&1 && pm2 list 2>/dev/null | grep -q online; then
  pm2 restart all && sleep 5
  pm2 list
  restart_ok=1
else
  ylw "Aucun service systemd ni pm2 detecte."
  ylw "Redemarrez le bot manuellement (screen -r, tmux attach, etc.)."
  exit 0
fi

if [ "$restart_ok" -eq 0 ]; then
  echo
  read -r -p "Revenir a la version precedente ? (o/N) " rb
  case "$rb" in o|O|oui|OUI)
      git reset --hard "$BEFORE"
      [ -n "$SERVICE" ] && sudo systemctl restart "$SERVICE"
      ylw "Retour arriere effectue vers ${BEFORE:0:8}.";;
    *) red "Le bot reste hors service. Corrigez avant de quitter.";; esac
  exit 1
fi

grn "Deploiement termine."
