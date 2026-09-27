# Steal a Kaiju — Architecture & contrat client/serveur

Projet Rojo. Tout le jeu (carte, modèles, UI) est construit **en code** au lancement.

```
src/shared  -> ReplicatedStorage.Shared   (config, logique pure, KaijuBuilder, Net)
src/server  -> ServerScriptService.Server (services, MapBuilder, ProfileStore)
src/client  -> StarterPlayerScripts.Client (contrôleurs, UI)
src/first   -> ReplicatedFirst.Loading    (écran de chargement)
```

Langue de l'interface : **anglais** (portée mondiale ; la traduction automatique
de Roblox couvre le français et les autres langues). Commentaires du code : français.

## Serveur

Services (dans `src/server/Services`), reliés par `Registry` :
DataService, Router, Notify, ShopService, PlotService, KaijuService,
MeteorService, StealService, EventService, RewardService, ProgressionService,
LeaderboardService.

## Actions client → serveur

`Remote.Call(nom, payload)` → `{ ok: boolean, msg: string?, ... }`

| Action | Payload | Réponse |
|---|---|---|
| Buy | `{ Kind = "Pass" \| "Product", Key, Target? (uid pour InstantGrow) }` | ok |
| BuyUpgrade | `{ Id }` (Shield, Sneakers, Muscles, Bonker, Reactor) | ok |
| BuyNest | `{}` | ok |
| BuyPotion / UsePotion | `{ Id }` (Luck, Growth, Cash) | ok |
| Lock | `{}` | ok |
| Sell | `{ Uid }` | `amount` |
| Feed | `{ Uid, Food }` (Snack, Feast, Steak) | ok |
| BuyMeteor | `{ Id }` | `free` |
| Steal | `{ Uid }` | `lifting` |
| Help | `{ Uid }` | ok |
| Drop | `{}` | ok |
| ClaimDaily | `{}` | `text`, `streak` |
| ClaimPlaytime | `{ Index }` | `text` |
| ClaimQuest | `{ Id }` | `text` |
| ClaimQuestBonus | `{}` | `text` |
| Redeem | `{ Code }` | `text` |
| ClaimGroup | `{}` | `text` |
| Spin | `{ UseGems? }` | `index` (1..#Rewards.Wheel), `source` |
| Tutorial | `{ Step }` | ok |
| Settings | `{ Music?, Sfx?, LowFx? }` | ok |
| Rebirth | `{}` | `level` |
| Fuse | `{ A, B }` (uids) | `species`, `mutation` |
| FuseOdds | `{ A, B }` | `odds = { { Label, Chance } }` |
| SetBuddy | `{ Uid }` (kaiju éclos à soi, recharge 10 s) | `cooldown` |

Entrées fréquentes sans réponse : `Remote.Input("Bonk")`, `Remote.Input("Orb", { Id })`.

## État client (`State`)

`State.Get(clé)`, `State.Observe(clé, fn)`, `State.Changed(clé):Connect(fn)`.

Clés = champs de `Shared.Logic.DataTemplate` (Cash, Gems, TotalEarned, Rebirths,
Nests, Stored, Kaijus, PendingEggs, Upgrades, Potions, Boosts, Index, Daily,
Quests, Codes, Stats, Settings, Spins, FreeSpinAt, Tutorial, GroupClaimed,
StarterPack…) **plus** les valeurs dérivées :

| Clé | Contenu |
|---|---|
| Passes | `{ [Key] = true }` passes possédés |
| RandomRestricted | bool : masquer les achats liés au hasard (PolicyService) |
| Multiplier | multiplicateur de cash total |
| Luck | chance personnelle |
| GrowthRate | vitesse de croissance |
| Income | $/s actuel |
| Friends | amis présents sur le serveur |
| SessionStart | `workspace:GetServerTimeNow()` au début de session |
| PlaytimeClaimed | `{ [index] = true }` cadeaux déjà pris cette session |

`Kaijus` est une liste de records : `{ Uid, Species?, Rarity, Mutation?, Growth, Nest, Egg?, HatchAt? }`.

## Effets serveur → client (`FxBus.On(nom, fn(args))`)

(tous) = envoyé à tous les joueurs.

PassUnlocked{Key,Name} · CashBurst{Amount} · GemBurst{Amount} · Purchased{Key,Name} ·
Upgraded{Id,Level} · NestUnlocked{Count} · PotionUsed{Id} · ShieldUp{Plot} (tous) ·
ShieldZap{Plot,Protected} · EggGift{Rarity,Source,Uid} · Hatch{Uid,Species,Mutation,Rarity} ·
HatchWorld{Uid,Rarity} (tous) · StageUp{Uid,Stage} (tous) · Collect{Amount} ·
Sold{Amount,Species} · Fed{Uid,Food} (tous) · WelcomeBack{Amount,Seconds,Capped,MaxHours} ·
PersonalMeteor{Rarity} · MeteorBought{Id,Buyer,Rarity,From} (tous) · MeteorExpired{Id} (tous) ·
Alarm{Uid,Thief,Species} · AlarmStop{Uid} · Grabbed{Uid,Lifting?,Helper?} · HelperJoined{Name} ·
KaijuReturned{Uid,Reason} (tous) · HeistSuccess{Uid,Species,Mutation,Stage} · Robbed{Thief,Species} ·
HeistCut{Amount,Leader} · BonkSwing{UserId,Super} (tous) · Knockback{Velocity,From} ·
BonkHit{UserId,Position} (tous) · StampedeWave (tous) · OrbGrabbed{Id,Amount} · OrbGone{Id} (tous) ·
BossSpawn (tous) · BossEnd{Defeated} (tous) · BossReward{Gems,Top} · BossHit{UserId,Damage} (tous) ·
BossStomp (tous) · Infected{Uid,Mutation} (tous) · EventStart{Id,By} (tous) · EventEnd{Id} (tous) ·
QuestReady{Id,Text} · RewardClaimed{Text,Source} · Discovered{Species,Mutation,NewSpecies} ·
DailyReady · Rebirth{UserId,Level} (tous) · Fused{Uid,Species,Mutation,Secret} ·
BuddyChanged{Uid,Species,Mutation,Reason=Auto|Set|Lost,First} · BuddyLevelUp{Level,Radius,Reason} ·
BuddyTreasure{Id,Position,ExpireAt} · BuddyTreasureGone{Id} · BuddyDig{Id,Position,Kind,Amount,Text,Rarity?} ·
BuddyDigWorld{UserId,Position,Kind} (tous) · BuddyMagnet{Positions,Count} · BuddyPounce{UserId,Target,Boss?} (tous)

Toasts : `Notify` → types Info | Good | Bad | Cash | Gem | Rare.
Fil d'annonces : styles Meteor | Rare | Heist | Help | Event | Boss | Purchase | Rebirth | Info.

## Attributs répliqués

- `workspace` : EventId, EventEnds, CraterLuck, ServerLuck, ServerLuckUntil
- `workspace.Map.Plot<i>` : Index, OwnerId, OwnerName, ShieldUntil, ShieldCooldown, ProtectedUntil, Nests, Stored
- Ancres `workspace.Kaijus.<userId>.<uid>` : Uid, Owner, OwnerName, Plot, Nest, Rarity, Egg, HatchAt,
  Species, Mutation, Stage, Growth, GrowthStamp, GrowthRate, Income, SellValue, CarriedBy, Helper, Lifting, LiftUntil
- Météores `workspace.Meteors.<id>` : Id, Rarity, Price, LandAt, ExpireAt, Owner, Pad
- Orbes `workspace.Orbs.<id>` : Id — Boss `workspace.Effects.Boss` : Species, Mutation, MaxHP, HP, Scale
- Joueur : Plot, Carrying, BuddyUid, BuddySpecies, BuddyMutation, BuddyLevel, TreasurePos (Vector3, trésor privé en cours)
- Trésors `workspace.DigSpots.<id>` : Id, Owner, ExpireAt + ProximityPrompt « DIG » (désactivé localement chez les autres clients)

Les temps sont en `workspace:GetServerTimeNow()` (même échelle que `os.time()`).

## Client

- `Controllers/State`, `Remote`, `Audio`, `FxBus`, `UIRegistry` : fondations.
- `UI/Kit` : composants (Panel, Button, Window, Tabs, Ribbon, Hazard, Starburst, ProgressBar,
  Scroll, Chip, Badge, Text) et animations (Pop, Punch, Shake, Breathe, Wobble, CountTo, Tween).
- `UI/Screens/*` : un module par fenêtre, interface `{ Init(), Open(args?), Close() }`,
  enregistré dans `UIRegistry.Screens[Nom]`.
- `UI/Viewport` : aperçu 3D d'un kaiju dans l'UI.
