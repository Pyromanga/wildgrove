# 🛠️ WildGrove — Service Registry & Responsibilities
*Stand: 2026-06 — Immer synchron halten mit BootstrapConfig.tres und Services.gd*

---

## Service-Übersicht

| Service | Key | Typ | Zuständigkeit | Abhängigkeiten |
|---------|-----|-----|--------------|----------------|
| **ServiceTicker** | `ticker` | `ServiceNode` | Zentraler Update-Loop für `on_tick()`/`on_physics_tick()` | keine |
| **SceneManager** | `scenemanager` | `ServiceNode` | Szenenwechsel via `transition_to_state()` | keine |
| **SaveSystem** | `savesystem` | `ServiceNode` | JSON-Serialisierung, Provider-Pattern, Disk-IO | keine |
| **DataService** | `data` | `ServiceNode` | Statische Ressourcen (PlayerData, Item-DB) | keine |
| **PlayerStateService** | `playerstates` | `ServiceNode` | Mikro-State des Spielers (FREE/BUSY/MENU) | `savesystem` |
| **SkillSystem** | `skill_system` | `ServiceNode` | XP-Kurven, Level-Ups, Skill-Tracking | `data`, `savesystem` |
| **Factory3D** | `factory3d` | `ServiceNode` | Programmatische 3D-Objekte (Bäume, Bars) | `data` |
| **InteractionExecutor** | `interaction_executor` | `ServiceNode` | Timed-Interaction-Ablauf, Tween-Management | `playerstates` |
| **GameSaveService** | `gamesave` | `ServiceNode` | Koordinator für vollständige Speichervorgänge | `savesystem` |
| **GameManager** | `gamemanager` | `ServiceNode` | State Machine (BOOT→MENU→PLAYING…) | `savesystem`, `playerstates`, `scenemanager` |
| **WorldService** | `world` | `ServiceNode` | Welt-Daten, Zeit-Zyklus, prozeduale Generierung | `savesystem`, `data` |
| **InventorySystem** | `inventory` | `ServiceNode` | Item-Add/Remove, Item-DB, Save-Provider | `data`, `savesystem` |
| **UICanvasService** | `ui_canvas` | `ServiceNode` | Root-CanvasLayer bereitstellen | keine |
| **HUDManager** | `hud` | `ServiceNode` | HUD-Controller-Setup, attach_to_scene | `inventory`, `playerstates` |
| **QuestService** | `quest` | `ServiceNode` | Quest-Tracking, Objectives, Rewards | `data`, `savesystem` |

---

## Entity-System (nicht über BootstrapConfig registriert)

| Klasse | Ort | Zuständigkeit |
|--------|-----|--------------| 
| **EntityOrchestrator** | `scripts/core/EntityOrchestrator.gd` | Spawn/Despawn/Pool von World-Entities |
| **OakTree** | `scripts/world/objects/OakTree.gd` | Fällbarer Baum (InteractableComponent) |
| **IronOre** | `scripts/world/objects/IronOre.gd` | Abbaubares Erz (InteractableComponent) |
| **InteractionSensor** | `scripts/interaction/InteractionSensor.gd` | Area3D-Child des Players; erkennt Interagierbare |
| **InteractableComponent** | `scripts/interaction/InteractableComponent.gd` | Node3D-Child von Entities; koppelt an Interaktions-System |

---

## Save-Provider

| Service | Save-Key | Gespeicherte Daten |
|---------|----------|-------------------|
| SaveSystem | — | Koordinator — keine eigenen Daten |
| InventorySystem | `inventory` | `{ "item_id": quantity }` |
| SkillSystem | `skills` | `{ "skill_name": { xp, level } }` |
| QuestService | `quest_progress` | `{ active: {}, completed: [] }` |
| WorldService | `world_state` | `{ day_time, day_count, tree_positions, player_pos }` |

---

## EventBus-Namespaces

### `EventBus.system`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `state_changed` | `state: int` | GameManager |
| `services_initialized` | — | ServiceOrchestrator (Phase 8) |
| `boot_failed` | `phase, reason` | ServiceOrchestrator |
| `save_started` | — | SaveSystem |
| `save_completed` | `success: bool` | SaveSystem |

### `EventBus.player`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `xp_gained` | `skill, amount` | InteractableComponent |
| `level_up` | `skill, new_level` | SkillSystem |
| `movement_interrupted` | — | Player |
| `inventory_changed` | `items: Array` | InventorySystem |
| `speed_modifier_changed` | `id, multiplier` | extern |
| `speed_modifier_removed` | `id` | extern |

### `EventBus.world`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `interaction_started` | `label, duration` | InteractionExecutor |
| `interaction_finished` | `label` | InteractionExecutor |
| `interaction_cancelled` | `label` | InteractionExecutor |
| `world_scene_ready` | `world_root: Node` | WorldService |
| `loot_collected` | `item_id, quantity` | InteractableComponent |
| `interaction_reward_text` | `text` | InteractableComponent |
| `proximity_changed` | `target: Node3D, in_range: bool` | InteractionSensor |
| `time_of_day_changed` | `hour` | WorldService |
| `chunk_loaded` / `chunk_unloaded` | `chunk_id: Vector2i` | WorldService (future) |

### `EventBus.ui`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `joystick_toggled` | `is_active: bool, origin: Vector2` | TouchInput (bridged) |
| `joystick_moved` | `origin: Vector2, offset: Vector2` | TouchInput (bridged) |
| `request_context_menu` | — | ContextButtonController |
| `layout_requested` | `state: String` | extern |
| `menu_toggled` | `menu_name, is_visible` | extern |
| `overlay_changed` | `overlay_type, active` | extern |

### `EventBus.quest`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `quest_started` | `quest_id` | QuestService |
| `quest_completed` | `quest_id, reward` | QuestService |
| `quest_objective_updated` | `quest_id, obj_id, current, required` | QuestService |

---

## Boot-Reihenfolge (nach Dependency-Auflösung)

```
ticker → scenemanager → savesystem → data
  → playerstates → skill_system → factory3d
  → interaction_executor → gamesave → gamemanager → inventory
  → ui_canvas → world → hud → quest
```

---

## UI-Komponenten Architektur

HUD-Komponenten folgen dem **Component/Controller/Visuals**-Muster:

```
HUDBuilder.build_all()
  └── XyzComponent.build(hud, deps)
        ├── XyzVisuals.new(hud)      ← Erstellt Godot-Nodes, hängt sie in HUD ein
        ├── XyzController.new()      ← Enthält Logik, lauscht auf Events
        └── ctrl.setup(visuals, ...) ← Koppelt Logik an Visuals

Regel: Controller die _ready()/_process() brauchen → extends Node → hud.add_child(ctrl)
Derzeit betrifft das: InteractionButtonController, ContextButtonController
```

---

## Multiplayer-Readiness (Planung)

| Datenkategorie | Besitzer | Validierung |
|---------------|----------|-------------|
| Item-Pickup | Server | `InventorySystem.request_pickup()` → Server-Check → Client-Sync |
| Quest-Fortschritt | Server | QuestService prüft Voraussetzungen serverseitig |
| Welt-Zustand | Server | WorldService ist Authority für Ressourcen-State |
| UI-Einstellungen | Client | Lokal, keine Sync nötig |
