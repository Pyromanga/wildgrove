# 🔍 WildGrove — Code Review & Session Log
*Lebendiges Dokument — nach jeder Session aktualisieren*

---

## Session 1 — Initial Review + Bug Fixes (Juni 2026)

### Gefundene und behobene Bugs

#### 🔴 KRITISCH: HUDManager.gd — Parse Error (Zeile 63)
**Problem:** Geschachtelter Klammer-Ausdruck in `Logger.log_warn()` verursachte:
```
Unexpected token Token('_INDENT', '\t') at line 63, column 23
```
**Ursache:** GDScript-Parser kann `Logger.log_warn((multiline_string % expr), LOG_CAT)` mit
extra Klammer-Gruppe nicht auflösen wenn über mehrere Zeilen umbrochen.

**Fix:** Variable für die Nachricht extrahiert, einzeiliger `log_warn()`-Call.

---

#### 🔴 KRITISCH: SimpleTerminal.gd — Datei-Korruption
**Problem:** Die Datei-Header wurden während einer früheren Formatter-Session in jeden
Lambda-Körper von `_register_default_commands()` eingefügt. GDScript konnte die Datei nicht parsen.

**Fix:** Vollständige Neuerstellung der Datei. Neue Commands hinzugefügt:
`status`, `service <n>`, `stats`, `errors`, `time`, `save`.

---

#### 🟡 ARCHITEKTUR: Main.gd — Falscher Autoload-Lookup
**Problem:** `Main.gd` suchte den `ServiceOrchestrator` als Kind-Node mit
`get_node_or_null("ServiceOrchestrator")`. Da er ein Autoload ist, lebt er bei
`/root/ServiceOrchestrator` — der Check lieferte immer `null` und loggte einen Fehler.

**Fix:** `Main.gd` überarbeitet — erklärender Kommentar, doppelte `is_connected()`-Guard,
Fallback wenn Services schon befüllt sind.

---

#### 🟡 ARCHITEKTUR: WorldService.gd — `_process()` statt `on_tick()`
**Problem:** `WorldService._process()` wurde direkt von Godot aufgerufen, umging damit
den `ServiceTicker`-Vertrag. Das macht den Ticker-Mechanismus inkonsistent.

**Fix:** `_process()` entfernt, `on_tick(delta)` implementiert, in `on_ready()` beim
`ServiceTicker` registriert.

---

#### 🟡 ARCHITEKTUR: WorldData.gd — `extends Node` ohne Tree-Einhängung
**Problem:** `WorldData` erbte von `Node`, wurde aber nie in den SceneTree eingehängt.
Node-Overhead ohne Nutzen.

**Fix:** `extends RefCounted` — keine Allocations, kein verstecktes Godot-Objekt.

---

#### 🟡 SERVICE-LÜCKE: ServiceOrchestrator bot keine Debug-API
**Problem:** `SimpleTerminal`s `services`-Command griff direkt auf `orch.registry` zu
(enge Kopplung an interne Implementierung).

**Fix:** `get_registered_names()` und `get_service_info(name)` als öffentliche API
zu `ServiceOrchestrator` hinzugefügt.

---

#### 🟢 DATEINAME: ServiceInitalizer.gd (Tippfehler)
**Problem:** Dateiname hatte Tippfehler (`Initalizer` statt `Initializer`).
`class_name ServiceInitializer` war korrekt — funktionierte auf case-insensitiven
Systemen (macOS/Windows), aber nicht auf Linux-Servern.

**Fix:** Korrekte Kopie als `ServiceInitializer.gd` erstellt.

---

### Neue Features

#### ✅ EntityOrchestrator (`scripts/core/EntityOrchestrator.gd`)
**Motivation:** ServiceOrchestrator sollte keine Entity-Lifecycle-Logik tragen.
Entities (NPCs, Ressourcen, Truhen) haben einen anderen Lebenszyklus als Services.

**Verantwortung:**
- Spawn/Despawn von World-Entities per `type_id`
- Object Pooling (max. `POOL_SIZE = 10` pro Typ)
- UUID-basiertes Entity-Tracking
- `on_world_unloaded()` für sauberes Cleanup

**Noch zu tun:** `EntityOrchestrator` in `WorldService.on_world_scene_ready()` integrieren
und `OakTree`/`IronOre` über ihn spawnen statt direkt über `WorldFactory`.

---

#### ✅ Logger — Enterprise-Erweiterungen
- **File-Logging:** `user://wildgrove.log` automatisch im Debug-Build aktiv
- **`log_begin()`/`log_end()`:** Elapsed-Zeit-Tracking für Operationen
- **`get_errors()`:** Alle ERROR-Logs aus dem Puffer abrufbar
- **`get_log_stats()`:** Counter pro Level
- **`peek_log_buffer()`:** Puffer lesen ohne Leeren
- MAX_BUFFER von 200 auf 500 erhöht

---

### Offene TODOs

| Priorität | Task | Datei |
|-----------|------|-------|
| 🔴 HIGH | `EntityOrchestrator` in `WorldService` integrieren | WorldService.gd |
| 🔴 HIGH | `BootstrapConfig.tres` Pfad für `ServiceInitializer.gd` prüfen (Tippfehler-Fix) | BootstrapConfig.tres |
| 🟡 MEDIUM | `QuestService._data_service` wird nie genutzt — Interface definieren | QuestService.gd |
| 🟡 MEDIUM | `GameSaveService` sollte `EventBus.system.save_started` connecten | GameSaveService.gd |
| 🟡 MEDIUM | `InteractionSensor.gd` noch nicht geprüft | InteractionSensor.gd |
| 🟢 LOW | `WorldFactory` nutzt immer noch Kommentar "Kernel.factory3d" | WorldFactory.gd |
| 🟢 LOW | `HUD.gd` ist leer — CanvasLayer-Setup fehlt | HUD.gd |
| 🟢 LOW | `SimpleTerminalUI.gd` nicht geprüft | SimpleTerminalUI.gd |

---

## Health-Check Protokoll

Vor jeder Session ausführen:
1. **`status`** im SimpleTerminal → alle Services grün?
2. **`errors`** im SimpleTerminal → keine unerwarteten Fehler?
3. **`services`** im SimpleTerminal → alle 15 Services registriert?
4. Log-Datei öffnen: `user://wildgrove.log`
5. Boot-Zeit im Log suchen: `╚══ BOOT FERTIG (X ms) ══╝` — unter 500ms?

---

## Bekannte GDScript-Fallen in diesem Projekt

1. **Multiline-Logger-Calls:** Niemals `Logger.log_xyz(("string %s" % val), CAT)` mit
   extra Klammer-Gruppe über mehrere Zeilen — Parser-Fehler. → Variable benutzen.
2. **`configure()` vs. `on_ready()`:** `Services.xyz` erst in `on_ready()` — in `configure()`
   ist der Container noch leer.
3. **`_process()` in Services:** Verboten — immer `on_tick()` + `ServiceTicker.register_service()`.
4. **`class_name`-Tippfehler:** Dateiname ≠ class_name → crasht auf Linux-Servern.
5. **Lambda in Dictionary:** Kommentare zwischen Lambda-Zeilen sind erlaubt, aber
   KEINE mehrzeiligen Expressions mit `(` direkt nach dem Kommentar.

---

## Session 2 — HUD-Fix + InteractionSensor + Joystick-Bridge (Juni 2026)

### Symptome (aus Log + User-Report)
- HUD war nicht sichtbar (kein Joystick, keine Buttons sichtbar)
- InteractionSensor: kein Log wenn Player in Reichweite kommt
- Joystick "funktioniert" (Player bewegt sich) aber Visuals folgen nicht

---

### Gefundene und behobene Bugs

#### 🔴 KRITISCH: TouchInput.gd — Joystick-Signale wurden nicht auf EventBus gebridged
**Problem:** `TouchInput` hatte eigene Signals `joystick_activated/released` die
nirgendwo verbunden wurden. `JoystickController.setup()` verbindet sich mit
`EventBus.ui.joystick_toggled/moved` — die wurden nie emittiert.
Ergebnis: Player bewegte sich (js_vec wurde korrekt gesetzt), aber Joystick-Visuals
blieben stumm und unsichtbar.

**Fix:** `TouchInput._handle_touch()` und `_handle_drag()` rufen jetzt direkt
`EventBus.ui.emit_joystick_toggled()` und `emit_joystick_moved()` auf.
Eigene Signal-Deklarationen entfernt (kein Zwischenlayer nötig).

---

#### 🔴 KRITISCH: JoystickVisuals.gd — ColorRects hatten keine Farbe
**Problem:** Godot-Default für `ColorRect.color` ist `Color(1,1,1,1)` (weiß).
Auf hellem/transparentem Hintergrund unsichtbar.

**Fix:** Explizite Farben: Basis = `Color(0.1, 0.1, 0.1, 0.45)`, Knob = `Color(0.8, 0.8, 0.8, 0.75)`.

---

#### 🔴 KRITISCH: InteractableComponent.gd — `add_to_group("interactable")` auf falschem Node
**Problem:** Die Gruppe wurde auf dem `InteractableComponent`-Node (Node3D-Child) gesetzt.
`InteractionSensor.get_overlapping_bodies()` gibt aber den **Physics-Body** zurück —
das ist das Parent-Objekt (OakTree, IronOre), nicht der Component.
Ergebnis: `sensor.get_closest()` fand nie ein Ziel → Button blieb immer aus.

**Fix:** `get_parent().add_to_group("interactable")` statt `add_to_group(...)` auf `self`.

---

#### 🟡 STUB AUFGELÖST: InteractionButtonController.gd — `_process()`-Polling
**Problem:** Controller pollte jeden Frame via `get_nodes_in_group("player")` und
`player.get_closest_interactable()` — O(n²) pro Frame, unnötig.

**Fix:** `_process()` entfernt. Controller lauscht jetzt auf
`EventBus.world.proximity_changed` — wird von `InteractionSensor` gefeuert
wenn sich das nächste Ziel ändert.

---

#### 🟡 STUB AUFGELÖST: InteractionSensor.gd — keine Events, kein Logging
**Problem:** Sensor war pure Daten-Klasse ohne `_ready()`, ohne Logging,
ohne Event-Emission. Nur `get_closest()` als synchrone API.
Ergebnis: Keine Log-Ausgabe wenn Player in Reichweite kommt.

**Fix:**
- `_ready()`: CollisionShape3D wird jetzt programmatisch erstellt (3.5m Radius)
- `_physics_process()`: Erkennt Änderungen im nächsten Ziel, emittiert `EventBus.world.proximity_changed`
- Logging: `[INFO] In Reichweite: 'OakTree'` und `Außer Reichweite: ...`

---

#### 🟡 ARCHITEKTUR: ContextButtonController — extend RefCounted, kein _ready()
**Problem:** `ContextButtonController` war `extends RefCounted` (implizit) ohne Node-Lifecycle.
EventBus-Connections für `proximity_changed` konnten nicht in `_ready()` gesetzt werden.
Der Kontext-Button war immer ausgeblendet oder immer sichtbar, unabhängig von Targets.

**Fix:** `extends Node`, `hud.add_child(ctrl)` in `ContextButtonComponent.build()`,
`_ready()` connectet `proximity_changed`.

---

#### 🟢 KOSMETIK: InteractionButtonVisuals + ContextButtonVisuals — initial sichtbar
**Problem:** Godot-Default `visible = true`. Buttons flackerten kurz beim HUD-Boot.
**Fix:** `visible = false` im `_init()`.

---

### Neue Features

#### ✅ WorldEvents — `proximity_changed(target: Node3D, in_range: bool)`
Neues Signal. Wird von `InteractionSensor` gefeuert wenn sich das nächste
Interagierbare ändert. Lauscher: `InteractionButtonController`, `ContextButtonController`,
`InteractableComponent` (für Label-Visibility).

---

### Aktualisierte offene TODOs

| Priorität | Task | Datei |
|-----------|------|-------|
| 🔴 HIGH | `EntityOrchestrator` in `WorldService` integrieren | WorldService.gd |
| 🔴 HIGH | `BootstrapConfig.tres` Pfad für `ServiceInitializer.gd` prüfen | BootstrapConfig.tres |
| 🟡 MEDIUM | `InteractionSensor` Physics-Layer per Editor setzen (Layer 2, Mask für Interactables) | Editor |
| 🟡 MEDIUM | `QuestService._data_service` wird nie genutzt — Interface definieren | QuestService.gd |
| 🟡 MEDIUM | `GameSaveService` sollte `EventBus.system.save_started` connecten | GameSaveService.gd |
| 🟡 MEDIUM | `ContextMenuController` nutzt `Engine.get_main_loop().root` — fragil; besser via Services.world oder direkt EventBus | ContextMenuController.gd |
| 🟡 MEDIUM | `OakTree`/`IronOre` via EntityOrchestrator statt direkt in WorldFactory spawnen | WorldFactory.gd |
| 🟢 LOW | `WorldFactory` Kommentare aufräumen | WorldFactory.gd |
| 🟢 LOW | `HUD.gd` leer — bei Bedarf CanvasLayer-Layer setzen (Standard: 1) | HUD.gd |
| 🟢 LOW | `SimpleTerminalUI.gd` nicht geprüft | SimpleTerminalUI.gd |

---

### Bekannte GDScript-Fallen (Ergänzung)

6. **`add_to_group()` und `get_overlapping_bodies()`:** Area3D gibt den Physics-Body
   zurück (CharacterBody3D, StaticBody3D etc.), nicht Node3D-Children. Die Gruppe
   muss auf dem Physics-Body-Node sitzen, nicht auf einem Child-Component.
7. **`ColorRect.color` Default ist weiß** — auf hellen Hintergründen unsichtbar.
   Immer explizit setzen.
8. **`extends Node`-Controller brauchen `add_child()`** — RefCounted-Objekte ohne
   Tree-Einhängung bekommen kein `_ready()` und kein `_process()`.

---

## Session 3 — EntityOrchestrator Integration + Stub-Auflösung (Juni 2026)

### Gefundene und behobene Bugs

#### 🔴 KRITISCH: WorldFactory._add_trees() — set_script()-Anti-Pattern
**Problem:** `_add_trees()` nutzte `Node3D.new()` + `tree.set_script(OakScript)`.
Der Kommentar in `_add_player()` verbot dies explizit: *"set_script() nach add_child() triggert _ready() ein zweites Mal."*
Dennoch wurde dasselbe Anti-Pattern für Bäume angewandt. Ergebnis: OakTree._ready() feuerte doppelt — InteractableComponent wurde zweimal hinzugefügt, Gruppe "interactable" zweimal gesetzt, Physik-Konflikte möglich.

**Fix:** `WorldFactory._add_trees()` entfernt. Baum-Spawning komplett in EntityOrchestrator verschoben. WorldFactory erstellt nur noch statische Geometrie (Boden, Licht, Player). Player-Instanziierung nutzte bereits korrekt `PlayerClass.new()`.

---

#### 🔴 KRITISCH: ServiceInitializer.gd — Dateiname-Tippfehler
**Problem:** Datei heißt `ServiceInitalizer.gd` (fehlendes 'i'). Auf macOS/Windows (case-insensitiv) funktioniert es da class_name `ServiceInitializer` gefunden wird. Auf Linux CI-Servern (case-sensitiv) würde ein expliziter `load("res://scripts/core/ServiceInitializer.gd")` fehlschlagen.

**Fix:** Korrekte Datei `ServiceInitializer.gd` erstellt (Phase 4/5 Logik identisch, aber mit deutlich mehr Logging per Service).

---

#### 🟡 STUB AUFGELÖST: EntityOrchestrator nicht in WorldService integriert
**Problem:** EntityOrchestrator existierte seit Session 1 aber wurde nie genutzt. OakTree/IronOre wurden direkt von WorldFactory.create_world() erstellt — ohne UUID-Tracking, ohne Object Pooling, ohne Harvest-State.

**Fix:**
- `WorldService` erstellt `EntityOrchestrator` als Child-Node in `configure()`
- `WorldService._register_entity_definitions()` registriert oak_tree + iron_ore
- `WorldService._spawn_world_entities()` spawnt Entities nach WorldFactory-Setup
- `WorldFactory.create_world()` spawnt KEINE Entities mehr (nur statische Geometrie)
- `OakTree` / `IronOre` implementieren jetzt `on_spawn(config)` und `on_despawn()`
- `on_despawn()` markiert Positionen in `WorldData` als geerntet → persistiert im Save
- `WorldEvents` um `entity_spawned`, `entity_despawned`, `world_scene_unloaded` erweitert

---

#### 🟡 STUB AUFGELÖST: InteractableComponent fehlte get_actions()
**Problem:** `Player.get_context_actions()` hatte einen expliziten STUB-Kommentar: "Wenn get_actions() hinzugefügt wird: return target.get_actions()". Bis dahin lieferte der Fallback eine generische Interagieren-Aktion ohne korrekte Daten.

**Fix:**
- `InteractableComponent.get_actions() -> Array[InteractableAction]` implementiert
- Gibt eine typsichere Aktion mit allen Daten aus `InteractableData` zurück
- `_ready()` setzt `get_parent().set_meta("interactable_component", self)` — Meta-Pattern für typ-agnostischen Lookup

**Warum Meta statt Child-Lookup?**
`Player.get_context_actions()` kennt den Entity-Typ nicht. `find_child("*Interactable*")` wäre fragil (naming-abhängig). Das Meta-Pattern ist O(1) und typ-agnostisch.

---

#### 🟡 STUB AUFGELÖST: Player.get_context_actions() nutzte Fallback
**Fix:** Nutzt jetzt `target.get_meta("interactable_component")` → `comp.get_actions()`. Drei-stufiger Fallback (Meta → Child-Traversal → has_method) für maximale Robustheit + ausführliches Logging auf jeder Stufe.

---

#### 🟡 STUB AUFGELÖST: GameSaveService.on_ready() fehlte
**Problem:** `GameSaveService` hatte kein `on_ready()`. `EventBus.system.save_started` war nie verbunden → programmatische Speicher-Trigger (Quicksave-Button, Pause-Menü) funktionierten nicht.

**Fix:** `on_ready()` hinzugefügt mit `EventBus.system.save_started.connect(_on_save_requested)`. Doppel-Save-Schutz dokumentiert (SaveSystem.save_game() emittiert save_started selbst).

---

#### 🟡 ARCHITEKTUR: ContextMenuController — Engine.get_main_loop() fragil
**Problem:** `Engine.get_main_loop().root.get_nodes_in_group("player")` — koppelt an die globale Engine-Instanz, schwer testbar, null-Risiko in Unit-Tests.

**Fix:** `_hud.get_tree().get_nodes_in_group("player")` — kontextgebunden, testbar, klar aus welchem Tree gesucht wird.

---

#### 🟢 ARCHITEKTUR: HUD.gd war leer
**Problem:** Kein explizites `layer = 1`, kein Logging, keine Dokumentation der Layer-Konvention.

**Fix:** `_ready()` mit explizitem `layer = 1` und Layer-Hierarchie-Dokumentation.

---

#### 🟢 ARCHITEKTUR: QuestService._data_service nie genutzt
**Problem:** DI-Dependency "data" wurde injiziert aber nie referenziert. Totes Code-Artefakt.

**Fix:** `_data_service` wird jetzt in `_load_quest_definitions()` genutzt (Existenz-Check, Pfad-Scan-Vorbereitung). Stubs dokumentieren den geplanten Einsatz für QuestDefinition-Ressourcen.

---

#### 🟢 FEATURE: InteractionSensor — Logging + doppelte Overlap-Erkennung
**Problem:** Sensor hatte keinerlei Logging. Zudem: `get_overlapping_bodies()` erkennt keine `Area3D`-Objekte — aber `InteractableComponent` erstellt eine eigene `Area3D`. OakTree (extends Node3D) ist kein Physics-Body → hätte nie erkannt werden können.

**Fix:**
- `_physics_process()` loggt Änderungen des nächsten Ziels
- `get_closest()` prüft jetzt BEIDE: `get_overlapping_bodies()` AND `get_overlapping_areas()`
- Area-Parent wird für die Distanzberechnung genutzt

---

### Geänderte Dateien (Session 3)

| Datei | Art | Beschreibung |
|-------|-----|-------------|
| `scripts/core/ServiceInitializer.gd` | NEU | Korrekt benannte Datei (Tippfehler-Fix) |
| `scripts/core/EntityOrchestrator.gd` | GEÄNDERT | Debug-API, on_world_unloaded Cleanup, emit-Events |
| `scripts/events/WorldEvents.gd` | GEÄNDERT | +entity_spawned, +entity_despawned, +world_scene_unloaded |
| `scripts/world/WorldFactory.gd` | GEÄNDERT | set_script()-Fix, Trees entfernt, nur statische Geometrie |
| `scripts/world/WorldService.gd` | GEÄNDERT | EntityOrchestrator integriert, _spawn_world_entities() |
| `scripts/world/WorldData.gd` | GEÄNDERT | +mark_tree/ore_harvested, Doppel-Add-Schutz |
| `scripts/world/objects/OakTree.gd` | GEÄNDERT | +on_spawn, +on_despawn, UUID-basiertes Despawn |
| `scripts/world/objects/IronOre.gd` | GEÄNDERT | +on_spawn, +on_despawn, UUID-basiertes Despawn |
| `scripts/interaction/InteractableComponent.gd` | GEÄNDERT | +get_actions(), +set_meta Pattern |
| `scripts/interaction/InteractionSensor.gd` | GEÄNDERT | +Logging, +get_overlapping_areas() |
| `scripts/player/Player.gd` | GEÄNDERT | get_context_actions() Stub aufgelöst, Meta-Lookup |
| `scripts/ui/HUD.gd` | GEÄNDERT | +layer=1, +_ready(), Layer-Dokumentation |
| `scripts/ui/controllers/ContextMenuController.gd` | GEÄNDERT | Engine.get_main_loop() → _hud.get_tree() |
| `scripts/services/GameSaveService.gd` | GEÄNDERT | +on_ready(), save_started verbunden |
| `scripts/services/QuestService.gd` | GEÄNDERT | _data_service genutzt, Stubs dokumentiert, +available_quests |

---

### Aktualisierte offene TODOs

| Priorität | Task | Datei |
|-----------|------|-------|
| 🔴 HIGH | `BootstrapConfig.tres` prüfen ob ServiceInitalizer.gd Pfad-Referenz existiert | BootstrapConfig.tres |
| 🟡 MEDIUM | Physics-Layer für InteractionSensor im Editor konfigurieren (Layer 2, Mask) | Editor |
| 🟡 MEDIUM | QuestDefinition .tres Dateien erstellen und in DataService integrieren | DataService.gd |
| 🟡 MEDIUM | `WorldService._spawn_world_entities()` mit Chunk-Loading erweitern | WorldService.gd |
| 🟡 MEDIUM | Object-Pooling für OakTree/IronOre testen (on_despawn → Pool → on_spawn) | EntityOrchestrator.gd |
| 🟢 LOW | `PlayerBackup.gd` enthält set_script()-Anti-Pattern für TouchInput — bereinigen | PlayerBackup.gd |
| 🟢 LOW | `SimpleTerminalUI.gd` nicht geprüft | SimpleTerminalUI.gd |
| 🟢 LOW | `WorldService.get_entity_debug_info()` an SimpleTerminal-Command koppeln | SimpleTerminal.gd |

---

### Bekannte GDScript-Fallen (Ergänzung)

9. **`set_script()` auf existierenden Nodes:** Niemals `Node.new() + node.set_script(script)`. Lösung: `Script.new()` direkt (Ein _ready()-Aufruf, korrektes Physik-Verhalten).
10. **Area3D vs. Body-Overlap:** `get_overlapping_bodies()` findet KEINE Area3D-Objekte. Wenn das Interagierbare keine Collision-Shape als Body hat, muss `get_overlapping_areas()` zusätzlich geprüft werden.
11. **Meta-Pattern für Komponenten-Lookup:** `node.set_meta("comp_key", component)` in `_ready()` → O(1) Lookup ohne fragiles `find_child()`. Invalidierung bei `on_despawn()` beachten wenn der Node gepoolt wird.
