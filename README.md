# Bot Discord — accès à distance

> Ce dépôt contient aussi **[`trailer-uefn/`](trailer-uefn/)** : un logiciel qui monte
> automatiquement des trailers UEFN (coupes sur le rythme, bandeaux, carte de fin avec le
> code de l'île) et génère les miniatures de l'île.

Ce dépôt sert de pont entre l'instance **Oracle Cloud** (où le bot tourne 24h/24)
et le travail à distance depuis un téléphone.

## Le problème résolu

Le code du bot n'existait que sur l'instance Oracle, accessible uniquement en SSH.
Les sessions Claude dans le cloud n'ont pas d'accès SSH sortant : impossible de
modifier le bot sans une machine personnelle. En plaçant le code ici, les
modifications peuvent être préparées à distance, puis déployées sur l'instance
par une seule commande.

## Mise en place (une seule fois)

Sur l'instance Oracle :

```bash
curl -fsSL <URL_DU_SCRIPT> -o push-bot.sh
less push-bot.sh          # lire avant d'exécuter
bash push-bot.sh          # ou : bash push-bot.sh /chemin/vers/le/bot
```

Le script :

1. localise le dossier du bot (automatiquement, via le processus en cours) ;
2. écrit un `.gitignore` couvrant `.env`, bases de données, logs, `__pycache__`,
   `node_modules` ;
3. **refuse de pousser** s'il détecte un token en clair dans le code ;
4. affiche la liste exacte des fichiers avant tout envoi ;
5. pousse vers GitHub via un token saisi en invisible, jamais écrit dans
   `.git/config`.

### Sans clé SSH (console Oracle, « Run Command »)

« Run Command » ne peut pas poser de questions. Le script accepte alors un mode
automatique, où le scan de sécurité reste bloquant :

```bash
YES=1 GH_TOKEN=github_pat_xxx BOT_PATH=/home/ubuntu/mon-bot bash push-bot.sh
```

> **Ordre important :** téléchargez le script *avant* de passer le dépôt en privé
> (l'URL brute cesse d'être accessible sans authentification ensuite), puis
> mettez-le en privé *avant* d'y envoyer le code du bot.
> GitHub › Settings › General › Change repository visibility › Private.

## Boucle de travail

```
téléphone  ──demande──>  Claude  ──push──>  GitHub
                                               │
instance Oracle  <──deploy-bot.sh──────────────┘
```

Pour déployer, sur l'instance :

```bash
cd /chemin/vers/le/bot
bash scripts/deploy-bot.sh
```

Le script sauvegarde le commit courant, installe les dépendances si
`requirements.txt` ou `package.json` a changé, redémarre le service, vérifie
qu'il tourne et propose un retour arrière automatique en cas d'échec.

## Règles sur les secrets

- Le token Discord vit dans `.env` sur l'instance, jamais dans le dépôt.
- Dans le code : `os.getenv("DISCORD_TOKEN")` ou `process.env.DISCORD_TOKEN`.
- Un token qui a été commité une fois est compromis, même après suppression :
  le régénérer sur <https://discord.com/developers/applications>.
- La base de données des niveaux reste sur l'instance ; elle est ignorée par git
  pour éviter d'écraser la progression des membres lors d'un déploiement.
