> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-015: Lokale Spieler-Identität & Per-Player Interaction State

**Status:** Vollständig umgesetzt (Runde 6) — Phasen 1–6 fertig.
**Datum:** 2026-07
**Kontext:** Betrifft `InteractionExecutor`, `InteractableComponent`, `IEntityContext`,
`IUIContext`, alle UI-Controller die aktuell `get_nodes_in_group("player")` nutzen,
sowie `AnimalCatcher`/`PetComponent` (Owner-Zuordnung, siehe dortige Code-Kommentare).
Ergänzt [ADR-010](010-multiplayer-authority-tiers.md) / [MIGRATION-010](../MIGRATION-010.md).

**Umsetzungsstand (siehe [MIGRATION-015](../MIGRATION-015.md) für Details):**
- ✅ Phase 1: `get_local_peer_id()`/`get_local_player()` auf `IEntityContext`/`IUIContext`,
  produktiv über `SessionManager.get_local_peer_id()` aufgelöst.
- ✅ Phase 2: Alle sechs UI-seitigen `get_nodes_in_group("player")[0]`-Stellen
  (InventoryUIController, EquipmentUIController, PlayerHPController,
  InteractionButtonController, ContextMenuController, JumpButtonController)
  ersetzt. `EnemyNPC`/`AnimalBase` bewusst NICHT angefasst — dort ist "nächster
  Spieler" die richtige Semantik, nicht "lokaler Spieler" (EnemyNPC hatte das
  bereits korrekt; AnimalBase hat einen benannten, nicht behobenen Folge-Bug).
- ✅ Phase 3: `InteractionExecutor` hält State jetzt in `_active: Dictionary`
  pro `player_id` statt global. `InteractableAction.player_id` neu, gesetzt von
  `Player.get_context_actions()`. `movement_interrupted` trägt jetzt `player_id`.
- ✅ Phase 4: `InteractableComponent.interacted`-Signal um `player_id` erweitert
  (`interacted(action_id: String, player_id: int)`, kein Default — Pflichtparameter).
  Alle vier tatsächlichen Consumer umgestellt (Neugrep fand einen vierten,
  `EnemyNPC` via `EnemyAttack.gd`, den der ursprüngliche Report nicht hatte):
  `QuestNPC`, `HarvestableEntity`, `AnimalBase` (nutzt den Wert), `EnemyNPC`
  (nimmt ihn entgegen, nutzt ihn noch nicht — siehe dortiger Kommentar zu
  `CombatSystem.player_melee_damage()`, separates Thema).
- ✅ Phase 5: `AnimalCatcher.catch_animal()` nimmt `player_id` jetzt als
  Pflichtparameter vom Aufrufer entgegen statt ihn über
  `animal.get_multiplayer().get_unique_id()` zu erraten. Whitelist-Eintrag in
  `test_identity_access_boundary.gd` entfernt (Aufruf existiert nicht mehr —
  kein toter Whitelist-Rest).
- ✅ Phase 6: Regressionstests (`test_interaction_executor.gd` erweitert,
  `test_local_player_access_boundary.gd` neu, `test_animal_catcher.gd` neu für
  Phase 4/5).

---

## Problem

MIGRATION-010 Phase 1 wurde als ✅ abgeschlossen markiert: `InventorySystem`,
`PlayerStateService`, `EquipmentService`, `QuestService`, `SkillSystem`, `CombatSystem`
trennen ihren State per `player_id`/`peer_id`. Das stimmt — aber die Liste ist nicht
vollständig, und die Lücke ist genau der Service, über den *jede* Sammel-/Abbau-/
Fang-Interaktion im Spiel läuft:

**1. `InteractionExecutor` hält globalen Singleton-State statt Per-Player-State.**

`scripts/interaction/InteractionExecutor.gd:20-21`:
```gdscript
var _active_action: InteractableAction = null
var _active_tween:  Tween              = null
```
Kein `{ player_id: ... }`-Dictionary wie bei den fünf oben genannten Services.
`execute_action()` (`InteractionExecutor.gd:33`) prüft `_player_states.is_free()` /
`_player_states.set_state(BUSY)` (`InteractionExecutor.gd:34,39`) ohne `player_id`-Argument
— beide Aufrufe fallen auf den Default `player_id: int = 1` zurück
(`PlayerStateService.gd:58,77`). `PlayerStateService` selbst ist bereits multi-tenant
(`_current: Dictionary`, `PlayerStateService.gd:15`) — der darunterliegende Service kann
es, der Aufrufer nutzt es nicht.

**Konkreter Effekt:** Spieler A startet eine Interaktion (Baum fällen, Erz abbauen,
Tier fangen) → `_active_action` ist global gesetzt → Spieler B's `execute_action()`
gibt sofort ab (`InteractionExecutor.gd:35-37`), unabhängig davon, womit B interagieren
wollte. Das ist keine Kantensituation, das ist der Standardfall, sobald zwei Spieler
gleichzeitig irgendetwas tun.

**2. Es gibt keinen Begriff "mein lokaler Spieler" — nur "Index 0 in der Gruppe".**

Zehn Dateien holen sich den Spieler so:
```gdscript
var players := get_tree().get_nodes_in_group("player")
var player: Node3D = players[0]
```
Fundstellen: `InteractionButtonController.gd:26-27`, `ContextMenuController.gd`,
`EquipmentUIController.gd`, `InventoryUIController.gd:78-84` (Funktion heißt
`_find_local_player_visuals()` — der Name verspricht eine Korrektheit, die die
Implementierung nicht hat, siehe Zitat unten), `PlayerHPController.gd`,
`JumpButtonController.gd`, `EnemyNPC.gd`, `AnimalBase.gd`, `PetComponent.gd`.

`InventoryUIController.gd:78-79`:
```gdscript
func _find_local_player_visuals() -> PlayerVisuals:
    var players: Array = Engine.get_main_loop().get_nodes_in_group("player") if Engine.get_main_loop() else []
```
— trotz des Namens exakt dasselbe Muster wie überall sonst. Das ist der Beweis, dass das
Team "lokaler Spieler" bereits für ein gelöstes Problem hielt, es aber nie war.

**Warum das erst bei echtem Multiplayer auffällt:** Solange nur ein `Player`-Node
existiert (Tier 1, Solo), ist `players[0]` immer richtig — Zufallstreffer, kein Beweis.
Sobald ein zweiter `Player`-Node über `MultiplayerSpawner` auf demselben Client
repliziert wird (Tier 2), hängt die Korrektheit von `players[0]` von der
Spawn-Reihenfolge ab. Das kann so weit gehen, dass Spieler B's UI-Button
Spieler A's Charakter fernsteuert, wenn A's Node zuerst in der Gruppe registriert wurde.

**3. `InteractableComponent.interacted(action_id: String)` trägt keine Spieler-Identität.**

`scripts/interaction/InteractableComponent.gd:29`. Verbindet sich mit `HarvestableEntity`,
`QuestNPC`, `AnimalBase` — keine dieser drei Entities kann heute wissen, *wer* die
Interaktion abgeschlossen hat. Für `AnimalCatcher` haben wir das (Session-Fix zuvor)
mit `animal.get_multiplayer().get_unique_id()` überbrückt — eine funktionierende
Näherung für den aktuellen Single-Executor-Fall, aber keine echte Lösung, weil sie auf
genau der Fehlannahme aufbaut, die dieses ADR beheben soll (siehe Migrationsplan, Phase 3).

**Zusammenhang mit MIGRATION-010:** Punkt 1 ist eine Lücke in einer bereits
"abgeschlossen" markierten Phase — kein neuer Scope, sondern ein Nacharbeiten. Punkt 2/3
sind neuer Scope, den ADR-010 nie abgedeckt hat (ADR-010 behandelt Service-State,
nicht UI-/Entity-seitige Spieler-Referenzierung).

---

## Optionen

### Option A: Nur `InteractionExecutor` fixen, `players[0]`-Stellen unangetastet lassen

Per-Player-Dictionary in `InteractionExecutor`, `player_id` kommt weiterhin aus
`get_nodes_in_group("player")[0]` an den bestehenden zehn Stellen.

- ✅ Behebt den schlimmsten Fall (Spieler blockieren sich gegenseitig) mit kleinem Diff
- ❌ Löst nicht, *woher* `player_id` überhaupt kommt — der eigentliche Bug (falscher
  Spieler wird angesteuert) bleibt bestehen, nur die Blockade ist weg
- ❌ Nächster Report in einem Jahr findet dasselbe Muster wieder, an einer elften Stelle

### Option B: Zentraler `get_local_peer_id()`/`get_local_player()`-Helper auf `IEntityContext`/`IUIContext`, plus `InteractionExecutor`-Fix

Ein Accessor, konsequent überall eingesetzt, ersetzt alle zehn `players[0]`-Stellen.
`multiplayer.get_unique_id()` ist bereits die korrekte Godot-Primitive dafür — sie wird
nur nirgends zentral bereitgestellt, sondern an jeder Stelle neu (und falsch) nachgebaut.

> **Korrektur 2026-07:** `NetworkBridge.gd:119` hat diese Primitive bereits als
> `get_local_peer_id()` gekapselt (`return multiplayer.get_unique_id() if _has_peer() else 1`).
> `IEntityContext`/`IUIContext` sollten also nicht `multiplayer.get_unique_id()` ein
> zweites Mal direkt implementieren, sondern an `NetworkBridge.get_local_peer_id()`
> **delegieren**. Sonst entstehen zwei unabhängige Quellen für dieselbe Information mit
> potenziell unterschiedlichem Tier-1-Fallback-Verhalten — genau das Muster ("dieselbe
> Annahme an zwei Stellen neu gebaut"), das dieses ADR eigentlich beheben soll.

- ✅ Ein Fix, eine Fundstelle für die Korrektheit — nicht zehn Kopien derselben Annahme
- ✅ Nutzt bestehende Godot-Primitives (`multiplayer.get_unique_id()`,
  `get_multiplayer_authority()`), keine neue Infrastruktur
- ✅ Fügt sich in das bestehende Context-Pattern ein (`IEntityContext`/`IUIContext` sind
  exakt dafür gebaut — schmale Fassade statt AutoLoad/Gruppen-Scan)
- ⚠️ Berührt zehn Call-Sites plus zwei Interfaces — größerer, aber mechanischer Diff
- ⚠️ `interacted`-Signal-Signatur ändert sich (`action_id` → `action_id, player_id`) —
  drei Consumer (`HarvestableEntity`, `QuestNPC`, `AnimalBase`) müssen mitgezogen werden

### Option C: Vollständige RPC-Verdrahtung (MIGRATION-010 Phase 4) gleich mit erledigen

Zusätzlich zu Option B: `request_*()`/`on_*_confirmed()` direkt gegen `rpc_id()`
verdrahten, wie in MIGRATION-010 Phase 4 skizziert.

- ✅ Würde "echten Multiplayer" tatsächlich fertigstellen, nicht nur diesen Ausschnitt
- ❌ Vermischt zwei unabhängige Probleme in einem Schnitt (Spieler-Identität vs.
  Netzwerk-Transport) — bei einem Fehler ist nicht klar, welcher Teil ihn verursacht hat
- ❌ Kann ohne laufendes Multiplayer-Setup zum Testen hier nicht verantwortbar in einem
  Zug umgesetzt werden

---

## Entscheidung

**Empfehlung: Option B**, als eigener, in sich abgeschlossener Schritt — unabhängig von
MIGRATION-010 Phase 4 (RPC-Verdrahtung), die danach auf einem korrekten
Spieler-Identitäts-Fundament aufbauen kann statt gleichzeitig damit zu entstehen.

**Das ist noch keine verbindliche Festlegung** — konkret zu klären, bevor Migration
losläuft (siehe [MIGRATION-015](../MIGRATION-015.md), Abschnitt "Offene Fragen"):

- Reicht `get_local_peer_id() -> int` auf `IEntityContext`/`IUIContext`, oder braucht es
  zusätzlich `get_local_player() -> Node3D` als Bequemlichkeits-Wrapper?
- Wird `InteractableAction` um ein `player_id`-Feld erweitert (gesetzt beim Bau der
  Action in `InteractableComponent.get_actions()`), oder wird `player_id` separat durch
  `execute_action()` durchgereicht?
- Bricht die `interacted`-Signal-Signaturänderung etwas außerhalb der drei bekannten
  Consumer? (Grep-Ergebnis in MIGRATION-015 ist vollständig, aber neue Entity-Typen
  könnten seither dazugekommen sein.)

---

## Konsequenzen

### Positiv
- Schließt die einzige verbliebene Lücke in der als abgeschlossen markierten
  MIGRATION-010-Phase-1 — Multi-Tenanz der Session-Services ist danach tatsächlich
  vollständig, nicht nur "bis auf einen Service".
- Ersetzt zehn unabhängige (und mindestens eine bereits falsch benannte) Kopien
  derselben Annahme durch eine einzige, korrekte Quelle.
- MIGRATION-010 Phase 4 (RPC-Verdrahtung) bekommt ein sauberes Fundament: `player_id`
  ist ab dann durchgängig korrekt, RPC-Handler müssen es nicht zusätzlich raten.

### Negativ / Risiken
- Signatur-Änderung an einem öffentlichen Signal (`interacted`) — Compile-Zeit-Fehler
  sind wahrscheinlich, falls ein Consumer beim Umbau übersehen wird; GDScript prüft
  Signal-Handler-Arität nicht immer streng zur Compile-Zeit.
- Kein laufendes Godot/Multiplayer-Setup hier zum Verifizieren — die Migration sollte in
  einem Schritt passieren, der lokal (Tier 1) UND mit zwei verbundenen Clients (Tier 2)
  getestet wird, bevor sie als abgeschlossen gilt.

### Mitigationen
- Migration in der in MIGRATION-015 beschriebenen Reihenfolge (Interfaces zuerst, dann
  ein Call-Site nach dem anderen, mit Zwischenstand kompilierbar) statt eines einzigen
  großen Patches.
- `test_event_bus_access_boundary.gd`-artiger Architektur-Test wäre ein sinnvoller
  Folge-Schritt: ein Scan-Test, der `get_nodes_in_group("player")` außerhalb einer
  Whitelist verbietet, analog zum bestehenden EventBus-Boundary-Test. Verhindert, dass
  das Muster nach der Migration an Stelle elf wieder auftaucht.

---

## Ablösung

Ergänzt ADR-010, löst nichts ab. Wird selbst hinfällig, falls Godots `MultiplayerAPI`
in einer künftigen Version einen eingebauten "lokaler Peer"-Node-Accessor liefert, der
den hier vorgeschlagenen Wrapper überflüssig macht.
