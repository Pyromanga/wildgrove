# 🛠️ WildGrove — Service Registry & Responsibilities
*Stand: 2026 — Immer synchron halten mit BootstrapConfig.tres und Services.gd*

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
| **InteractionBuilder** | `builder` | `ServiceNode` | Timed-Interaction-Ablauf, Tween-Management | `playerstates` |
| **GameSaveService** | `gamesave` | `ServiceNode` | Koordinator für vollständige Speichervorgänge | `savesystem` |
| **GameManager** | `gamemanager` | `ServiceNode` | State Machine (BOOT→MENU→PLAYING…) | `savesystem`, `playerstates`, `scenemanager` |
| **WorldService** | `world` | `ServiceNode` | Welt-Daten, Zeit-Zyklus, HUD-Attachment | `savesystem`, `data` |
| **InventorySystem** | `inventory` | `ServiceNode` | Item-Add/Remove, Item-DB, Save-Provider | `data`, `savesystem` |
| **UIFactory** | `ui_factory` | `ServiceNode` | Programmatische UI-Canvas-Erstellung | `inventory` |
| **HUDManager** | `hud` | `ServiceNode` | HUD-Controller-Setup, attach_to_scene | `inventory`, `playerstates` |
| **QuestService** | `quest` | `ServiceNode` | Quest-Tracking, Objectives, Rewards | `data`, `savesystem` |

---

## Entity-System (nicht über BootstrapConfig registriert)

| Klasse | Ort | Zuständigkeit |
|--------|-----|--------------|
| **EntityOrchestrator** | `scripts/core/EntityOrchestrator.gd` | Spawn/Despawn/Pool von World-Entities |
| **OakTree** | `scripts/world/objects/OakTree.gd` | Fällbarer Baum (InteractableComponent) |
| **IronOre** | `scripts/world/objects/IronOre.gd` | Abbaubares Erz (InteractableComponent) |

---

## Save-Provider

Services, die am Save-System teilnehmen (implementieren `get_save_key()` + `get_save_data()`):

| Service | Save-Key | Gespeicherte Daten |
|---------|----------|-------------------|
| SaveSystem | — | Koordinator — keine eigenen Daten |
| InventorySystem | `inventory` | `{ "item_id": quantity }` |
| SkillSystem | `skills` | `{ "skill_name": { xp, level } }` |
| QuestService | `quest_progress` | `{ active: {}, completed: [] }` |
| PlayerStateService | `player_state` | `{ current_micro_state: int }` |
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

### `EventBus.world`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `interaction_started` | `label, duration` | InteractionBuilder |
| `interaction_finished` | `label` | InteractionBuilder |
| `time_of_day_changed` | `hour` | WorldService |

### `EventBus.quest`
| Signal | Parameter | Wer feuert |
|--------|-----------|-----------|
| `quest_started` | `quest_id` | QuestService |
| `quest_completed` | `quest_id, reward` | QuestService |
| `quest_objective_updated` | `quest_id, obj_id, current, required` | QuestService |

---

## Boot-Reihenfolge (nach Dependency-Auflösung)

Kahn's Algorithmus berechnet die Reihenfolge zur Laufzeit. Typische Reihenfolge:
```
ticker → scenemanager → savesystem → data
  → playerstates → skill_system → factory3d
  → builder → gamesave → gamemanager → inventory
  → ui_factory → world → hud → quest
```

---

## Multiplayer-Readiness (Planung)

| Datenkategorie | Besitzer | Validierung |
|---------------|----------|-------------|
| Item-Pickup | Server | `InventorySystem.request_pickup()` → Server-Check → Client-Sync |
| Quest-Fortschritt | Server | QuestService prüft Voraussetzungen serverseitig |
| Welt-Zustand | Server | WorldService ist Authority für Ressourcen-State |
| UI-Einstellungen | Client | Lokal, keine Sync nötig |
