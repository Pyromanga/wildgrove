# WildGrove — Service Registry & EventBus Reference

> **Stand:** v35 (Prio 3)
> **Vorgänger:** v34 (Session 5)
> **Pflege:** Bei jedem neuen Service, Signal oder Save-Provider aktualisieren (siehe `CONTRIBUTING.md` Abschnitt 2.7)
> **⚠ Ableitungs-Warnung:** Diese Datei ist eine *Ableitung* — die eigentliche Source of Truth ist `BootstrapConfig.tres` (Services) und die `*Events.gd`-Dateien (Signals). Ableitungen driften. Wenn diese Datei und der Code widersprechen: **dem Code glauben.**
>
> **Nachtrag (AUDIT-03 I-02):** Diese Datei wurde zwischen v35 und diesem Nachtrag nicht laufend
> mitgepflegt (mehrere Runden, u.a. I-01, fehlen hier vollständig — siehe `docs/audit/AUDIT-03-meta-review.md`
> für den aktuellen Stand). Dieser Nachtrag deckt ausschließlich I-02 ab, nicht die Lücke dazwischen:
> UI-Controller (`scripts/ui/controllers/*.gd`) lesen Events jetzt über `IUIContext.bus()` statt direkt
> vom `EventBus`-AutoLoad — siehe Abschnitt 4a und [ADR-012](adr/012-ui-eventbus-injection.md).
>
> **v35 (Prio 3):**
> - `StatModifierService` ist jetzt Multi-Tenant (`player_id`-Parameter an allen öffentlichen Methoden, Default = 1). Neue Methode `clear_player(player_id)`.
> - `EquipmentService` ist jetzt Multi-Tenant (gleiche Konvention) und implementiert `ISaveProvider` (Save-Key `"equipment"`). Neue Methode `clear_player(player_id)`. Benötigt `DataService` in deps für Save-Load.
> - `ChunkManager` nutzt `on_tick()` statt `_process()` — `WorldService` registriert ihn beim `ServiceTicker` nach `initialize()`.
> - `EventBus.player`-Signale `speed_modifier_changed` / `speed_modifier_removed` entfallen (PlayerMover liest Geschwindigkeit direkt aus `StatModifierService` — Prio 1/2 bereits erledigt).
> - Save-Schema: v3 ergänzt leeres `"equipment":{}`-Objekt in `SaveMigrationService` für Saves < v3.

---

## 1. Service-Registry

Alle Services werden in `BootstrapConfig.tres` registriert und von `ServiceOrchestrator` in topologischer Reihenfolge gebootet. Die Reihenfolge in dieser Tabelle entspricht der Reihenfolge im Boot.

| Service | Registry-Key | Basisklasse | Verantwortung | Abhängigkeiten |
|---------|-------------|-------------|---------------|----------------|
| `ServiceTicker` | `ticker` | `ServiceNode` | Zentraler Update-Loop für alle `on_tick()`-Services | keine |
| `SceneManager` | `scenemanager` | `ServiceNode` | Szenenwechsel via `transition_to_state()` | keine |
| `SaveSystem` | `savesystem` | `Service`¹ | JSON-Serialisierung, Provider-Pattern, Disk-IO | keine |
| `SettingsService` | `settings_service` | `Service` | Persistiert UI-/Client-Settings (Joystick, Kamera, Zoom, Bildschirm-Rotation) nach `user://settings.json`, atomic write, geräteweit statt pro Charakter | keine |
| `DataService` | `data` | `ServiceNode`¹ | Statische Ressourcen: PlayerData, Item-DB, Quest-DB, Skill-DB, CombatProfile-DB | keine |
| `PlayerStateService` | `playerstates` | `ServiceNode`¹ | Mikro-State des Spielers: FREE / BUSY / MENU | keine |
| `SaveMigrationService` | *(statisch)* | `RefCounted` | Versionierte Save-Schema-Migration (aktuell v3) | keine |
| `SkillSystem` | `skill_system` | `Service` | XP-Kurven, Level-Ups, Skill-Tracking | `data`, `savesystem` |
| `InventorySystem` | `inventory` | `Service` | Item-Add/Remove, Slot/Gewichts-Limits, Save-Provider | `data`, `savesystem` |
| `RewardDispatcher` | `reward_dispatcher` | `Service` | Verteilt Quest-Rewards an Inventory/Skills | `inventory`, `skill_system` |
| `InteractionExecutor` | `interaction_executor` | `ServiceNode` | Timed-Interaction-Ablauf, Tween-Management | `playerstates` |
| `GameSaveService` | `gamesave` | `Service` | Koordiniert vollständige Speichervorgänge² | `savesystem` |
| `GameManager` | `gamemanager` | `ServiceNode` | State Machine: BOOT → MENU → PLAYING → … | `savesystem`, `playerstates`, `scenemanager` |
| `WorldGenerationService` | `world_gen` | `ServiceNode` | Seed-basierte prozedurale Welt-Generierung | keine |
| `WorldService` | `world` | `ServiceNode` | Welt-Daten, Tag/Nacht-Zyklus, Wetter (ADR-041), Entity-Orchestration, Multiplayer-Spawn | `savesystem`, `event_bus` (required); `world_gen`, `ticker`, `respawn`, `gamemanager`, `session_manager`, alle Entity-Session-Deps (optional) |
| `RespawnService` | `respawn` | `ServiceNode` | Plant geerntete Entities für Respawn ein (Min-Heap) | keine |
| `QuestService` | `quest` | `Service` | Quest-Tracking, Objectives, Rewards | `data`, `savesystem`, `skill_system`, `reward_dispatcher` |
| `StatModifierService` | `stat_modifiers` | `Service` | Generische Stat-Boni (FLAT_ADD/PERCENT_ADD/PERCENT_MULTIPLY), zeitbasiert, **multi-tenant** | keine |
| `CombatSystem` | `combat` | `ServiceNode` | Schaden-Berechnung (`DamageRecord`, Resistenz, Krit), `apply_damage()` (ADR-008), Status-Effekte | `stat_modifiers` |
| `EquipmentService` | `equipment` | `Service` | Ausgerüstete Items pro Slot, Equipment-Boni via StatModifier, WeaponVisual3D-Attachment, **multi-tenant**, **ISaveProvider** | `stat_modifiers`, `savesystem`, `data` |
| `ItemProtectionService` | `item_protection` | `Service` | ADR-038: Item-Schutz-Dreiklang (PvE-Todesschutz/Diebstahlschutz/PvP-Schutz), Anwendung + Abfrage, **zustandslos** (State lebt auf `ItemInstance`) | `inventory` |
| `PvPDeathLossService` | `pvp_death_loss` | `Service` | ADR-036: PvP-Tod-Verlust (Skull-Loot), Gold/Item-Verlust nach Skull-Status des Opfers + Killer-Risiko, Loot an den Killer, respektiert ADR-038-Schutzkategorien | `pvp`, `currency`, `inventory` |
| `AuraService` | `aura` | `Service` | ADR-036: Reputationswert (-6000..+6000), Kill-Strafe bei geskulltem Killer, "Danken"-Interaktion (24h-Cooldown/Paar), **ISaveProvider** | — |
| `DeathLootService` | `death_loot` | `Service` | ADR-037: PvE-Tod-Loot (Grab-Hybrid-Timer), entfernt Gold/Items (außer PvE-todesgeschützt) und spawnt `Gravestone`, injiziert `WorldService` per `inject_world()` (Zyklus-Vermeidung) | `currency`, `inventory` |
| `PickpocketService` | `pickpocket` | `Service` | ADR-039: Pickpocketing (drei Kristallstufen, Skill-Formel, Cooldown/Paar), Zonen-Check auf das Opfer, respektiert `is_theft_protected`, **ISaveProvider** | `inventory`, `currency`, `skill_system`, `zone_service` |

**¹ Resolved (ADR-003):** `SaveSystem`, `DataService`, `PlayerStateService`, `StatModifierService`, `RewardDispatcher`, and `GameSaveService` all extend `Service`. No open ADR-003 violations remain among registered services.
**² Tech Debt:** Aufteilung zwischen `GameSaveService` und `SaveSystem` ist unklar. Konsolidierung ausstehend.

> **v33:** `HUDManager` wurde aus dem Services-Container entfernt (A-03 ✅). Er lebt jetzt als eigenständiger Node unter `/root`, kommuniziert ausschließlich über `EventBus.ui`.

---

## 2. Entity-System

Nicht über BootstrapConfig registriert — leben im SceneTree unter WorldService.

| Klasse | Pfad | Verantwortung |
|--------|------|---------------|
| `EntityOrchestrator` | `scripts/platform/entity/` | Spawn/Despawn/Pool aller World-Entities; setzt `multiplayer_authority(peer_id)` nach `add_child()` |
| `EntityPool` | `scripts/platform/entity/` | Object-Pool: acquire / release nach type_id |
| `EntityRegistry` | `scripts/platform/entity/` | Definition-Verwaltung: script_path + group pro type_id; `get_path_to_type_map()` liefert umgekehrte Map für `MultiplayerSpawner.spawn_function` |
| `ChunkManager` | `scripts/world/chunks/` | Lädt/entlädt Terrain-Chunks, **on_tick()** (kein _process mehr) |
| `OakTree` | `scripts/world/objects/` | Fällbarer Baum (mit InteractableComponent) |
| `IronOre` | `scripts/world/objects/` | Abbaubares Erz (mit InteractableComponent) |
| `EnemyNPC` | `scripts/entities/combat/` | Gegner mit EnemyAI, HealthComponent; `MultiplayerSynchronizer` 10 Hz |
| `QuestNPC` | `scripts/progression/quests/ (QuestNPC ist Quest-Domain)` | Quest-Geber mit DialogController |
| `AnimalBase` | `scripts/entities/animals/` | Basis für Deer, Rabbit, Boar, Fox, Squirrel, Sheep |

**Multiplayer-Spawn-Replikation (Sprint F):**
`WorldService._setup_multiplayer_spawner()` setzt `MultiplayerSpawner.spawn_function` und
`despawn_function` (Custom Callables) statt `add_spawnable_scene()`. Grund: das Projekt
instanziiert Entities via `GDScript.new()` — `add_spawnable_scene()` akzeptiert nur `.tscn`-Pfade.
`spawn_function` löst den vom Server übermittelten script_path via `EntityRegistry.get_path_to_type_map()`
zu einem `type_id` auf und ruft `EntityRegistry.instantiate()` auf. Läuft nur auf dem Server
(Tier 2/3); Solo (Tier 1) und Tests bleiben unberührt.

**RespawnService spawn_callback-Signatur (Sprint F):**
`Callable(type_id: String, position: Vector3, peer_id: int = 1) -> Node3D`.
`peer_id` Default 1 (Server-Autorität für World-Entities). Ein zukünftiger Player-Respawn
müsste `peer_id` im Queue-Eintrag mitführen — als Erweiterungspunkt dokumentiert.

**MultiplayerSynchronizer-Intervalle (Sprint F):**
Player: 20 Hz (`replication_interval = 0.05`). EnemyNPC: 10 Hz (`replication_interval = 0.1`).
Sync-Richtung: Godot sendet vom Autoritäts-Peer zu allen anderen — kein zweiter Synchronizer nötig.

---

## 3. Save-Provider

| Service | Save-Key | Schema | Gespeicherte Daten |
|---------|----------|--------|--------------------|
| `InventorySystem` | `inventory` | `{ "item_id": quantity }` | Alle Items + Mengen |
| `SkillSystem` | `skills` | `{ "skill_name": { "xp": int, "level": int } }` | XP + Level pro Skill |
| `QuestService` | `quest_progress` | `{ "active": {}, "completed": [], "available": [] }` | Quest-Fortschritt |
| `WorldService` | `world_state` | `{ "day_time", "day_count", "typed_tree_positions", "typed_ore_positions", "player_pos", "harvested", "saved_pets", "world_seed", "weather", "weather_last_rolled_day" }` | Welt-State |
| `EquipmentService` | `equipment` | `{ "peer_id_str": { "slot": "item_id"\|null } }` | Ausgerüstete Items pro Spieler |

**Schema-Version:** `SaveMigrationService.CURRENT_VERSION` = 3. Migration v2→v3 adds empty `"equipment": {}` for saves older than v3.

---

## 4. EventBus-Namespaces

> **⚠ Signal-Ownership:** `BaseEvents`-Objekte trennen Connections **nicht** automatisch. Jeder Service der sich in `on_ready()` connected, muss sich in `on_cleanup()` explizit disconnecten.

### 4a. Zugriffspfade — Service-Layer vs. UI-Layer (ADR-011, ADR-012)

Zwei Schichten, ein Adapter: `EventBusAdapter` ist die einzige Produktions-Implementierung von
`IEventBus`, registriert unter `ServiceKeys.EVENT_BUS` in **beiden** Registries (global + Session,
siehe `BootPipeline`). Niemand greift produktiv direkt auf den `EventBus`-AutoLoad zu außer dieser
einen Adapter-Klasse selbst.

| Schicht | Zugriffspfad | Test-Double |
|---------|--------------|-------------|
| Services (`scripts/<domain>/*.gd (domain-first, z.B. scripts/economy/inventory/)`) | `deps.require(ServiceKeys.EVENT_BUS) as IEventBus` in `configure()` | `MockEventBus` |
| UI-Controller (`scripts/ui/controllers/*.gd`) | `ctx.bus()` — `ctx: IUIContext` aus `setup(visuals, ctx)` | `UIContext.for_test()` + `MockEventBus` |

`EventBus.xyz.*` direkt im eigenen Code zu referenzieren ist für beide Schichten ein
Review-Blocker (CONTRIBUTING.md 2.1, 7.3 bzw. 7.8). Ausnahme: Scene-Tree-Nodes außerhalb des
Service-Containers (`HUDManager`, `HUDBuilder`, `World.gd`, `MainMenuController.gd`) — die haben
keinen DI-Einstiegspunkt und sind nicht Teil von ADR-011/ADR-012.

> **BUG-21 (Round 24):** `MainMenuController.SaveSystem` ist ebenfalls ein AutoLoad-freier
> DI-Punkt, aber **kein** `EventBus`-Fall — separat gelöst über `MenuScopeInitializer`
> (Push-Pattern analog `WorldScopeInitializer`). `MainMenu.tscn` enthält einen
> `MenuScopeInitializer`-Child-Node, der beim `_ready()` `menu_ready(menu_root)` emittiert;
> `ServiceOrchestrator._watch_for_menu_initializer()` lauscht dauerhaft (MainMenu.tscn wird bei
> jedem `main_menu_requested` neu geladen) und ruft `menu_root.inject_save_system(...)` mit dem
> `SaveSystem` aus dem App-Scope auf. Vorher existierte `inject_save_system()` als toter DI-Punkt
> ohne jeden Aufrufer — die Charakterliste im Hauptmenü blieb dadurch immer leer.

### `EventBus.system`

| Signal | Parameter | Emittiert von | Empfänger |
|--------|-----------|---------------|-----------|
| `state_changed` | `state: int` | `GameManager` | `PlayerStateService`, `SceneManager` |
| `services_initialized` | — | `ServiceOrchestrator` (Phase 8) | `Player` |
| `boot_failed` | `phase: String, reason: String` | `ServiceOrchestrator` | Debug-UI |
| `save_started` | — | `SaveSystem` | HUD-Feedback |
| `save_completed` | `success: bool` | `SaveSystem` | HUD-Feedback |

### `EventBus.player`

| Signal | Parameter | Emittiert von | Empfänger |
|--------|-----------|---------------|-----------|
| `xp_gained` | `skill: String, amount: int` | `InteractableComponent` | `SkillSystem`, `QuestService` |
| `level_up` | `skill: String, new_level: int` | `SkillSystem` | HUD, Notifications |
| `health_changed` | `current: float, max: float` | `HealthComponent` | HUD |
| `player_died` | — | `Player` | HUD, GameManager |
| `player_respawned` | — | `Player` | HUD |
| `movement_interrupted` | — | `Player` | HUD-Animation |
| `input_reset_requested` | — | `PlayerStateService` | `TouchInput` |

> **v35:** `speed_modifier_changed` / `speed_modifier_removed` entfernt — `PlayerMover` liest Geschwindigkeit direkt aus `StatModifierService` via `IEntityContext` (Prio 1/2).

### `EventBus.world`

| Signal | Parameter | Emittiert von | Empfänger |
|--------|-----------|---------------|-----------|
| `world_scene_ready` | `world_root: Node3D` | `WorldService` | `EntityOrchestrator`, `HUDManager` |
| `world_unloaded` | — | `WorldService` | `EntityOrchestrator`, `RespawnService` |
| `entity_spawned` | `type_id: String, entity: Node3D, pos: Vector3` | `EntityOrchestrator` | Debug |
| `entity_despawned` | `type_id: String, uuid: String, pos: Vector3` | `EntityOrchestrator` | `RespawnService` |
| `loot_collected` | `item_id: String, quantity: int` | `InteractableComponent` | `InventorySystem`, `QuestService` |
| `interaction_started` | `label: String, duration: float` | `InteractionExecutor` | HUD-Progressbar |
| `interaction_finished` | `action_id: String, label: String` | `InteractionExecutor` | `QuestService` |
| `interaction_cancelled` | `label: String` | `InteractionExecutor` | HUD |
| `day_started` | `day_count: int` | `WorldTimeService` | UI, Quests |
| `day_time_changed` | `normalized: float` | `WorldTimeService` | Sky-Shader, UI |
| `weather_changed` | `new_weather: String, old_weather: String` | `WeatherService` (ADR-041, deterministisch pro Peer, kein RPC) | UI-Notification |
| `respawn_scheduled` | `type_id: String, pos: Vector3, at: float` | `RespawnService` | Debug |
| `damage_dealt` | `record: DamageRecord` | `CombatSystem.apply_damage()` | UI, Logger |

### `EventBus.quest`

| Signal | Parameter | Emittiert von | Empfänger |
|--------|-----------|---------------|-----------|
| `quest_unlock_requested` | `quest_id: String` | NPCs | `QuestService` |
| `quest_start_requested` | `quest_id: String` | UI | `QuestService` |
| `quest_unlocked` | `quest_id: String` | `QuestService` | HUD |
| `quest_started` | `quest_id: String` | `QuestService` | HUD |
| `quest_completed` | `quest_id: String, reward: QuestReward` | `QuestService` | HUD, Notification |
| `quest_failed` | `quest_id: String` | `QuestService` | HUD |
| `objective_updated` | `quest_id, obj_id, current, required` | `QuestService` | HUD |
| `quest_start_failed` | `quest_id: String, reason: String` | `QuestService` | Debug |

### `EventBus.ui`

| Signal | Parameter | Emittiert von | Empfänger |
|--------|-----------|---------------|-----------|
| `pause_requested` | — | `PauseMenuController` | `GameManager` |
| `resume_requested` | — | `PauseMenuController` | `GameManager` |
| `inventory_open_requested` | — | UI-Button | `HUDManager` |

---

## 5. Boot-Reihenfolge (AutoLoads)

```
1. Logger              — Muss als erstes starten (alle anderen loggen)
2. EventBus            — Namespaced Signal-Infrastruktur
3. SimpleTerminal      — Debug-Terminal (nur Development-Build)
4. Services            — Typisierter Service-Container (startet leer)
5. ServiceOrchestrator — Startet Boot-Pipeline, befüllt Services
6. IT03Harness         — CI-only Zwei-Prozess-Treiber für IT-03 (scripts/testing/,
                          per Cmdline-User-Arg aktiviert, No-Op im normalen Spiel,
                          vor dem Produktions-Export physisch entfernt)
```

---

## 6. Change-Impact-Matrix

| Datei | Auswirkung |
|-------|------------|
| `BootstrapConfig.tres` | Boot-Reihenfolge, alle Service-Instanziierungen |
| `Services.gd` | Alle Stellen die `Services.xyz` aufrufen (gesamtes Projekt) |
| `EventBus.gd` + `*Events.gd` | Alle Signal-Connections (grep nach `EventBus.namespace`) |
| `Logger.gd` | Jede einzelne Log-Zeile im Projekt |
| `ServiceOrchestrator.gd` | Komplettes Boot-Verhalten |
| `SaveSystem.gd` | Alle Save-Provider |
| `SaveMigrationService.gd` | Alle gespeicherten Spielstände |
| `EntityContext.gd` | Alle Entities die `on_spawn(config, ctx)` implementieren |
| `StatModifierService.gd` | Equipment-Boni, Buffs, Debuffs — multi-tenant ab v35 |
| `EquipmentService.gd` | Equipment-State, ISaveProvider ab v35 |
