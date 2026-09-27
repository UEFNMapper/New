# Uploader les assets (icônes, sons, modèles) dans ton compte Roblox

Le jeu fonctionne sans rien uploader : les icônes utilisent des emojis de secours et les sons
des sons publics de la bibliothèque Roblox. Pour avoir les **vraies icônes 3D**
(`assets/icons/`, aperçu dans `assets/icons/contact_sheet.png`) et les **sons originaux**
(`assets/audio/`), il faut les uploader dans ton compte (ou ton groupe) puis renseigner les
identifiants dans `src/shared/Config/Icons.luau` (champ `Id`) et
`src/shared/Config/Sounds.luau` (table `Uploaded`).

Deux méthodes : le script automatique (recommandé, 2 minutes) ou l'import manuel dans Studio.

---

## Méthode 1 — Script automatique `tools/upload_assets.py` (Open Cloud)

### 1. Créer une clé API Open Cloud

1. Va sur le **Creator Hub** : <https://create.roblox.com/dashboard/credentials>
   (menu **Open Cloud → API Keys**).
2. **Create API Key** :
   - **Name** : `steal-a-kaiju upload` (ce que tu veux).
   - **Access Permissions** → **Add API System** → choisis **Assets**, puis coche
     **Read** et **Write** (`asset:read` + `asset:write`).
     Si tu uploades sur un **groupe**, sélectionne le groupe ici (tu dois y avoir le rôle
     « Create and edit group experiences / assets »).
   - *(Optionnel, seulement si tu utilises `--image-type Decal`)* : ajoute aussi
     **Legacy Asset Delivery** (lecture) pour que le script puisse convertir les decals en images.
   - **Security** → **Accepted IP addresses** : mets **`0.0.0.0/0`** (toutes les IP) ou ton IP
     publique (<https://www.whatismyip.com>) suivie de `/32`.
   - **Expiration** : laisse *Never expires* ou mets une date.
3. **Save & Generate Key** → copie la clé **maintenant** (elle n'est plus affichée ensuite).
4. Ton **User ID** : c'est le nombre dans l'URL de ton profil
   (`https://www.roblox.com/users/123456789/profile` → `123456789`). Pour un groupe, le nombre
   dans l'URL du groupe.

> ⚠️ Ne mets jamais la clé dans un fichier du projet ni dans git. Passe-la en variable
> d'environnement ou en argument.

### 2. Lancer le script

```bash
# Depuis la racine du projet
export ROBLOX_API_KEY="ta_clé_ici"
python3 tools/upload_assets.py --user-id 123456789          # tout (icônes + sons + modèles)
python3 tools/upload_assets.py --group-id 987654 --only icons
python3 tools/upload_assets.py --user-id 123456789 --dry-run  # juste lister, sans envoyer
```

Le script :

- envoie chaque fichier à `POST https://apis.roblox.com/assets/v1/assets` (icônes en
  `Image`, sons en `Audio`, `.fbx`/`.rbxm` de `assets/models/` en `Model`) à raison d'un
  par seconde, attend la fin de l'opération et réessaie tout seul sur `429` / erreurs réseau ;
- mémorise chaque upload dans **`assets/upload_state.json`** (empreinte SHA-256 → id) : tu
  peux le relancer autant de fois que tu veux, il ne renvoie que ce qui est nouveau ou modifié
  (`--force` pour tout renvoyer) ;
- écrit automatiquement les identifiants dans `Icons.luau` (`Id = …`) et dans la table
  `Uploaded` de `Sounds.luau` ;
- affiche l'état de modération (`Approved` / `Reviewing`). Un asset en `Reviewing` fonctionne
  dès qu'il est approuvé (quelques minutes en général).

Ensuite : `rojo build default.project.json -o release/StealAKaiju.rbxlx` (ou `rojo serve`)
et les icônes/sons apparaissent en jeu.

### Limites à connaître

| Sujet | Détail |
|---|---|
| Sons | Roblox limite les uploads audio à **100 par mois** pour un compte vérifié par pièce d'identité, **10 par mois** sinon. Le pack en contient 46 : vérifie ton compte avant, ou fais-le en deux mois. |
| Taille | 20 Mo max par fichier (nos icônes font ~40 Ko). |
| Images : Decal vs Image | Roblox distingue le **Decal** (enveloppe) de l'**Image** (le fichier). Les `ImageLabel` ont besoin de l'id de l'**Image**. Le script envoie `assetType = "Image"` (id directement utilisable) et, si l'API refuse, retombe sur `Decal` puis essaie de retrouver l'id d'image via l'API *Asset Delivery* (permission « Legacy Asset Delivery » nécessaire, pas disponible pour les groupes). S'il n'y arrive pas, il garde le `decalId` dans `upload_state.json` : colle alors `rbxassetid://<decalId>` dans la propriété `Image` d'un `ImageLabel` dans Studio, qui le convertit tout seul en id d'image, et recopie cet id dans `Icons.luau`. |
| Modèles | Un `.fbx` s'uploade comme `Model` (c'est même le seul type dont le contenu peut être mis à jour ensuite). Le script ne remplit pas de fichier Luau pour les modèles : les ids sont dans `upload_state.json`. |
| Erreur 401 / 403 | Clé invalide, permission *Assets: Read/Write* manquante, IP non autorisée, ou clé créée pour un groupe alors que tu passes `--user-id` (et inversement). |

---

## Méthode 2 — Import manuel dans Roblox Studio (Bulk Import)

1. Ouvre le jeu dans Studio → onglet **View → Asset Manager** (ou **Toolbox → Creations**).
2. Dans l'Asset Manager, clique sur **Bulk Import** (l'icône avec la flèche), sélectionne
   tous les `.png` de `assets/icons/` (sauf `contact_sheet.png`), puis les `.ogg` de
   `assets/audio/`.
3. Attends la modération (une coche verte). Clique-droit sur chaque asset →
   **Copy ID to clipboard** (pour une image, l'Asset Manager copie déjà l'id de l'**Image**,
   pas du Decal).
4. Colle les ids :
   - `src/shared/Config/Icons.luau` : `shop = { Id = 123456789, Emoji = "🛒" },`
   - `src/shared/Config/Sounds.luau`, dans la table `Uploaded` entre les marqueurs
     `BEGIN UPLOADED` / `END UPLOADED` : `ui_click = 123456789,`
5. Vérifie avec `./tools/check.sh` (types Luau) puis rebuild avec Rojo.

Astuce : la clé d'un son est le nom du fichier sans `.ogg` (`ui_click.ogg` → `ui_click`) ; la clé
d'une icône est le nom du fichier sans `.png` (`egg_rare.png` → `egg_rare`).

---

## Crédits obligatoires

Les icônes viennent de **Microsoft Fluent Emoji** (MIT) et de **game-icons.net** (CC BY 3.0,
icône *Gold stack* par Delapouite). Garde une mention dans la description du jeu ou un écran
« Crédits » : voir `assets/icons/LICENSES.md`.
