# MIGRATION-015 — Lokale Spieler-Identität & Per-Player Interaction State

**Referenz:** [ADR-015](adr/015-local-player-identity.md)
**Ziel:** `InteractionExecutor` auf Per-Player-State umstellen; einen zentralen
"lokaler Spieler"-Accessor einführen und alle zehn `get_nodes_in_group("player")[0]`-
Stellen darauf umstellen; `interacted`-Signal um `player_id` erweitern.

**Status:** Runde 6 — Phasen 1–6 vollständig umgesetzt. Dieses Dokument
dokumentiert jetzt den abgeschlossenen Stand.

---

## Gesamtstatus

| Phase | Beschreibung | Status |
|-------|-------------|--------|
| 0 | Offene Fragen klären (siehe unten) | ✅ Entschieden (Option B / "beide" / Feld / Signal-Erweiterung) |
| 1 | `get_local_peer_id()` auf `IEntityContext`/`IUIContext` | ✅ Umgesetzt |
| 2 | Sechs `players[0]`-Stellen auf den Accessor umstellen | ✅ Umgesetzt (EnemyNPC/AnimalBase bewusst ausgenommen, siehe unten) |
| 3 | `InteractionExecutor` auf Per-Player-State umstellen | ✅ Umgesetzt |
| 4 | `interacted`-Signal um `player_id` erweitern (+ 4 Consumer) | ✅ Umgesetzt (Runde 6) |
| 5 | `AnimalCatcher` von der Näherungslösung auf den echten Accessor umstellen | ✅ Umgesetzt (Runde 6) |
| 6 | Architektur-Test gegen Regressionen (analog EventBus-Boundary-Test) | ✅ Umgesetzt |

**Korrektur zu Phase 2:** Die ursprüngliche Zählung "zehn Stellen" umfasste auch
`EnemyNPC._find_closest_player()` — bei genauerer Prüfung implementiert diese
bereits korrekt eine räumliche Nächster-Spieler-Suche, kein `players[0]`. Real
umgestellt wurden sechs Stellen (Inventory-, Equipment-, PlayerHP-, Interaction-
Button-, ContextMenu-, JumpButton-Controller). `AnimalBase._ready()`/
`_check_player_proximity()` nutzen weiterhin `players[0]` für Flucht-Verhalten —
das braucht "nächster Spieler", nicht "lokaler Spieler", und ist ein benannter,
nicht in dieser Runde behobener Folge-Bug (kein Regressions-Risiko durch diese
Migration, aber auch keine neue Korrektheit).

Reihenfolge ist absichtlich so gewählt, dass nach jeder Phase kompiliert und lokal
(Tier 1) getestet werden kann — keine Phase hinterlässt einen halb-funktionierenden
Zwischenzustand.

---

## Phase 0 — Offene Fragen (vor Implementierung zu klären)

1. **Reicht `get_local_peer_id() -> int`, oder zusätzlich `get_local_player() -> Node3D`?**
   Ersteres ist die minimale Primitive (`multiplayer.get_unique_id()`); Letzteres spart
   den `for`-Loop über die Gruppe an jeder Call-Site, kostet aber eine zweite Methode
   auf beiden Interfaces. Vorschlag: beide — `get_local_player()` baut intern auf
   `get_local_peer_id()` + der bereits in `PetComponent._find_owner()` etablierten
   Authority-Match-Logik auf (`scripts/world/pets/PetComponent.gd:88-95`, dort schon
   für den Owner-Fall gelöst).
2. **`InteractableAction.player_id` als Feld, oder Parameter durch `execute_action()`
   durchreichen?** Feld ist konsistenter mit den bestehenden Feldern auf
   `InteractableAction` (`xp_type`, `loot_table`, etc.) und vermeidet eine
   Signaturänderung an `execute_action()` selbst, die auch von
   `UIEvents.interaction_execute_requested(action)` transportiert wird (ein Signal mit
   einem Parameter zu erweitern heißt, auch dort die Emit-Stelle anzupassen). Vorschlag:
   Feld auf `InteractableAction`.
3. **Vollständigkeit des Consumer-Greps.** Vor Phase 4 erneut grep'en (Codebasis kann
   sich seit Report-Erstellung geändert haben):
   `grep -rn "\.interacted\.connect" scripts/`.
4. **Wird `_is_player_target()` in `InteractableComponent.gd` (aktuell ein
   Closest-Interactable-Heuristik-Workaround für die 3D-Fortschrittsbar-Sichtbarkeit,
   `InteractableComponent.gd` Kommentar bei `_is_player_target()`) durch echten
   `player_id`-Vergleich ersetzt, sobald der verfügbar ist?** Wäre eine Vereinfachung,
   ist aber nicht zwingend Teil dieser Migration — separat entscheiden, sonst wächst der
   Scope.

**Diese Fragen werden hier nicht beantwortet — das ist absichtlich.** Antworten kommen
vom Repo-Owner, nicht vom Reviewer.

---

## Phase 1 — `get_local_peer_id()` / `get_local_player()`

**Ziel:** Eine einzige, korrekte Quelle für "wer bin ich lokal" statt zehn Kopien.

| Datei | Änderung |
|-------|----------|
| `scripts/interfaces/core/IEntityContext.gd` | `func get_local_peer_id() -> int: return 1` (Default-Impl, analog zu allen anderen `get_*()`-Methoden dort) |
| `scripts/interfaces/core/IUIContext.gd` | dieselbe Methode, dieselbe Begründung |
| `scripts/core/entity/EntityContext.gd` (Produktions-Implementierung) | `return NetworkBridge.get_local_peer_id()` — **nicht** `multiplayer.get_unique_id()` erneut direkt aufrufen (siehe Korrektur unten) |
| `scripts/ui/...` (Produktions-Implementierung von `IUIContext`, Name im Code prüfen — nicht in diesem Report verifiziert) | dieselbe Delegation an `NetworkBridge.get_local_peer_id()` |
| Test-Mocks (`MockEntityContext`, `MockUIContext` falls vorhanden) | `return 1` (fester Wert reicht für Tier-1-Tests) |

> **Korrektur 2026-07:** `NetworkBridge.gd:119` implementiert `get_local_peer_id()`
> bereits (`return multiplayer.get_unique_id() if _has_peer() else 1`). Die
> Produktions-Implementierungen von `IEntityContext`/`IUIContext` sollten dahin
> **delegieren** statt `multiplayer.get_unique_id()` selbst ein zweites Mal
> nachzubauen — sonst gibt es zwei unabhängige Implementierungen derselben Primitive,
> die bei einem künftigen Fix nur an einer Stelle geändert werden könnten (z. B. der
> `_has_peer()`-Fallback auf `1`). `NetworkBridge` muss dafür für `EntityContext`/den
> `IUIContext`-Produktionscode erreichbar sein (DI-Weg prüfen, analog zu anderen
> Services, die `_network` bereits per `ServiceDeps` injiziert bekommen, z. B.
> `InventorySystem.gd`).

`get_local_player() -> Node3D` (falls Phase-0-Frage 1 mit "beide" beantwortet wird):
```gdscript
func get_local_player() -> Node3D:
    var my_id := get_local_peer_id()
    for p in Engine.get_main_loop().get_nodes_in_group("player"):
        if p is Node3D and p.get_multiplayer_authority() == my_id:
            return p as Node3D
    return null
```
Identisches Muster zu `PetComponent._find_owner()` — kein neues Konzept, nur zentralisiert.

**Verifikation:** Kompiliert, keine Verhaltensänderung (noch nichts nutzt die neue
Methode). Bestehende Tests müssen unverändert grün bleiben.

---

## Phase 2 — Zehn Call-Sites umstellen

| Datei | Aktuelles Muster | Ersetzen durch |
|-------|-------------------|-----------------|
| `scripts/ui/controllers/InteractionButtonController.gd:26-27` | `players[0]` | `_ctx.get_local_player()` |
| `scripts/ui/controllers/ContextMenuController.gd` | `players[0]` | `_ctx.get_local_player()` |
| `scripts/ui/controllers/EquipmentUIController.gd` | `players[0]` | `_ctx.get_local_player()` |
| `scripts/ui/controllers/InventoryUIController.gd:78-84` | `_find_local_player_visuals()` (falscher Name, richtiges Ziel) | Funktion umbenennen bleibt, Body auf `_ctx.get_local_player()` umstellen |
| `scripts/ui/controllers/PlayerHPController.gd` | `players[0]` | `_ctx.get_local_player()` |
| `scripts/ui/controllers/JumpButtonController.gd` | `players[0]` | `_ctx.get_local_player()` |
| `scripts/world/combat/EnemyNPC.gd` | `players[0]` (Ziel-Auswahl für Aggro/Angriff) | **Vorsicht:** hier ist "der Spieler" evtl. bewusst "der nächste Spieler", nicht "der lokale" — vor dem Umstellen den Verwendungszweck einzeln prüfen, nicht blind ersetzen |
| `scripts/world/animals/AnimalBase.gd` | `players[0]` (Flucht-Verhalten) | dieselbe Vorsicht wie EnemyNPC — Fluchtziel ist "nächster Spieler", nicht zwingend "lokaler" |
| `scripts/world/pets/PetComponent.gd` | bereits `_find_owner()` mit Authority-Match (aus vorherigem Fix) | kein Handlungsbedarf, dient als Referenzimplementierung für Phase 1 |

**Wichtige Unterscheidung, die beim Umsetzen nicht verloren gehen darf:** "lokaler
Spieler" (wer bin *ich*, für UI-Controller relevant) ist etwas anderes als "nächster
Spieler" (wer ist *räumlich am nächsten*, für Gegner-KI/Flucht-Verhalten relevant).
`EnemyNPC` und `AnimalBase` brauchen wahrscheinlich weiterhin eine Nächster-Spieler-Suche
— nur eben nicht `players[0]` als Krücke dafür, sondern eine echte Abstandsberechnung
über alle Spieler in der Gruppe. Das ist streng genommen ein drittes, separates Problem
und wird hier nur benannt, nicht gelöst — sonst wächst Phase 2 über ihr eigentliches Ziel hinaus.

**Verifikation:** Tier 1 (ein Spieler) — Verhalten unverändert. Tier 2 (zwei Clients,
falls testbar) — jeder Client steuert nachweislich nur seinen eigenen Charakter über UI.

---

## Phase 3 — `InteractionExecutor` Per-Player-State

`scripts/interaction/InteractionExecutor.gd`:

| Vorher | Nachher |
|--------|---------|
| `var _active_action: InteractableAction = null` | `var _active: Dictionary = {}  # { player_id: {action, tween} }` |
| `var _active_tween: Tween = null` | (in `_active` integriert) |
| `execute_action(action)` | `execute_action(action)` — `player_id` kommt aus `action.player_id` (Phase-0-Entscheidung) |
| `_player_states.is_free()` | `_player_states.is_free(action.player_id)` |
| `_player_states.set_state(BUSY)` | `_player_states.set_state(BUSY, action.player_id)` |
| `cancel_interaction()` | braucht `player_id`-Parameter — Aufrufer (`_bus.player().movement_interrupted`) muss ihn mitliefern; falls das Signal aktuell keinen `player_id` trägt, ist das ein weiterer Konsumenten-Kreis, siehe Phase-0-Frage 3 sinngemäß auch hier |
| `_on_tween_finished()` | muss wissen, für welchen `player_id` der Tween fertig ist — Closure-Capture beim Tween-Setup (`player_id` als lokale Variable im Tween-Callback capturen, analog zum bestehenden Lambda-Capture-Bugfix in `InteractableComponent.gd` bei `_on_interaction_started`) |

**Risiko hier am höchsten:** `cancel_interaction()` wird aktuell von genau einem Signal
ausgelöst (`movement_interrupted`) das selbst möglicherweise noch keine `player_id`
trägt. Vor Phase 3 prüfen: `grep -n "movement_interrupted" scripts/events/PlayerEvents.gd`
und alle Emit-Stellen.

**Verifikation:** Tier 1 unverändert. Tier 2: zwei Clients starten gleichzeitig je eine
Interaktion an unterschiedlichen Objekten — beide laufen unabhängig durch, keine
gegenseitige Blockade mehr.

---

## Phase 4 — `interacted`-Signal erweitern ✅ Umgesetzt

`scripts/interaction/InteractableComponent.gd`:
```gdscript
signal interacted(action_id: String, player_id: int)
```

**Abweichung vom ursprünglichen Plan (bewusst, siehe Nutzer-Vorgabe "keine
praktischen Workarounds"):** `player_id` ist ein **Pflichtparameter, kein
`= 1`-Default** — weder auf dem Signal noch auf `_handle_completion()`. Ein
Default hätte jede Call-Site (inkl. Tests) weiter kompilieren lassen, ohne
dass sie sich bewusst mit "welcher player_id gilt hier eigentlich" auseinandersetzen
muss — genau die Art von stillem Fallback, die diese Migration eigentlich
beseitigen soll. `_on_interacted()`-Handler, die den Wert nicht brauchen,
markieren ihn stattdessen explizit als ungenutzt (`_player_id`-Konvention,
siehe `AnimalBase.on_spawn(_cfg, ...)` als bestehendes Beispiel dieses Musters).

`_handle_completion()` (`InteractableComponent.gd`) nimmt `player_id: int` jetzt
als Pflichtparameter entgegen und emittiert `interacted.emit(data.id, player_id)`.
`InteractionExecutor._on_tween_finished()` reicht ihn durch: `completed.on_complete.call(player_id)`.
Die `inspect`-Action (`get_actions()`) bekommt denselben Parameter, ungenutzt
(`func(_player_id: int) -> void: ...`) — GDScript lässt einen mit weniger
Positional-Args deklarierten Callable nicht mit mehr Args aufrufen, daher
musste auch dieser Callable die neue Arität mittragen.

**Consumer, tatsächlich umgestellt (Neugrep vor Umsetzung, wie in Phase 0
Frage 3 gefordert — `grep -rn "\.interacted\.connect\|_on_interacted" scripts/`
fand einen vierten Consumer, den der ursprüngliche ADR-015-Report nicht kannte):**

| Datei | `player_id` genutzt? | Begründung |
|-------|---------------------|------------|
| `scripts/progression/quests/QuestNPC.gd` (`_on_interacted`) | ungenutzt (`_player_id`) | Dialogzustand ist heute nicht per-player (ein globaler `_dialog`-State pro NPC-Instanz) |
| `scripts/world/objects/HarvestableEntity.gd` (`_on_interacted`) | ungenutzt (`_player_id`) | Despawn ist nicht per-player — das Objekt verschwindet für alle |
| `scripts/entities/animals/AnimalBase.gd` (`_on_interacted`) | **genutzt** | an `AnimalCatcher.catch_animal(self, player_id)` weitergereicht — Grundlage für Phase 5 |
| `scripts/entities/combat/EnemyNPC.gd` (`_on_interacted`, verdrahtet über `EnemyAttack.gd`) | ungenutzt (`_player_id`) | `CombatSystem.player_melee_damage()` nimmt aktuell einen hartcodierten String `"player"` entgegen, keine echte peer_id — Umbau davon ist MIGRATION-010 Phase 4 (RPC-Verdrahtung), bewusst nicht hier mitgelöst, um den Scope nicht zu vermischen |

**Verifikation:** Alle vier Dateien + `InteractionExecutor` kompilieren mit der
neuen Signatur. Bestehende Tests, die `_on_interacted()` direkt aufrufen
(`test_quest_npc.gd`, `test_harvestable_entity.gd`), wurden auf die neue Arität
umgestellt (expliziter `player_id`-Wert, kein Weglassen des Arguments). Neuer
Test `test_completion_passes_player_id_to_on_complete()` in
`test_interaction_executor.gd` verifiziert, dass der tatsächlich an der Aktion
hängende `player_id` (nicht irgendein Wert) am `on_complete`-Callback ankommt.

---

## Phase 5 — `AnimalCatcher` auf den echten Accessor umstellen ✅ Umgesetzt

`scripts/entities/animals/pets/AnimalCatcher.gd`:
```gdscript
static func catch_animal(animal: AnimalBase, player_id: int) -> PetComponent:
    ...
    var owner_peer_id := player_id
```
Ersetzt die vorherige Näherung `animal.get_multiplayer().get_unique_id()` — auch
hier **kein Default**, `player_id` ist Pflichtparameter. Der einzige Aufrufer
(`AnimalBase._on_interacted()`) liefert ihn seit Phase 4 aus dem echten
`interacted`-Signal.

**Das ist der Beweis, dass Phase 1-4 tatsächlich etwas lösen**, nicht nur Code
verschieben: die Näherung in `AnimalCatcher` verschwindet ersatzlos, sie wird nicht durch
eine andere Näherung ersetzt.

**Aufräumen als Teil dieser Phase:** `tests/unit/test_identity_access_boundary.gd`
hatte `AnimalCatcher.gd` auf der Whitelist für legitime direkte
`multiplayer.get_unique_id()`-Aufrufe. Der Aufruf existiert nach diesem Umbau
nicht mehr — der Whitelist-Eintrag wurde entfernt statt als toter Rest stehen
zu bleiben (sonst würde der Boundary-Test eine Ausnahme für einen Fall
offenhalten, der gar nicht mehr eintreten kann).

**Verifikation:** Neuer Test `tests/unit/test_animal_catcher.gd` — verifiziert,
dass zwei unterschiedliche `player_id`-Werte zu unterschiedlichen `owner_peer_id`
führen (der eigentliche Kernbeweis: vorher hätte `get_multiplayer().get_unique_id()`
in einem Test-Kontext ohne echtes Multiplayer-Setup ohnehin nur einen konstanten
Wert geliefert, unabhängig vom fangenden Spieler — das wäre in einem Unit-Test
gar nicht als Bug sichtbar gewesen).

---

## Phase 6 — Regressions-Schutz

Neuer Test `tests/unit/test_local_player_access_boundary.gd`, Muster identisch zu
`tests/unit/test_event_bus_access_boundary.gd`: scannt `scripts/` nach
`get_nodes_in_group("player")` außerhalb einer Whitelist (die dann nur noch die
"nächster Spieler"-Fälle aus Phase 2 enthält, z. B. `EnemyNPC.gd`, `AnimalBase.gd` —
falls deren Nächster-Spieler-Suche wie in Phase 2 vermerkt bewusst bestehen bleibt).

Ohne diesen Test ist nichts, was diese Migration verhindert, dass in sechs Monaten an
Stelle elf wieder `players[0]` auftaucht — genau das Muster, das `_find_local_player_visuals()`
schon einmal vorgemacht hat.

---

## Nicht Teil dieser Migration (bewusst)

- MIGRATION-010 Phase 4/5 (RPC-Verdrahtung, Equipment-Sync) — separates Vorhaben, siehe
  ADR-015 Option C, warum das nicht vermischt wird.
- "Nächster Spieler"-Suche für Gegner-KI/Tier-Flucht sauber implementieren (aktuell
  `players[0]` als Krücke) — verwandtes, aber eigenständiges Problem, in Phase 2 nur
  benannt.
- `_is_player_target()`-Heuristik in `InteractableComponent.gd` vereinfachen — optionale
  Folge-Verbesserung, keine Voraussetzung.
