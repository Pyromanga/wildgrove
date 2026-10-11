> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-048: Charaktererstellung — Fragenreihe → Aussehen/Charakterzüge

**Status:** Angenommen — umgesetzt (Round 105, Tutorial-Teil 1 von 2; Round
106: Multiplayer-RPC-Pfad UND Tutorial-Teil 2, siehe jeweils gleichnamige
Abschnitte unten — beide Teile jetzt vollständig)
**Datum:** 2026-08
**Kontext:** Explizite Vorgabe für den Tutorial-/Onboarding-Punkt (seit
Round 53 als fehlend dokumentiert, siehe `TODO-offene-probleme.md`
"Tutorial-/Onboarding-Struktur"): eine Fragenreihe ähnlich Animal
Crossing bestimmt beim ersten Login sowohl Aussehen als auch
Charakterzüge des Spielers; danach spawnt er in der Welt, ein NPC
erklärt kurz UI/UX. Diese Runde deckt ausschließlich den ersten Teil
(Fragenreihe → Aussehen/Charakterzüge) ab — der erklärende NPC ist
bewusst eine eigenständige Folgerunde, siehe "Bewusst nicht Teil dieser
Runde" unten.

Vor der Umsetzung wurden drei Architekturfragen geklärt (siehe Chat-
Verlauf 2026-08):
1. **Wirkung der Charakterzüge:** vorerst rein kosmetisch. Zwei
   Ausbaustufen (Flavor-Dialoge, echte Stat-Boni) sind als Spike-Punkt in
   `TODO-offene-probleme.md` vorgemerkt, noch nicht entschieden.
2. **Aussehen:** wird aus den Antworten ABGELEITET (Mehrheitsentscheid),
   nicht direkt vom Spieler gewählt. Vier grobe Presets für diese Runde,
   Feintuning (Slider) explizit vertagt.
3. **Pflicht/überspringbar:** überspringbar, mit je einem Achievement für
   Abschluss ODER Überspringen (beide Ausgänge werden gewürdigt, keiner
   bestraft).

## Entscheidung

`CharacterCreationService` (`scripts/onboarding/CharacterCreationService.gd`)
mit vier Bausteinen:

### Datenmodell

Feste, im Code hinterlegte `QUESTIONS`-Konstante (kein Resource-/Editor-
Workflow — analog `AchievementService`s `DEFAULT_DEFINITIONS` vor dessen
datengetriebener Erweiterung in Round 103). Vier Fragen, jede mit
denselben vier Archetyp-Optionen (`APPEARANCE_ARCHETYPES`: sonnig/wald/
flut/asche, je mit `trait_id` + `color`). Antworten sind
`Dictionary(question_id -> option_id)`; `on_submit_answers_confirmed()`
(aufgerufen über `request_submit_answers()`, siehe „Round 106" unten)
zählt die gewählten `preset_id`s, die Mehrheit gewinnt (Gleichstand:
stabile Dictionary-Reihenfolge, deterministisch statt zufällig — dasselbe
Antwortmuster ergibt immer dasselbe Ergebnis). Gesammelte `trait_id`s
werden dedupliziert gespeichert (`get_traits()`), aber in dieser Runde an
keiner Stelle gelesen außer vom UI-Panel selbst (siehe Punkt 1 oben).

`on_skip_creation_confirmed()` (aufgerufen über `request_skip_creation()`)
setzt einen neutralen fünften Farbton (`DEFAULT_APPEARANCE_ID =
"unbestimmt"`, Grau) statt eines der vier Archetypen — sichtbar anders,
aber nicht abwertend.

### Autorität

`on_submit_answers_confirmed()`/`on_skip_creation_confirmed()` hinter
`_require_authority()` — identisches Muster wie
`AchievementService.grant_progress()`/`_unlock()`. **Round 106:** der in
Round 105 bewusst offen gelassene RPC-Pfad für Nicht-Host-Clients ist
nachgezogen, siehe eigener Abschnitt unten.

### Persistenz

`SAVE_KEY = "character_creation"`, Save-Interface exakt nach
`StatsService`/`AchievementService`-Muster. `has_seen_creation()` ist der
zentrale Gate: true sobald `on_submit_answers_confirmed()` ODER
`on_skip_creation_confirmed()` einmal lief — verhindert, dass die
Fragenreihe bei jedem Login erneut erscheint.

### Achievement-Trigger (fünfte/sechste Quelle für `AchievementService`)

Zwei neue Definitionen: `character_creator_complete` (20 Gold),
`character_creator_skipped` (10 Gold) — bewusst BEIDE belohnt, exakt die
Vorgabe "Achievement dafür falls man es tut oder nicht tut". Entkoppelt
verdrahtet: `AchievementService` bekommt einen optionalen Dep auf
`CharacterCreationService` und hört auf dessen `character_created`/
`character_creation_skipped` — `CharacterCreationService` selbst kennt
`AchievementService` nicht, identisches Entkopplungsmuster wie die vier
bereits bestehenden Trigger-Quellen (PvP/Auktion/Meldung/Statistiken).

### UI

`scripts/onboarding/ui/` — `CharacterCreationVisuals`/`Controller`/
`Component`, programmatisch gebaut (kein `.tscn`), registriert in
`HUDBuilder.build_all()`. Vollbild-Overlay (abgedunkelter Hintergrund,
zentriertes Panel) statt eines Toggle-Panels wie Skill/Quest/Achievement
— fühlt sich bewusst wie ein blockierender Onboarding-Schritt an, nicht
wie ein optionales Menü. `CharacterCreationController.setup()` zeigt das
Overlay nur, wenn `has_seen_creation(local_player_id)` false ist;
"Überspringen" ist auf jeder Frage sichtbar.

**Aussehen-Anwendung auf den Player:** `PlayerVisuals.apply_appearance(color)`
(neue, additive Methode — `mesh.material_override` war vorher nie
gesetzt, kein bestehendes Verhalten geändert) wird sowohl beim initialen
`setup()` aufgerufen (deckt wiederkehrende Spieler ab, deren Erstellung
schon in einer früheren Sitzung abgeschlossen wurde) als auch direkt nach
Abschluss/Überspringen. Zugriff über `IUIContext.get_local_player()`
(bereits bestehende Basis-Implementierung, Gruppen-Scan nach "player").
**Bekannte, unverifizierte Lücke:** wenn der Player-Node erst NACH dem
HUD-Build spawnt, läuft der initiale Aufruf ins Leere — kein Retry, kein
Signal-Listener auf Spawn-Events. In der bisher beobachteten Boot-
Reihenfolge (Player spawnt als Teil des World-Boots vor dem HUD) tritt
das nicht auf, wurde aber mangels Editor-Zugriff nicht gegen echte
Godot-Startreihenfolge verifiziert — dieselbe strukturelle Einschränkung
wie bei jeder UI-Runde in diesem Projekt (siehe ADR-046 "Umsetzungsstand
(Round 104)").

## Round 106: Multiplayer-RPC-Pfad

Schließt exakt die in Round 105 dokumentierte Lücke: ein Nicht-Host-Client
konnte `submit_answers()`/`skip_creation()` bis dahin nicht selbst
auslösen (`_require_authority()` verweigerte den direkten Aufruf lautlos).

**Request/Confirmed-Trennung** (identisches Muster wie
`ReportService.request_submit_report()`/`on_submit_report_confirmed()`):
`submit_answers()`/`skip_creation()` heißen jetzt
`on_submit_answers_confirmed()`/`on_skip_creation_confirmed()` (reiner
Autoritäts-Pfad, unverändertes Verhalten). Neu:
`request_submit_answers()`/`request_skip_creation()` als
Client-Einstiegspunkte — ohne echten Peer oder auf dem Host läuft das
direkt in `on_*_confirmed()`, ein Nicht-Host-Client schickt stattdessen ein
RPC an die Autorität (`NetworkBridge._rpc_character_creation_submit_
answers()`/`_rpc_character_creation_skip()`).

**Rückkanal:** anders als bei `ReportService` (reine Einbahnstraße)
braucht der anfragende Client hier sein eigenes Ergebnis zurück — ohne das
bekäme er nie sein eigenes Aussehen. Die Autorität schickt nach
`on_*_confirmed()` gezielt an den betroffenen Spieler zurück
(`send_character_creation_completed_for_player()`/
`_skipped_for_player()`, überspringt den lokalen Peer — identisches
Guard-/Skip-Local-Muster wie `send_achievement_unlocked_for_player()`).
Neues Signal `character_creation_confirmed(player_id)` — bewusst NICHT
`character_created`/`character_creation_skipped` wiederverwendet, weil die
laut `AchievementService`-Klassenkommentar ("TRIGGER-QUELLEN")
nachweislich ausschließlich auf der Autorität feuern dürfen; ein Re-Emit
auf dem Client hätte dort ungewollt (wenn auch folgenlos, nur Log-Lärm)
`grant_progress()` angestoßen und die dokumentierte Invarianz gebrochen.

**Dependency-Zyklus vermieden:** `CharacterCreationService` bezog
`NetworkBridge` bis Round 105 direkt über `configure()`-Deps. Da
`NetworkBridge` jetzt umgekehrt einen optionalen Dep auf
`CharacterCreationService` braucht (für den Tier-1/Host-Fallback-Zweig der
neuen `send_*()`-Funktionen), wäre das ein echter Zyklus im
`ServiceDependencyResolver` (Kahn's Algorithmus) gewesen.
`CharacterCreationService` bezieht `NetworkBridge` jetzt stattdessen über
`inject_network_bridge()` in Phase C8 (`BootPipeline.gd`) — exakt das
Muster, das `AchievementService`/`ReportService`/`ChatService` aus
demselben Grund schon nutzen. Neuer optionaler Dep: `session_manager`
(liefert `get_local_player_id()` für den Client-Empfangspfad, identisch zu
`AchievementService` seit Round 104).

**UI-Controller:** `CharacterCreationController` ruft jetzt
`request_submit_answers()`/`request_skip_creation()` auf und hängt die
"fertig"-Logik (Aussehen anwenden, Panel schließen, Toast) an das neue
`character_creation_confirmed`-Signal statt sie synchron direkt nach dem
Service-Aufruf laufen zu lassen — funktioniert für Tier 1/Host unverändert
(Signal feuert noch synchron im selben Aufruf), deckt aber jetzt auch den
asynchronen Nicht-Host-Client-Pfad ab. Filtert auf die lokale player_id,
weil die Autorität dasselbe Signal auch für ANDERE Spieler emittiert.

**Bewusst weiterhin nicht Teil dieser Runde:** kein Broadcast des
Aussehens an andere Peers — der neue Rückkanal informiert ausschließlich
den betroffenen Spieler selbst, andere Clients sähen die farbige Anwendung
auf einem entfernten Player-Mesh weiterhin nicht (eigene, noch offene
Lücke, siehe `CharacterCreationService.gd`-Klassenkommentar).

## Round 106: Tutorial-Teil 2 (erklärender NPC)

Schließt den zweiten, in Round 105 bewusst vertagten Teil der ursprünglichen
Vorgabe ("Fragenreihe bestimmt Aussehen + Charakterzüge, danach Spawn in
der Welt + erklärender NPC"): `TutorialGuideNPC`
(`scripts/onboarding/TutorialGuideNPC.gd`) — ein stationärer NPC nahe dem
Player-Spawnpunkt (`WorldSpawner.gd`: `Vector3(-3.0, ..., 3.0)`, bewusst
näher am Spawn als die "Handelsstraße" bei x=8..20, auf der Quest-/Shop-/
Bank-/Auktionshaus-NPC stehen), der bei jedem Gespräch einen von sieben
UI/UX-Tipps zeigt (Bewegung, Interaktion, Inventar, Skills, Quests,
Errungenschaften, die übrigen NPCs) — ein Tipp pro Gespräch, danach von
vorn (`TutorialGuideDialogController`, `scripts/onboarding/ui/`).

**Struktur:** exakt das etablierte NPC-Koordinator-Muster
(`QuestNPC`/`ShopNPC`/`BankNPC`/`AuctionHouseNPC`) — delegiert Visuals an
`NPCVisualBuilder` (identisches Aussehen wie alle anderen NPCs, keine
eigene Optik), Dialog-Logik an `TutorialGuideDialogController` (analog
`QuestNPCDialogController`, aber ohne Quest-State-Machine, nur ein Zähler
durch eine feste Tipp-Liste). Neuer Entity-Typ `tutorial_guide_npc` in
`WorldEntityRegistry.gd` registriert, Spawn-Aufruf in `WorldSpawner.gd`
neben den vier bestehenden NPC-Spawns.

**Bewusst schlanker als `QuestNPC`:** kein `NetworkBridge`-Dep (nichts, was
serverseitig getrackt werden müsste — reiner Anzeigetext, kein
Quest-Objective), kein Autoritäts-Guard in `_on_interacted()` (anders als
`QuestNPC`s BUG-26-Fix — hier gibt es kein doppelt zählbares Server-Event).
Kein Fortschritts-Tracking pro Spieler, ob der Guide schon gesprochen
wurde — die Tipps sind bewusst wiederholbar (kein einmaliges Gate wie
`CharacterCreationService.has_seen_creation()`), sodass ein Spieler
jederzeit erneut vorbeischauen kann.

**Bewusst weiterhin nicht Teil dieser Runde:** kein automatisches
Ansprechen direkt nach dem Spawn (kein erzwungener Dialog-Popup, keine
Lauf-zum-Spieler-Logik) — der NPC steht sichtbar in der Nähe, Interaktion
bleibt wie bei jedem anderen NPC freiwillig über `InteractableComponent`.
Details siehe `TutorialGuideNPC.gd`-Klassenkommentar.

## Tests

`tests/unit/test_character_creation_service.gd` (18 Tests aus Round 105 +
10 neue Tests in Round 106 — Netzwerk-Pfad via `SpyNetworkBridge` analog
`test_report_service.gd`, Autoritäts-Guard für beide `on_*_confirmed()`-
Einstiegspunkte, gezielte Rückkanal-Zustellung, `character_creation_
confirmed`-Emission, Client-Empfang via `StubSessionManager` analog
`test_achievement_service.gd`).
`tests/unit/test_character_creation_controller.gd` (13 Tests aus Round 105
+ 2 neue Tests in Round 106 — player_id-Filter auf
`character_creation_confirmed`). `test_player_visuals.gd`
(2 Tests für `apply_appearance()`). Plus 5 Tests in
`test_achievement_service.gd` für die beiden Trigger (Round 105,
unverändert — `character_created`/`character_creation_skipped` feuern
weiterhin ausschließlich innerhalb von `on_*_confirmed()`, siehe "Round
106"). `tests/unit/test_tutorial_guide_dialog_controller.gd` (neu, 10
Tests — Tipp-Reihenfolge, Abschlusszeile, Reset, Bus-Integration, analog
`test_quest_npc_dialog_controller.gd`). `tests/unit/test_world_spawner.gd`
(+2 — `tutorial_guide_npc` im Tier-3-Pfad und im normalen Spawn-Pfad neben
den übrigen vier NPCs). Kein eigener Koordinator-Test für
`TutorialGuideNPC` selbst — identisches Muster wie `BankNPC`/`ShopNPC`/
`AuctionHouseNPC`, die ebenfalls keinen eigenen Koordinator-Test haben
(nur `QuestNPC`, der komplexeste der fünf NPCs, hat einen — die
interessante Logik steckt jeweils im Dialog-/State-Controller, der
eigenständig getestet ist).

## Bewusst nicht Teil dieser Runde

- **Feintuning-Editor** (Farbwähler/Slider über die vier Presets hinaus).
- **Gameplay-Wirkung der Charakterzüge** (Stat-Boni oder Dialog-Flavor) —
  siehe Kontext-Absatz, als Spike vorgemerkt.
- **Erneutes Durchlaufen/Zurücksetzen der Erstellung** nach Abschluss
  (kein "Charakter neu erstellen"-Knopf).
- **Automatisches Ansprechen durch den Tutorial-Guide-NPC** — siehe "Round
  106: Tutorial-Teil 2".

## Round 114 (Nachtrag): Broadcast des Aussehens an andere Peers

Die Runde-106-Lücke ("Broadcast des Aussehens an andere Peers" — der
Multiplayer-RPC-Pfad informierte bis dahin ausschließlich den betroffenen
Spieler selbst über sein eigenes Ergebnis) ist geschlossen. Zwei
sich ergänzende Pfade:

1. **Spawn-Payload**: `NetworkBridge._register_and_broadcast_player_spawn()`
   schickt `CharacterCreationService.get_look(player_id)` jetzt direkt im
   Spawn-Payload eines Player-Entities mit (`_rpc_spawn_remote_player()` →
   `Player.on_spawn()`) — deckt neu beigetretene UND spät beitretende Peers ab.
2. **Live-Broadcast**: ändert sich der Look eines bereits gespawnten Spielers
   (Fragenreihe, Überspringen, Aussehens-Editor), sendet
   `CharacterCreationService._broadcast_look()` ihn über den bestehenden
   ADR-042-Kanal (`NetworkBridge.broadcast_to_all_peers()`, kind
   `"character_look"`) an jeden aktuell verbundenen Peer.

Beide Pfade wenden den Look über `PlayerVisuals` an, aufgelöst über einen
neu injizierten `WorldService` (`CharacterCreationService.
inject_world_service()`, analog `EquipmentService.inject_world_service()`
aus ADR-027) — player_id → peer_id über
`NetworkBridge.get_peer_id_for_player()`.

