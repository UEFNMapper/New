#!/usr/bin/env bash
# A COLLER DANS ORACLE CLOUD SHELL (icone >_ en haut de la console).
#
# Contourne l'interface graphique : envoie une commande a l'instance via
# l'agent Oracle Cloud, en utilisant le CLI deja authentifie dans Cloud Shell.
# Aucune cle SSH necessaire.
#
#   bash cloudshell-run.sh [nom_instance] [commande]
#
# Par defaut : instance "discordbot", commande = le script de diagnostic.

set -uo pipefail

INSTANCE_NAME="${1:-discordbot}"
COMMANDE="${2:-curl -fsSL https://raw.githubusercontent.com/UEFNMapper/New/fb3352afa63dc778c1e74b9a793eaa07f10bcdf3/scripts/diagnostic.sh | bash}"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

command -v oci >/dev/null 2>&1 || { red "Le CLI 'oci' est absent : ce script doit tourner dans Cloud Shell."; exit 1; }

step "1/4  Recherche de l'instance \"$INSTANCE_NAME\""

INFOS=$(oci search resource structured-search \
  --query-text "query instance resources where displayName = '$INSTANCE_NAME'" \
  --query 'data.items[0].[identifier,"compartment-id","lifecycle-state"]' \
  --raw-output 2>/dev/null | tr -d '[]," ' | grep -v '^$')

INSTANCE_ID=$(echo "$INFOS" | sed -n '1p')
COMPARTMENT_ID=$(echo "$INFOS" | sed -n '2p')
ETAT=$(echo "$INFOS" | sed -n '3p')

if [ -z "${INSTANCE_ID:-}" ]; then
  red "Instance \"$INSTANCE_NAME\" introuvable."
  echo "Instances visibles :"
  oci search resource structured-search \
    --query-text "query instance resources" \
    --query 'data.items[].["display-name","lifecycle-state"]' 2>/dev/null | head -30
  exit 1
fi

grn "Instance : $INSTANCE_ID"
echo "Etat      : $ETAT"

step "2/4  Envoi de la commande"

CONTENU=$(mktemp); trap 'rm -f "$CONTENU"' EXIT
python3 - "$COMMANDE" > "$CONTENU" <<'PY'
import json, sys
print(json.dumps({
    "source": {"sourceType": "TEXT", "text": sys.argv[1]},
    "output": {"outputType": "TEXT"},
}))
PY

CMD_ID=$(oci compute-instance-agent instance-agent-command create \
  --compartment-id "$COMPARTMENT_ID" \
  --execution-time-out-in-seconds 900 \
  --display-name "diagnostic-claude" \
  --target "{\"instanceId\":\"$INSTANCE_ID\"}" \
  --content "file://$CONTENU" \
  --query 'data.id' --raw-output 2>&1)

case "$CMD_ID" in
  ocid1.*) grn "Commande envoyee : ${CMD_ID:0:40}..." ;;
  *)
    red "Echec de l'envoi :"
    echo "$CMD_ID" | head -10
    echo
    ylw "Cause la plus frequente : le plugin 'Compute Instance Run Command'"
    ylw "est desactive. Console > instance > Oracle Cloud Agent > activez-le,"
    ylw "attendez 3 minutes, puis relancez ce script."
    exit 1 ;;
esac

step "3/4  Attente du resultat"

for i in $(seq 1 30); do
  ETAT_EXEC=$(oci compute-instance-agent instance-agent-command-execution get \
    --instance-agent-command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query 'data."lifecycle-state"' --raw-output 2>/dev/null)
  case "$ETAT_EXEC" in
    SUCCEEDED|FAILED|TIMED_OUT) break ;;
  esac
  printf '.'
  sleep 5
done
echo

step "4/4  Sortie (etat: ${ETAT_EXEC:-inconnu})"
echo "----------------------------------------------------------"
oci compute-instance-agent instance-agent-command-execution get \
  --instance-agent-command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query 'data.content.output.message' --raw-output 2>/dev/null \
  || red "Impossible de recuperer la sortie."
echo "----------------------------------------------------------"
