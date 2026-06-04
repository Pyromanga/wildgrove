# 🏗️ WildGrove Core Architecture — Technical Specification
*Stand: 2026 — Godot 4.3 Mobile 3D*

---

## 1. Autoload-Reihenfolge (Projekt-Start)

Die Autoloads starten in dieser festen Reihenfolge. Jeder darf nur auf frühere zugreifen.

| Nr. | Autoload | Typ | Abhängigkeiten |
|-----|----------|-----|---------------|
| 1 | **Logger** | `Node` | keine |
| 2 | **EventBus** | `Node` | Logger |
| 3 | **SimpleTerminal** | `Node` | Logger, EventBus |
| 4 | **Services** | `Node` | Logger (Platzhalter — wird von Orchestrator befüllt) |
| 5 | **ServiceOrchestrator** | `Node` | alle obigen |

> ⚠️ `ServiceOrchestrator` ist ein **Autoload**, kein Kind-Node von `Main.tscn`.
> Er lebt bei `/root/ServiceOrchestrator` und überlebt alle `change_scene_to_file()`-Aufrufe.

---

## 2. Die Boot-Pipeline (ServiceOrchestrator)

| Phase | Name | Klasse | Aktion |
|-------|------|--------|--------|
| **1** | **Validate** | `ServiceValidator` | Prüft `BootstrapConfig.tres` auf Existenz und Integrität |
| **2** | **Resolve** | `ServiceDependencyResolver` | Topologische Sortierung via Kahn's Algorithmus |
| **3** | **Instantiate** | `ServiceFactory` | Erstellt Instanzen aus GDScript oder PackedScene |
| **4** | **Configure** | `ServiceInitializer.run()` | Ruft `configure(deps)` auf — DI-Phase |
| **5** | **Activate** | `ServiceInitializer.run_on_ready()` | Ruft `on_ready()` auf — Signal-Connections |
| **6** | **Tick Start** | `ServiceTicker` | Startet `on_tick()`/`on_physics_tick()` Loop |
| **7** | **Install** | `ServiceInstaller` + `Services.populate()` | Befüllt den globalen Container |
| **8** | **Game Start** | `GameManager.start_game()` | Setzt State auf MAIN_MENU |

**Fail-Fast-Garantie:** Boot bricht bei Phase 1/2/3-Fehlern sofort ab und feuert `EventBus.system.boot_failed`.

---

## 3. Service vs. Entity — Die zentrale Trennung

```
ServiceOrchestrator      EntityOrchestrator
│                        │
├─ Services (Singletons) ├─ Entities (Instanzen)
│  ├─ SaveSystem         │  ├─ OakTree
│  ├─ InventorySystem    │  ├─ IronOre
│  ├─ QuestService       │  ├─ NPC_Blacksmith
│  └─ WorldService       │  └─ Chest_01
│                        │
│  LIFETIME: App         │  LIFETIME: Szene/Chunk
│  CONFIG: .tres          │  CONFIG: EntityDefinition
```

- **Services** → laufen die gesamte App-Laufzeit, überleben Szenenwechsel
- **Entities** → werden mit der Welt erzeugt und mit ihr zerstört (oder über Object Pooling recycelt)
- **EntityOrchestrator** → lebt als Member von WorldService (nicht als Autoload)

---

## 4. Core-Klassen

### A. Bootstrap-Konfiguration (`BootstrapConfig.tres`)
Jeder Service wird als `ServiceDefinition`-Resource registriert:

| Feld | Beschreibung |
|------|-------------|
| `service_name` | Eindeutiger Key (lowercase, z.B. `"inventory"`) |
| `path` | Pfad zu `.gd` oder `.tscn` |
| `deps` | Array der benötigten Service-Namen |
| `required_data_files` | `.tres`-Dateien, die vor dem Boot existieren müssen |
| `interface_type` | Optional: Interface-Typ für Validierung |

### B. Basis-Klassen

| Klasse | Erbt von | Einsatz |
|--------|----------|---------|
| `Service` | `RefCounted` | Pure Logik ohne Node-Overhead (DataService, SaveSystem) |
| `ServiceNode` | `Node` | Braucht SceneTree (Ticker, Physik, Signale auf Node-Level) |

### C. Lifecycle-Interface

| Methode | Phase | Erlaubt |
|---------|-------|---------|
| `configure(deps)` | 4 — Injection | `deps.get("name")` aufrufen, Variablen setzen |
| `on_ready()` | 5 — Activation | `Services.xyz` lesen, EventBus-Signale connecten |
| `on_tick(delta)` | Runtime | Update-Logik (via ServiceTicker, kein `_process()` in Services!) |
| `on_cleanup()` | Teardown | Ressourcen freigeben, Signale trennen |

> ⚠️ **Regel:** `Services.xyz` NIEMALS in `configure()` aufrufen — der Container ist noch nicht befüllt!

---

## 5. Globale Kommunikation

### A. `Services` — Typisierter Dependency Container
```gdscript
Services.data.get_player_stat("speed")
Services.inventory.add_item("log_normal", 3)
Services.world.get_formatted_time()
Services.game_manager.change_state(GameEnums.State.PLAYING)
```

### B. `EventBus` — Entkoppeltes Messaging

| Namespace | Signale |
|-----------|---------|
| `EventBus.system` | Boot, State-Changes, Save/Load |
| `EventBus.player` | XP, Level-Up, Bewegung, Inventar |
| `EventBus.world` | Zeit, Chunks, Interaktionen |
| `EventBus.quest` | Quest-Start, Objectives, Abschluss |
| `EventBus.ui` | Layout, Menüs, Overlays |

**Regel:** Services rufen sich für **Daten** gegenseitig an (`Services.xyz`). Sie informieren über **Signale** (`EventBus`).

---

## 6. State Machine (GameManager)

```
BOOT → MAIN_MENU → LOADING → PLAYING ←→ PAUSED
                           ↓             ↓
                        GAME_OVER   CUTSCENE
                           ↓
                        MAIN_MENU
```

Erlaubte Übergänge stehen in `GameConfig.tres` → `valid_transitions`.

---

## 7. Szenen-Architektur

| Szene | Zweck |
|-------|-------|
| `MainMenu.tscn` | Startmenü (main_scene in project.godot) |
| `World.tscn` | Spielwelt-Container (leer — WorldFactory füllt ihn prozedural) |

Der `ServiceOrchestrator` (Autoload) überlebt `change_scene_to_file()`.
Das HUD-CanvasLayer wird von `HUDManager.attach_to_scene()` in `world_root` eingehängt.

---

## 8. Erweiterung: Neuen Service hinzufügen

1. `scripts/events/XyzEvents.gd` erstellen (falls eigene Signale nötig)
2. `EventBus.gd` — Namespace-Variable und Initialisierung eintragen
3. `scripts/services/XyzService.gd` erstellen (`extends Service` oder `ServiceNode`)
4. `ServiceDefinition` zu `BootstrapConfig.tres` hinzufügen
5. `Services.gd` — Variable und `populate()`-Zeile eintragen
6. `services.md` aktualisieren

---

## 9. Erweiterung: Neuen Entity-Typ hinzufügen

1. Entity-Script erstellen (z.B. `scripts/world/objects/NewObject.gd`)
2. `EntityOrchestrator.register_definition()` aufrufen mit Pfad und Gruppe
3. Via `WorldService` oder direkt per `EntityOrchestrator.spawn_entity()` spawnen

---

## 10. Debugging ohne Godot-Editor

Da wir blind coden, ist Logging alles:
- **SimpleTerminal** in-game öffnen (Toggle-Taste)
- **`status`** command → alle Services und deren null-Status
- **`services`** command → alle registrierten Service-Namen
- **`errors`** command → alle ERROR-Logs aus dem Puffer
- **`user://wildgrove.log`** → persistente Log-Datei (im Debug-Build automatisch aktiv)
- **`Logger.log_trace(msg, data, cat)`** → strukturiertes Logging mit Data-Snapshot
