# ImplementAgent.md — WildGrove Bug-Fix Execution Plan

**Scope:** Prio-3 ZIP + Meta-Review (WILDGROVE_META_REVIEW.md)
**Method:** Bug-by-bug with ZIP output after each logical group. Code is ground truth.
**Date:** 2026-06

---

## Working Rules

1. **One bug at a time** — fix, update tests + docs atomically, output ZIP, move on.
2. **No legacy comments** — completed TODOs and "xyz is fixed" notes are removed, not kept.
3. **Meta-check every fix** — before applying, re-verify the actual file matches what the review claims.
4. **Docs + tests always updated** — services.md, ADRs, test files stay in sync with every change.
5. **Trust the code, not the docs** — AGENT.md rule applies here too.
6. **No franchise names** — concepts only in all output.

---

## DONE ✅

#### BUG-1: A-01 — EquipmentService: Complete Save Failure ✅
- `get_save_key()` / `get_save_data()` — renamed to match ISaveProvider contract
- `configure()` resolves `savesystem` dep, registers as provider, calls `load_data()` on startup
- `BootstrapConfig.tres` equipment deps: `["stat_modifiers", "savesystem", "data"]`
- `SaveMigrationService.CURRENT_VERSION = 3`; `_migrate_v2_to_v3()` adds `"equipment": {}`
- Tests: method names fixed, MockSaveSystem added, round-trip tests added
- `services.md` equipment deps and CURRENT_VERSION corrected

#### BUG-2: A-02 — SaveSystem: No .bak Recovery ✅
- `_read_from_disk()` extracted to `_try_read_json()` helper
- On main file failure: tries `.bak` before returning `{}`
- Distinct log messages for each failure scenario

#### BUG-3: C-01 — `roll_critical()` assert No-Op in Release ✅
- `assert(multiplayer.is_server(), ...)` → `if not multiplayer.is_server(): return false`
- Contract documented in test

#### BUG-4: B-01/B-02 — StatModifierService, RewardDispatcher, GameSaveService: ServiceNode without reason ✅
- `extends ServiceNode` → `extends Service` in all three (zero SceneTree usage verified)
- `services.md` table rows and footnote ¹ updated
- ADR-003 Ablösung section updated with post-verification note

#### BUG-5: B-03 — ServiceOrchestrator MeshCache Layer Violation ✅
- `WorldService.warmup_mesh_cache()` added — encapsulates all `factory3d` internals
- ServiceOrchestrator S8.8 uses `Services.world.warmup_mesh_cache()` — no direct field access

#### BUG-6 + BUG-11: F-03 + B-05 — Session Teardown Race + Double Wrapper ✅
- `_is_session_active()` (GameManager state query, always false post-transition) removed
- `is_session_active()` now checks `_session_registry.get_all_names().is_empty()` — race-free
- All 3 call sites updated (`_on_state_changed`, `_teardown_all`, `boot_session S1`)
- Public double-wrapper collapsed into single public method

#### BUG-8: A-03 — services.md divergence ✅
- Fully resolved across BUG-1 (deps, version) and BUG-4 (ServiceNode rows + footnote)

---

## ROUND 8 — Testability/DI Review (AUDIT-04, Section H)

External review pasted by owner, covering 9 testability/DI findings. Tracked in
`docs/audit/AUDIT-04-testability-di.md`. Bug numbering continues from BUG-18 (BUG-7,
BUG-9..BUG-17 remain queued from prior rounds, untouched this round).

#### BUG-18: H-01 — ServiceValidator hardcoded disk load ✅
- `config: BootstrapConfig` injectable property added (analog `ServiceFactory.mounter`)
- `BootstrapConfig.load_default()` static loader added — single source of truth for the path
- `_load_config()` now: return injected `config`, else fallback-load once and cache
- Test: `tests/unit/test_service_validator.gd` (new)

---

## ROUND 13 — BUG-14: C-02 Authority Guards + C-03 Equipment Sync ✅

#### C-02: Authority Guards in alle Services ✅
Alle `receive_*_from_network()` / `on_*_confirmed()` Methoden haben jetzt denselben Guard:
```gdscript
if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
    Logger.log_error("...: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT)
    return
```
- `InventorySystem.on_item_add_confirmed()` — war ungeschützt (C-02 Original-Find)
- `QuestService.receive_start_quest_from_network()`
- `QuestService.receive_complete_quest_from_network()`
- `SkillSystem.receive_add_xp_from_network()`
- `EquipmentService.on_equip_confirmed()` (neu, C-03)
- `EquipmentService.on_unequip_confirmed()` (neu, C-03)

#### C-03: Equipment-Sync in NetworkBridge ✅
- `EquipmentService`: `request_equip()` / `on_equip_confirmed()` / `request_unequip()` / `on_unequip_confirmed()` — exakt dasselbe Muster wie InventorySystem
- `NetworkBridge`: `_equipment: EquipmentService` dep, `send_equip_item()` / `send_unequip_item()`, `@rpc _rpc_equip_item()` / `@rpc _rpc_unequip_item()`
- `BootstrapConfig.tres`: `"equipment"` als dep für `network_bridge` ergänzt

#### Phase S8.6: Late-Network-Inject ✅
NetworkBridge ↔ Services ist ein zirkulärer Dep — beide Seiten brauchen sich gegenseitig.
Lösung: alle vier Services (`inject_network_bridge()` Methode) + Phase S8.6 in `BootPipeline.boot_session()`:
```gdscript
for key in [INVENTORY, QUEST, SKILL_SYSTEM, EQUIPMENT]:
    svc.inject_network_bridge(net)  # via has_method() guard
```
Kein Dep-Zirkel, NetworkBridge wird nach vollem Boot in alle Empfänger injiziert.

#### Tests: 5 neue Tests in test_network_bridge.gd ✅
- `test_inventory_on_item_add_confirmed_allowed_in_tier1`
- `test_inventory_authority_guard_blocks_client_direct_call`
- `test_send_equip_item_tier1_calls_on_equip_confirmed`
- `test_send_unequip_item_tier1_calls_on_unequip_confirmed`
- `test_equipment_inject_network_bridge_sets_field`

---



#### World.gd → WorldService: EventBus statt Services-Locator ✅
- `WorldEvents`: neues Signal `world_scene_node_ready(world_root: Node3D)` + `emit_world_scene_node_ready()`.
- `World.gd`: `Services.world.on_world_scene_ready(self)` → `EventBus.world.emit_world_scene_node_ready(self)`.
- `WorldService.on_ready()`: connected auf `_bus.world().world_scene_node_ready`.
- `WorldService.on_cleanup()`: disconnected das Signal sauber.
- Begründung: World.gd ist ein SceneTree-Node ohne Service-Lifecycle — EventBus ist der korrekte Entkopplungspunkt. Das Timing-Problem (call_deferred feuerte zu früh) ist durch das Signal-Connect in `on_ready()` gelöst.

#### EntityContext.from_services(): Locator entfernt, fail-fast ✅
- Methode bleibt als named stub für Compile-Kompatibilität.
- Inhalt: `push_error()` + `return EntityContext.new()` — feuert sofort wenn unerwartet aufgerufen.
- Produktionspfad: `from_deps()`. Testpfad: `for_test()`.

#### UIContext.from_services(): Locator entfernt, fail-fast ✅
- Gleiche Behandlung wie EntityContext.from_services().
- Produktionspfad: `from_registry()`. Testpfad: `for_test()`.

#### Verbleibender legitimer Services.-Zugriff (dokumentiert, kein Handlungsbedarf)
- `Main.gd:30` — einmaliger Post-Boot-Existenzcheck, kein Business-Logik-Locator.
- `IntegrationTest.gd` — Testinfrastruktur, inspiziert Container von außen (Assertion-Ebene).
- `SimpleTerminal.gd` — Debug-Tool, bewusst außerhalb des DI-Graphen.
- `Services.populate_global/session/clear` in BootPipeline — Container-Befüllung, kein Auflösen.

---



#### ARCH-1 Bugfix: WorldService fehlende Entity-Dep-Resolution ✅
- `_ent_skill`, `_ent_inventory`, `_ent_stat_mod`, `_ent_combat`, `_ent_equipment`, `_ent_interact`
  waren in `configure()` nie aufgelöst — undeclared vars, immer `null`.
  Das ist der Grund warum `_entity_services_injected` immer `false` war und der
  Services-Locator-Fallback in `EntityOrchestrator.spawn_entity()` jedes Mal feuerte.
- Alle 7 Entity-Deps als `var _ent_*` deklariert und in `configure()` via `deps.get_optional()` aufgelöst.
- `_ent_player_states: PlayerStateService` als neue Entity-Dep ergänzt.
- `BootstrapConfig.tres` WorldService-deps: `"playerstates"` hinzugefügt.

#### ARCH-1 Erweiterung: PlayerStateService → TouchInput via DI ✅
- `EntityOrchestrator.set_entity_services()`: `player_states: PlayerStateService = null` (optionaler Parameter, kein Breaking Change).
- `EntityOrchestrator.spawn_entity()`: ruft nach `on_spawn()` `entity.inject_player_states()` auf wenn Methode vorhanden und `_entity_player_states` gesetzt.
- `Player.inject_player_states(svc)`: öffentliche Methode, delegiert an `input.inject_player_states(svc)`.
- `TouchInput._player_states: PlayerStateService` injiziert — kein `Services.player_states` mehr in `_unhandled_input()`.

#### InteractableComponent: Services-Locator-Fallback entfernt ✅
- `Services.interaction_executor` Fallback aus `start_default_interaction()` entfernt.
- Klarer `log_error` wenn `inject_context()` nicht aufgerufen wurde — fail-fast statt silent fallback.

#### MainMenuController: Services.save_system → inject_save_system() ✅
- `_save_system: SaveSystem` injiziertes Feld, `inject_save_system(svc)` public method.
- `ServiceOrchestrator._ready()`: ruft `_inject_save_system_into_main_menu()` nach `boot_global()`.
- `_inject_save_system_into_main_menu()` / `_do_inject_save_system()`: holt SaveSystem aus `_global_registry`, findet `MainMenuController` via `get_tree().current_scene`, injiziert per `call_deferred()`.
- Analog zum HUDManager-UIContext-Pattern (DEBT-2).

---



Verified H-02–H-06/H-09 all fixed (code-read confirmed). Implemented remaining open
structural items from `wildgrove_architektur_analyse.md` and `AUDIT-04`.

#### ARCH-2: ServiceTeardownManager — explizite Boot-Reihenfolge ✅
- `execute(registry, boot_order: Array[String] = [])` — neues optionales Argument
- BootPipeline speichert `_global_boot_order` + `_session_boot_order` nach Dependency-Resolve
- Beide `teardown.execute()` Aufrufe übergeben die jeweilige Order + resetten danach
- Fallback (leeres Array) bleibt kompatibel — kein Breaking Change
- Test: `tests/unit/test_teardown_order.gd` (neu, 5 Tests)

#### DEBT-3: BootPipeline Phase S8.8 warmup_mesh_cache — kein Services-Locator ✅
- `Services.world.warmup_mesh_cache()` → `session_registry.get_service(ServiceKeys.WORLD) as WorldService`
- BootPipeline ist jetzt vollständig ohne Services-Container testbar

#### ARCH-1 + BUG-3: EntityContext.from_deps() + spawn_entity(peer_id) ✅
- `EntityContext.from_deps(skill, inv, factory3d, respawn, data, stat_mod, combat, equip, world, interaction_executor, peer_id)` hinzugefügt — kein Services-Locator
- `EntityContext.from_services()` bleibt als `@deprecated`-Fallback
- `EntityOrchestrator.set_entity_services(...)` — Injection-Methode für alle 10 Entity-Services
- `EntityOrchestrator.spawn_entity(type_id, position, config, peer_id: int = 1)` — peer_id-Parameter
- spawn_entity nutzt from_deps() wenn set_entity_services() aufgerufen wurde; Fallback auf from_services() mit Log-Warn
- `WorldService.configure()` liest entity service deps (alle optional) + ruft `_entity_orchestrator.set_entity_services(...)` auf
- `WorldService.spawn_entity()` leitet peer_id weiter
- `BootstrapConfig.tres` WorldService-deps um entity service deps erweitert (alle optional)
- Test: `tests/unit/test_entity_context.gd` — 6 neue Tests für from_deps() + peer_id

#### DEBT-2: UIContext.from_services() — ServiceRegistry statt Services-Locator ✅
- `UIContext.from_registry(registry: ServiceRegistry)` hinzugefügt — canonical DI-Pfad
- `UIContext.from_services()` bleibt als `@deprecated`-Fallback
- `HUDManager._ui_context_factory: Callable` — default = from_services(), injectable via `set_ui_context_factory()`
- `HUDManager._on_world_scene_ready()` ruft `_ui_context_factory.call()` statt from_services()
- `ServiceOrchestrator.boot_session()` setzt Factory über `get_node_or_null("/root/HUDManager")` nach boot

#### H-06: ServiceInitializer + TeardownManager duck-typing → typsichere Guards ✅
- `scripts/interfaces/core/IServiceLifecycle.gd` erstellt — dokumentiert den Lifecycle-Vertrag
- `ServiceInitializer.run()`: `svc is Service or svc is ServiceNode` statt `has_method("configure")`
- `ServiceInitializer.run_on_ready()`: `svc is Service or svc is ServiceNode` statt `has_method("on_ready")`
- `ServiceTeardownManager.execute()`: `svc is Service or svc is ServiceNode` statt `has_method("on_cleanup")`

---

## QUEUE — P1 Fixes

#### BUG-7: F-01 — ISaveProvider missing `load_save_data()` on restore side ✅
**Won't fix as described — documented instead (verified in AUDIT-03).**
Code-Lese-Analyse: alle Provider lesen State selbst in `configure()` via `get_state_for()`.
Pull-Pattern ist Absicht. `load_save_data()` im Interface würde Push-Architektur erzwingen.
Fix: ISaveProvider.gd dokumentiert das Pull-Pattern explizit mit Beispiel-Code.

---

## DONE — P3 Cleanup

#### OBS-1: ServiceDefinition.interface_type — toter Code ✅
- `@export var interface_type: String = ""` entfernt aus `ServiceDefinition.gd`
- Kein einziger Nutzer im gesamten Codebase (grep-bestätigt)
- Kein Breaking Change: kein `.tres`-File setzt `interface_type`

#### OBS-2: ServiceTicker Fehlerresilienz — bereits implementiert ✅
- `_process()` und `_physics_process()` iterieren rückwärts mit `is_instance_valid()`-Guard
- Ungültige Einträge werden sauber entfernt — kein Handlungsbedarf

#### OBS-3: SaveSystem kein `on_cleanup()` ✅
- `on_cleanup()` ergänzt in `SaveSystem.gd` nach `configure()`
- Leert `_save_providers`, `_loaded_state`, `_active_player_id` — idempotent, sicher bei hartem Exit
- Tests: 3 neue Tests in `tests/unit/test_save_system.gd`
  - `test_on_cleanup_clears_providers()`
  - `test_on_cleanup_clears_active_session()`
  - `test_on_cleanup_is_idempotent()`



---

---

## ROUND 14 — BUG-12: Property-Tests, Lifecycle-Tests, Player.gd Tests ✅

#### E-03: Property-Based Tests für Core Math ✅
- `tests/unit/test_property_based.gd` — 25 Tests in 3 Klassen
- **P-01…P-06:** `calculate_damage()` Invarianten — MIN_DAMAGE-Floor für alle raw/resist-Kombinationen, TRUE-Schaden = raw (crit-immun), monotone Resistenz-Abnahme, Armor-Clamp bei 0.85, Post-condition-Stabilität, final >= 0
- **S-01…S-08:** `get_effective_stat()` Invarianten — Identität, FLAT_ADD-Additivität, PERCENT_ADD/MULTIPLY-Mathematik, Operationsreihenfolge (Vertrag aus StatModifier.gd), cross-stat-Isolation, Endlichkeit
- **M-01…M-08:** `migrate()` Invarianten — Idempotenz, schema_version = CURRENT_VERSION, Downgrade-Erkennung + downgrade_detected-Flag, v0/v1/v2-Chain, non-destructive equipment-Block-Insert, Input-Mutation verhindert

#### B-04: ServiceOrchestrator Lifecycle Tests ✅
- `tests/unit/test_service_orchestrator_lifecycle.gd` — 11 Tests (L-01…L-11)
- `is_session_active()` Race-Condition-frei: Registry-Zustand statt GameManager.get_state()
- Character-Switch: teardown_session() → neue Registry → boot_session() in korrekter Reihenfolge
- begin_session()/end_session() erhalten korrekte player_ids
- teardown_all(): Session-Registry vor Global-Registry (Reihenfolge L-09)
- Fehler-Paths (S2 ohne SaveSystem), Registry-Isolation nach Teardown

#### G-01 + G-02: Player.gd Tests + EnemyNPC Fallback ✅
- `tests/unit/test_player_gd.gd` — 14 Tests (PM/PL/EN)
- **PlayerMover (PM-01…PM-06):** Velocity-Physik, StatModifier-Integration, nil-Safety
- **Player Lifecycle (PL-01…PL-06):** Initial-State FREE, on_despawn() D-02-Fix-Absicherung, nil-safe inject, get_context_actions() ohne Sensor
- **EnemyNPC Fallback (EN-01…EN-04):** G-02 Fallback-Pfad reduziert HP, kein Crash ohne HC, is_dead-Guard, Timer-Null-Safety

## ROUND 15 — I-01: `on_*_confirmed` Public-API-Konsistenz ✅
*(Nachträglich geloggt — der Fix war bereits im Code und in AUDIT-03 als ✅ markiert, aber nie hier verzeichnet. Gegen den Code verifiziert, nicht nur gegen die Audit-Beschreibung übernommen.)*

#### I-01: `_on_*_confirmed` → `on_*_confirmed` öffentlich, typisiert ✅
- `QuestService.on_quest_start_confirmed(quest_id: String, player_id: int = 1)` — public, Authority Guard
- `QuestService.on_quest_complete_confirmed(quest_id: String, player_id: int = 1)` — public, Authority Guard
- `SkillSystem.on_xp_add_confirmed(skill_name: String, amount: int, player_id: int = 1)` — public, Authority Guard
- `receive_*_from_network()`-Wrapper-Schicht vollständig entfernt; `NetworkBridge` ruft `on_*_confirmed()` direkt — konsistent mit `InventorySystem`/`EquipmentService`
- `tests/unit/test_network_bridge_contract.gd` vollständig neu geschrieben: Sichtbarkeit, State-Äquivalenz zu `request_*()`, player_id-Routing, Tier-1-Routing, Abwesenheit der alten `receive_*`-Wrapper

## ROUND 16 — I-02: UI-Controller EventBus-Injektion ✅

#### I-02: `IUIContext.bus()` ersetzt direkten `EventBus.*`-Zugriff in UI-Controllern ✅
- `IUIContext.bus() -> IEventBus` — neuer Accessor, Basis-Vertrag `null` (wie alle anderen Getter)
- `UIContext.from_registry()` löst `IEventBus` aus `ServiceKeys.EVENT_BUS` auf — derselbe Registry-Key wie Services, kein zweiter Adapter
- 10 Controller umgestellt: `ContextButtonController`, `ContextMenuController`, `EquipmentUIController`, `FloatingTextController`, `InteractionButtonController`, `NotificationController`, `PauseMenuController`, `PlayerHPController`, `QuestPanelController`, `SkillPanelController` — alle nehmen jetzt `ctx: IUIContext` entgegen, lesen Events über `_ctx.bus().<namespace>()`; rohe Namespace-Parameter (`UIEvents`/`PlayerEvents`/`Object`) entfernt wo sie parallel zum AutoLoad-Zugriff existierten
- 7 `*Component.build()`-Fabriken + `HUDBuilder.build_all()` geben `ctx` jetzt an die obigen Controller weiter; tote `EventBus.ui`/`EventBus.player`-Lokalvariablen in `HUDBuilder` entfernt
- `ADR-012` dokumentiert die Entscheidung, schließt die UI-Hälfte von H-07/ADR-011 ab; Cross-Referenz von ADR-011 aus gesetzt
- Neuer Review-Blocker in `CONTRIBUTING.md` (2.1 Schichtentrennung + 7.8 Verbotene Muster)
- **Bewusst out-of-scope, als neuer P2-Befund I-02b dokumentiert:** `IEntityContext.get_event_bus() -> Node: return EventBus` — strukturell verwandt (behauptet Testbarkeit, Rückgabetyp verhindert sie), aber unbenutzt und außerhalb dieses Rounds
- **Tests:** `tests/unit/test_ui_context.gd` (8 Tests: Interface-Vertrag, `for_test()`-Isolation, `from_registry()`-Auflösung inkl. Regression auf bestehende Getter) + 3 Controller-Beispieltests (`test_notification_controller.gd`, `test_player_hp_controller.gd`, `test_skill_panel_controller.gd`) — je inklusive Gegenbeweis, dass der echte `EventBus`-AutoLoad die Controller nicht mehr erreicht. Restliche 7 Controller bleiben IV-03 (unverändert offen, nicht Teil dieses Fixes).

## ROUND 17 — I-03: Status-Effekte vollständig verdrahtet ✅

#### I-03: apply_weapon_on_hit() match auf StatusEffect.Kind — POISON + BURN ✅

Der Audit-Befund ("Fundament ohne Haus") war zur Zeit des Schreibens korrekt, wurde aber bereits teilweise behoben: `apply_weapon_on_hit()` existierte und war in `EnemyNPC._on_interacted()` eingehängt. Verbleibende Lücken vor diesem Round:
- `apply_weapon_on_hit()` hardcodiert `apply_poison()` statt per `match` auf `weapon.on_hit_effect` zu dispatchen — BURN wurde nie ausgelöst
- `test_equipment_ui.gd` hatte keinen Positiv-Test für `apply_weapon_on_hit()` mit injiziertem Equipment
- `before_each()` injizierte kein `MockEventBus` → `_bus.ui().emit_floating_text()` hätte im Positiv-Pfad gecrasht

**Fixes:**
- `CombatSystem.apply_weapon_on_hit()`: `match weapon.on_hit_effect` auf `StatusEffect.Kind` — POISON, BURN, unbekannte Werte mit `log_warn`. Stale Kommentare ("steht noch aus", "NICHT verdrahtet") entfernt
- `test_equipment_ui.gd`: `MockEventBus` in `before_each()` + `ServiceKeys.EQUIPMENT` korrekt injiziert; 5 neue `apply_weapon_on_hit`-Tests:
  - `test_apply_weapon_on_hit_does_nothing_without_equipment_service` — Negativ (Combat ohne Dep)
  - `test_apply_weapon_on_hit_with_poison_weapon_registers_status_effect` — Positiv (Giftdolch → 1 StatusEffect)
  - `test_apply_weapon_on_hit_poison_ticks_deal_damage` — Tick-Assertion (exakt 5 HP TRUE-Schaden nach 1s)
  - `test_apply_weapon_on_hit_with_burn_weapon_registers_burn_effect` — BURN-Waffe
  - `test_apply_weapon_on_hit_no_double_stack_same_source_target` — Kein-Stacking-Garantie
  - `test_weapon_without_on_hit_effect_skips_poison` — überarbeitet: prüft jetzt via `apply_weapon_on_hit()` statt direkt

## SPRINT F — Multiplayer-Correctness: Verbleibende Lücken aus Reviewer-Feedback

### F-2: `peer_id` in `WorldService.spawn_entity()` + Callbacks ✅

**Problem:** `WorldService.spawn_entity()` leitete keinen `peer_id`-Parameter weiter.
`RespawnService` und `ChunkManager` nutzten Closures ohne `peer_id` — für World-Entities
(Bäume, Erze, Gegner) korrekt (immer Server-Autorität), aber ein Player-Respawn hätte die
falsche Autorität erhalten.

**Fixes:**
- `WorldService.spawn_entity()`: neuer Parameter `peer_id: int = 1` — kein Breaking Change,
  alle bestehenden Callsites nutzen automatisch den Default.
- Respawn-Closure in `WorldService.on_ready()`: `func(t, p, pid: int = 1) -> Node3D`
  — leitet `pid` an `spawn_entity()` weiter.
- ChunkManager-Closure in `on_world_scene_ready()`: analog aktualisiert.
- `RespawnService._do_respawn()`: übergibt explizit `peer_id=1` an Spawn-Callback
  (dokumentiert: World-Entities sind immer Server-autoritär; Player-Respawn würde
  einen Queue-Eintrag mit `peer_id`-Feld brauchen — als zukünftiger Erweiterungspunkt markiert).
- `RespawnService`-Docstring: Callable-Signatur auf `(type_id, position, peer_id: int)` aktualisiert.

**Tests:** `test_respawn_service.gd` — 2 neue Tests:
- `test_respawn_calls_spawn_callback_with_peer_id_1` — verifiziert peer_id=1 für World-Entities
- `test_respawn_spawn_callback_old_signature_still_works` — Rückwärtskompatibilität (Callable ohne peer_id)

`test_world_service.gd` — 2 neue Tests:
- `test_spawn_entity_accepts_peer_id_parameter` — Signatur akzeptiert peer_id ohne Crash
- `test_spawn_entity_default_peer_id_is_1` — Default greift ohne explizite Angabe

---

### F-1: Custom Spawn/Despawn via `MultiplayerSpawner`-Signale ✅

**Problem:** `_setup_multiplayer_spawner()` nutzte `add_spawnable_scene()` mit `.gd`-Pfaden.
`MultiplayerSpawner.add_spawnable_scene()` akzeptiert ausschließlich `.tscn`-Pfade —
`.gd`-Pfade werden zur Laufzeit beim ersten Spawn-Versuch abgelehnt.

**Entscheidung gegen `.tscn`-Wrapper:** Das Projekt instanziiert Entities bewusst via
`GDScript.new()` (EntityRegistry, EntityPool). 8 leere `.tscn`-Wrapper-Dateien nur für
den MultiplayerSpawner wären Architektur-Fremdkörper.

**Fixes:**
- `EntityRegistry.get_path_to_type_map()` — neue Methode: gibt `{ script_path: type_id }` zurück.
  Umgekehrte Abbildung der internen `_definitions`-Map. Gibt eine Kopie zurück (kein shared state).
- `EntityOrchestrator.get_registry()` — neuer Accessor: gibt `_registry` nach außen für
  `WorldService._setup_multiplayer_spawner()`.
- `WorldService._setup_multiplayer_spawner()` umgeschrieben:
  - `ms.spawn_function`: Closure über `path_map` (einmalig gebaut) + `registry_ref`.
    Empfängt `data` (script_path-String vom Server), löst via `path_map` zu `type_id` auf,
    ruft `registry_ref.instantiate(type_id)` auf.
    Kein `add_child`, kein `on_spawn`, kein UUID-Tracking — der Spawner übernimmt `add_child`,
    State-Sync läuft via `MultiplayerSynchronizer`.
  - `ms.despawn_function`: Closure ruft `node.queue_free()` auf (Client-seitig ausreichend,
    Server hält autoritativen Zustand).
  - Log-Meldung zeigt jetzt `path_map.size()` statt hardcodierter 8.

**Tests:**
- `test_entity_registry_path_map.gd` (neu, 7 Tests): Leer-Map, Key/Value-Präsenz,
  Zwei-Typen, Leerpfad-Exclusion, Bijektivität, Kopie-Isolation.
- `test_world_service.gd` (4 neue Tests): Path-Map ≥ 8 Einträge, `player`-type_id vorhanden,
  keine leeren Keys, `get_registry()` Rückgabetyp.

---

### F-3: Player + EnemyNPC `MultiplayerSynchronizer` `replication_interval` ✅

**Problem:** `_setup_multiplayer_sync()` in `Player.gd` und `EnemyNPC.gd` setzte
`replication_interval` nicht → Sync lief per-frame (60+ Hz). Unnötige Netzwerklast,
besonders bei vielen gleichzeitigen Entities.

**Analyse Authority-Richtung:** Der Reviewer-Hinweis "Clients sehen andere Clients nicht"
ist in der aktuellen Implementierung bereits korrekt gelöst:
`EntityOrchestrator.spawn_entity()` ruft `set_multiplayer_authority(peer_id)` nach
`add_child()` und *vor* `on_spawn()`. `_setup_multiplayer_sync()` läuft in `on_spawn()` —
der Synchronizer wird also immer *nach* korrekter Authority erstellt.
Ein einzelner `MultiplayerSynchronizer` auf einem Node sendet vom Autoritäts-Peer zu allen
anderen, was Client→Server→andere-Clients korrekt abdeckt.

**Fixes:**
- `Player._setup_multiplayer_sync()`:
  - `sync.replication_interval = 0.05` (20 Hz) gesetzt
  - Kommentar erklärt Autorität + Sync-Richtung explizit
  - Kommentar-Header von "Sprint D" auf "Sprint E / F-3" aktualisiert
  - Log-Meldung nennt jetzt "20Hz"
- `EnemyNPC._setup_multiplayer_sync()`:
  - `sync.replication_interval = 0.1` (10 Hz) gesetzt
  - Begründung im Kommentar: Gegner weniger latenz-kritisch als Player
  - Log-Meldung nennt jetzt "10Hz"

**Tests:** `test_player_gd.gd` — 6 neue Tests (F3-01…F3-06):
- F3-01: Player hat `MultiplayerSync`-Child nach `on_spawn()`
- F3-02: Player-Interval = 0.05s (20 Hz)
- F3-03: Player-Config hat 3 Properties (position, rotation, velocity)
- F3-04: Authority-Reihenfolge — kein Crash wenn `set_multiplayer_authority()` vor `on_spawn()`
- F3-05: EnemyNPC-Stub-Sync hat Interval = 0.1s (10 Hz)
- F3-06: EnemyNPC-Sync hat 2 Properties (position, rotation — kein velocity)

---

### F-4: Docs + ADR-010 ✅

**`docs/services.md`:**
- `WorldService`-Deps-Zeile korrigiert: war `savesystem, data` (veraltet), jetzt
  `savesystem, event_bus` (required) + alle optionalen Deps explizit aufgelistet.
- `EntityOrchestrator`-Zeile: Hinweis auf `multiplayer_authority(peer_id)` ergänzt.
- `EntityRegistry`-Zeile: `get_path_to_type_map()` dokumentiert.
- `EnemyNPC`-Zeile: Sync-Interval 10 Hz vermerkt.
- Neuer Abschnitt "Multiplayer-Spawn-Replikation": Custom Spawn/Despawn-Callable-Muster,
  Begründung gegen `.tscn`-Wrapper.
- Neuer Abschnitt "RespawnService spawn_callback-Signatur": `peer_id`-Parameter dokumentiert.
- Neuer Abschnitt "MultiplayerSynchronizer-Intervalle": 20 Hz / 10 Hz, Sync-Richtung.

**`docs/adr/010-multiplayer-authority-tiers.md`:**
- Status-Header: Sprint-F-Konkretisierung vermerkt.
- Neuer Unterabschnitt "Spawn-Replikation (Sprint F)": Entscheidung gegen `.tscn`-Wrapper,
  Custom Callable-Mechanismus, Path-Map-Strategie, Authority-Reihenfolge beim Sync-Setup.

---

## Sprint F — KOMPLETT ✅

Alle drei Reviewer-Lücken geschlossen:
- **F-1** ✅ Custom Spawn/Despawn via `MultiplayerSpawner`-Signale (`.gd`-Pfad-Problem behoben)
- **F-2** ✅ `peer_id` in `WorldService.spawn_entity()` + alle Callbacks
- **F-3** ✅ `replication_interval` 20 Hz (Player) / 10 Hz (EnemyNPC); Authority-Reihenfolge verifiziert
- **F-4** ✅ ADR-010 + services.md nachgeführt



### SPRINT A — Legacy-Cleanup ✅

- `Services.gd` gelöscht; Autoload aus `project.godot` entfernt
- `from_services()`-Stubs gelöscht (`EntityContext`, `UIContext`); `HUDManager`-Default → fail-fast `push_error`
- `EntityOrchestrator.spawn_entity()`: `_entity_services_injected`-Guard + else-Fallback entfernt — `from_deps()` ist einziger Pfad
- `BootPipeline`: `Services.populate_global/session/clear*()`-Calls entfernt
- `SimpleTerminal.gd`, `Main.gd`, `IntegrationTest.gd`: alle `Services.xyz`-Live-Calls → `ServiceOrchestrator.get_service()` (neu hinzugefügt)
- Alle `# MIGRATION-010:`, `# TD-NN:`, `# H-0N:`, `# ARCH-NN:`, `# DEBT-NN:`, `# BUG-NN:`-Kommentare aus scripts/ + tests/ entfernt (159 + 50 Dateien)
- Keine `@deprecated`-Tags mehr vorhanden

### SPRINT B — `@rpc`-Annotationen + SessionManager ✅

#### `@rpc`-Fix: `call_local` → `call_remote` in `NetworkBridge`
Alle 6 `_rpc_*`-Methoden hatten `"call_local"` — damit führte der sendende Client jede
RPC-Funktion auch lokal aus. Der `_is_authority()`-Guard verhinderte zwar State-Mutation,
aber der Aufruf selbst war semantisch falsch und unnötig.
Geändert: `_rpc_add_item`, `_rpc_start_quest`, `_rpc_complete_quest`, `_rpc_add_xp`,
`_rpc_set_state`, `_rpc_equip_item`, `_rpc_unequip_item` → `"call_remote"`.

#### `send_set_state()` ergänzt in `NetworkBridge`
`_rpc_set_state()` existierte ohne öffentlichen `send_set_state()`-Wrapper. Analog zu allen
anderen `send_*()`-Methoden ergänzt.

#### `SessionManager` — neuer globaler Service
`scripts/services/SessionManager.gd` (extends ServiceNode, global scope):
- `create_server(port, max_clients)` → ENetMultiplayerPeer.create_server()
- `join_server(address, port)` → ENetMultiplayerPeer.create_client()
- `close()` → Peer entfernen, Slots leeren
- Player-Slot-Registry: `register_player_slot(peer_id, player_id)` / `get_player_id_for_peer(peer_id)`
- Lauscht auf `EventBus.system.host_game_requested` / `join_game_requested` (von MainMenuController)
- Emittiert `EventBus.system.hosting_started` / `joined_as_client` / `connection_to_server_failed` / `network_peer_disconnected`
- Emittiert eigene Signale: `peer_joined`, `peer_left`, `server_started`, `client_connected_to_server`, `client_connection_failed`, `server_connection_lost`

#### `ServiceKeys.SESSION_MANAGER` ergänzt
#### `BootstrapConfig.tres` — SessionManager in `global_services` eingetragen (load_steps 27→28)
#### `ServiceInstaller` — `SESSION_MANAGER` in `CRITICAL_GLOBAL` ergänzt

#### `SystemEvents.gd` — 6 neue Multiplayer-Events
`host_game_requested(port)`, `join_game_requested(address, port)`, `hosting_started(port)`,
`joined_as_client()`, `connection_to_server_failed()`, `network_peer_disconnected()`

#### `BootPipeline` — Phase S8.7: Lokaler Spieler-Slot registrieren
Nach Phase S8.6 (Late-Network-Inject): `SessionManager.register_player_slot(local_peer, player_id)`.

#### `ServiceOrchestrator`
- `_connect_session_manager()` nach `boot_global()`: verbindet `client_connected_to_server` →
  `_on_client_connected_to_server()` — Auto-Boot-Session für Clients mit player_id `"client_N"`.

#### `MainMenuController` — Multiplayer-UI State Machine
4 Zustände: `CHARACTERS`, `NET_SETUP`, `HOST_ACTIVE`, `CONNECTING`.
[Multiplayer]-Button → NET_SETUP-Panel mit Host- und Join-Sektion.
Host-Flow: Port-Eingabe → `emit_host_game_requested()` → `hosting_started` → HOST_ACTIVE → Char-Wahl.
Join-Flow: IP+Port → `emit_join_game_requested()` → `joined_as_client` (auto via Orchestrator) → PLAYING.

#### `MainMenu.tscn` — NetPanel-Nodes ergänzt
`NetPanel/HostSection/{HostPortEdit, StartHostButton}`,
`NetPanel/JoinSection/{JoinAddressEdit, JoinPortEdit, StartJoinButton}`,
`NetPanel/BackButton`, `CenterContainer/MultiplayerButton`, `CenterContainer/StatusLabel`.

#### Tests: `tests/unit/test_session_manager.gd` — 12 Tests (SM-01…SM-12)
- `@rpc("any_peer", "call_remote", "reliable")` auf alle `_rpc_*`-Methoden in NetworkBridge
- `SessionManager`: create_server/join_server, peer_connected/disconnected, Player-Slot-Registry
- Host/Join-UI (minimal)
- `NetworkBridge.send_*()` für Quest, Inventory, Equipment (analog send_add_xp)

### SPRINT C — World Authority + EnemyAI-Gate ✅

- `set_multiplayer_authority(1)` in `EnemyNPC._ready()`, `IronOre._ready()`, `OakTree._ready()`, `AnimalBase._ready()`, `PetComponent._ready()`
- `_physics_process()` hinter `if not is_multiplayer_authority(): return` in: `EnemyNPC`, `AnimalBase`, `PetComponent`
- `EnemySpawner` ist `RefCounted` (kein Node) — kein Authority-Call nötig; Authority der gespawnten Entities liegt bei `EnemyNPC` selbst

### SPRINT E — Multiplayer-Correctness: Entity Authority + Spawning + Snapshot-Timing ✅

**Gefundene Lücken nach Sprint D (Code-Review):**

#### E-1: `set_multiplayer_authority(peer_id)` auf gespawnten Entities ✅
- `EntityOrchestrator.spawn_entity()`: nach `add_child()` wird `entity.set_multiplayer_authority(peer_id)` aufgerufen wenn `peer_id != 1`
- Server-Entities (EnemyNPC, Tiere, Objekte) behalten peer 1 aus `_ready()` — idempotent, kein Overhead

#### E-2: `WorldSpawner` übergibt `peer_id` beim Player-Spawn ✅
- `WorldSpawner.spawn_all(world_root, peer_id: int = 1)` — neuer Parameter
- `WorldService.on_world_scene_ready()`: ermittelt `local_peer` via `_session_manager.get_local_peer_id()` und übergibt ihn an `spawn_all()`
- `WorldService`: `_session_manager: SessionManager` neue optionale Dep; in `configure()` aufgelöst
- `BootstrapConfig.tres`: `"session_manager"` zu `world`-deps ergänzt (Global-Service, via fallback_registry auflösbar)

#### E-3: `MultiplayerSpawner` für Welt-Entities ✅
- `WorldService._setup_multiplayer_spawner(world_root)`: erstellt `MultiplayerSpawner`, registriert alle 8 Entity-Pfade, hängt ihn als Child in `world_root`
- Aufruf in `on_world_scene_ready()` vor `spawn_all()` — nur wenn Server mit aktivem Peer
- Solo (Tier 1) und Tests: Bedingung nicht erfüllt, kein Spawner, kein Overhead

#### E-4: Initial-Snapshot-Timing korrigiert ✅
- **Vorher (Sprint D, falsch):** Server schickt Snapshot bei `peer_connected` — Client hat noch keine Session, `apply_remote_state()` war geblockt
- **Jetzt:** Client fordert Snapshot selbst an nach vollständigem Session-Boot
- `NetworkBridge.send_request_initial_state()`: Client-Methode, ruft `rpc_id(1, "_rpc_client_requests_initial_state")`
- `NetworkBridge._rpc_client_requests_initial_state()`: `@rpc("any_peer", "call_remote", "reliable")` — Server antwortet mit `rpc_id(requester, "_rpc_receive_initial_state", state)`
- `BootPipeline` Phase S8.9: ruft `net.send_request_initial_state()` nach S8.8 (MeshCache)
- `SaveSystem.apply_remote_state()`: Guard auf `_active_player_id` entfernt — Client hat zu diesem Zeitpunkt bereits eine aktive Session

#### Initial-Snapshot an neue Peers
- `SaveSystem.get_full_state()` — gibt `_loaded_state.duplicate()` zurück (flache Kopie)
- `SaveSystem.apply_remote_state(state)` — übernimmt Server-Snapshot auf Client; Guard wenn Session bereits aktiv
- `NetworkBridge._save_system: SaveSystem` — neue optionale Dep; in `configure()` aufgelöst
- `NetworkBridge._on_peer_connected()`: Server ruft `rpc_id(peer_id, "_rpc_receive_initial_state", state)` nach `emit_save_pre_flush()` (via `get_full_state()`)
- `NetworkBridge._rpc_receive_initial_state(state)`: `@rpc("authority", "call_remote", "reliable")` — Client empfängt und ruft `_save_system.apply_remote_state()` auf
- `BootstrapConfig.tres`: `"savesystem"` zu `network_bridge`-deps ergänzt

#### MultiplayerSynchronizer — Player
- `Player._setup_multiplayer_sync()`: erstellt `MultiplayerSynchronizer` mit `SceneReplicationConfig` für `position`, `rotation`, `velocity`
- Aufruf in `on_spawn()` nach `set_physics_process(true)`

#### MultiplayerSynchronizer — EnemyNPC
- `EnemyNPC._setup_multiplayer_sync()`: erstellt `MultiplayerSynchronizer` für `position`, `rotation` (kein `velocity` — Clients führen keinen `_physics_process` aus, Sprint C)
- Aufruf in `_ready()` nach `EnemyAttack.setup_interactable()`

---

## ROUND 18 — I-02b: IEntityContext.get_event_bus() → IEventBus ✅

- `IEntityContext.get_event_bus()` Rückgabetyp `Node` → `IEventBus`, Default-Impl gibt `null` (kein AutoLoad-Hardcode mehr)
- `EntityContext`: `_bus: IEventBus`-Feld + `get_event_bus()` Override; `from_deps()` nimmt optionalen `bus`-Parameter
- `EntityOrchestrator.spawn_entity()`: leitet `_bus` an `EntityContext.from_deps()` weiter
- `test_entity_context.gd`: 3 alte Tests durch 3 neue ersetzt — `null`-by-default, MockEventBus-Injectable, Basis-Interface gibt kein AutoLoad zurück

---

## ROUND 19 — II-02: CombatSystem.player_melee_damage() SkillSystem als Dep ✅

- `CombatSystem`: `_skill_system: SkillSystem`-Feld, in `configure()` über `ServiceKeys.SKILL_SYSTEM` (optional) gelesen
- `player_melee_damage(skill_system, player_id)` → `player_melee_damage(player_id)` — Parameter entfernt
- `EnemyNPC._on_interacted()`: `var skill`-Lokale entfernt, `combat.player_melee_damage("player")` direkt
- `BootstrapConfig.tres`: `deps` für `combat` um `"skill_system"` erweitert
- `test_combat_system.gd`: `before_each()` injiziert `MockEventBus`; Skill-Test erstellt eigene `CombatSystem`-Instanz mit `SkillSystem`-Dep; alle seeded-RNG-Tests bekommen `EVENT_BUS` aus `_bus`

---

## ROUND 20 — I-05: Authority Guards (retroaktiv verifiziert) ✅

Alle drei Methoden (`on_item_add_confirmed`, `on_equip_confirmed`, `on_unequip_confirmed`) haben Guards bereits seit C-02 (Round 13). Finding war zum Zeitpunkt des Audits korrekt; wurde seither behoben. Keine Code-Änderungen nötig.

---

## ROUND 21 — II-01: lint_services_access.sh ✅

- `scripts/ci/lint_services_access.sh` erstellt (analog zu `lint_servicenode.sh`)
- Prüft: keine Live-Calls auf `Services.<name>` in `scripts/ui/`, `scripts/player/`, `scripts/world/combat/`, `scripts/world/objects/`, `scripts/interaction/`
- Kommentare und Docstrings korrekt ausgeschlossen (inline `#`-Splitting)
- ALLOWLIST für dokumentierte Ausnahmen (derzeit leer — alle Verletzungen behoben)
- Läuft sauber durch auf aktuellem Stand: `OK  Keine direkten Services.xyz-Calls in UI/Entity-Schichten gefunden.`

---

## ROUND 22 — IV-03: 7 UI-Controller Tests ✅

Neue Testdateien für verbleibende Controller:
- `test_context_button_controller.gd` — proximity_changed → Button sichtbar; AutoLoad-Isolation
- `test_context_menu_controller.gd` — request_context_menu-Verbindung; show([]) kein Crash; Isolation
- `test_floating_text_controller.gd` — xp_gained → Label spawnt in Canvas; Isolation
- `test_interaction_button_controller.gd` — proximity_changed → Button aktiv; Isolation
- `test_pause_menu_controller.gd` — _on_save() emittiert save_requested auf Mock; Isolation
- `test_quest_panel_controller.gd` — quest_started → panel sichtbar; Isolation

Jede Datei: 3 Tests — Signal-Verbindung auf injiziertem Bus, Positiv-Pfad via Mock, AutoLoad-Isolation.

---

## ROUND 23 — III-02/III-03/IV-01/IV-02 + AUDIT-03 Abschluss ✅

**III-02:** ADR-004 nachgeführt — Entscheidungstabelle, Negativ/Risiken, Tech-Debt-Abschnitt alle auf ✅-Stand (I-01 war Round 15).

**III-03:** ADR-001 Ablösungsbedingung war bereits korrekt formuliert (SceneTree-Kopplung, nicht Constructor-Syntax). Retroaktiv verifiziert, kein Handlungsbedarf.

**IV-01:** Round-Trip-Tests für alle drei Services nachträglich verifiziert — bereits vorhanden in `test_inventory_system.gd`, `test_quest_service.gd`, `test_skill_system.gd`.

**IV-02:** `test_network_bridge_contract.gd` — 3 neue Tier-Tests:
- `test_tier1_request_add_xp_calls_on_confirmed_locally` — kein Peer → lokaler Aufruf
- `test_tier2_request_add_xp_does_not_call_on_confirmed_locally` — MockNetworkBridgeAsPeer → kein lokaler State
- `test_tier2_skill_request_add_xp_routes_via_rpc_not_local` — SkillSystem._network = MockBridge → XP bleibt 0

`MockNetworkBridgeAsPeer` überschreibt `has_peer()→true`, `is_server()→false`, `get_local_peer_id()→2` und trackt RPC-Aufrufe ohne echtes SceneTree-Multiplayer.

**AUDIT-03 komplett:** Alle 20 Findings (I-01 bis IV-03) sind ✅.



Merged into `docs/audit/AUDIT-03-meta-review.md`.
Completed findings marked ✅ and removed from open-items list as each bug is fixed.

---

## ROUND 24 — Runtime-Verified Bugs (erste echte Godot-Ausführung + GUT-Lauf)

Erster Durchlauf mit tatsächlich ausgeführtem Godot-Build (`wildgrove_2026-07-02_01-34-14.log`)
und GUT-Testlauf (`gut-output.log`, 95 von 1002 Tests fehlgeschlagen). ReviewAgent.md Punkt "Nothing
has been executed" ist damit für diese Session hinfällig — mehrere Befunde sind runtime-only
und wären durch reines Lesen nicht aufgefallen.

#### BUG-19: `BootstrapConfig.tres` — ungültiges `#`-Kommentarzeichen zerstört WorldService-Deps ✅
- **Root Cause:** `.tres` ist INI-artig, Kommentare beginnen mit `;`, nicht `#`. Eine Zeile
  `# ARCH-1: entity service deps für EntityContext.from_deps() — alle optional.` direkt vor
  `Resource_worldservice`s `deps`-Property hat die Parser-Zuordnung zerstört — `deps` fiel
  still auf `[]` zurück statt der 15 deklarierten Einträge.
- **Kaskade (alles ein einziger Root Cause, bestätigt durch Logzeilen 219–392 und den
  GUT-Lauf mit identischer `require('event_bus') FEHLT`-Signatur in 24+ Tests):**
  - `ServiceDeps.require('event_bus')` in `WorldService.configure()` schlägt fehl → `_bus` bleibt `null`.
  - `WorldService.on_ready()` crasht bei `_bus.world()` ("Nonexistent function 'world' in base 'Nil'"),
    bevor `respawn.set_spawn_callback()` erreicht wird.
  - `RespawnService.on_tick()`: Assertion "`_spawn_cb` fehlt" — direkte Folge des obigen Crashs.
  - `WorldGenerationService` wird ebenfalls nicht injiziert (`WARN: WorldGenerationService fehlt`).
- **Fix:** `#` → `;` in `config/BootstrapConfig.tres`. Keine Code-Änderung nötig, reiner Datenfehler.
- **Sweep:** `grep -rn "^#" --include=*.tres .` — keine weiteren Treffer im Projekt.
- Test: `test_bootstrap_config_integration.gd::test_world_service_deps_are_fully_declared` (neu) —
  prüft die geladenen `deps`-Werte direkt statt nur Auflösbarkeit (die bestehenden Tests hätten
  eine leere `deps`-Liste nicht bemerkt, da weniger Deps für den Resolver *leichter* aufzulösen sind).

#### BUG-20: `ServiceInstaller.RECOMMENDED_SESSION` — fehlende Array[String]-Typisierung ✅
- **Root Cause:** `const RECOMMENDED_SESSION := ["respawn", ...]` (Typinferenz via `:=`) ergibt
  einen untypisierten `Array`, nicht `Array[String]`. `_check(recommended: Array[String])`
  erwartet aber den typisierten Array — Engine-Fehler "Invalid type in function '_check'... argument 3"
  beim Aufruf, `install_session()` liefert dadurch `false` zurück.
- **Symptom:** `Phase C7 FAIL — kritischer Session-Service fehlt`, obwohl alle kritischen Services
  (`CRITICAL_SESSION`) tatsächlich registriert waren — der Fehler lag ausschließlich in der
  Typisierung der *empfohlenen* (nicht kritischen) Liste.
- **Fix:** `const RECOMMENDED_SESSION: Array[String] = [...]` — explizite Typisierung.
- Test: `tests/unit/test_service_installer.gd` (neu, 4 Tests) — Typ-Check direkt + Verhaltens-Tests
  für install_session() mit/ohne kritische bzw. empfohlene Services.

#### BUG-21: `MainMenuController.inject_save_system()` — nie aufgerufen, Charakterliste immer leer ✅
- **Root Cause:** `inject_save_system()` existiert seit ADR-012 als vorgesehener DI-Punkt, aber
  kein Aufrufer wurde je gebaut (`ServiceOrchestrator._wire_hud()` deckt nur die Session-HUD ab,
  nicht das App-Scope-MainMenu — dokumentiert, aber nie umgesetzt, siehe ADR-012 Zeile 83).
  `_save_system` blieb dauerhaft `null`.
- **Symptom:** `_refresh_character_list()` loggt `SaveSystem nicht injiziert.` und bricht ab —
  gespeicherte Charaktere erscheinen nie im Hauptmenü, Spieler kann nie einen bestehenden
  Spielstand fortsetzen (nur "Neuer Charakter" funktioniert, da das ohne SaveSystem auskommt).
- **Fix:** Push-Pattern analog `WorldScopeInitializer` (bereits etabliert, kein neuer Mechanismus):
  - `scripts/ui/MenuScopeInitializer.gd` (neu) — Child-Node in `MainMenu.tscn`, emittiert
    `menu_ready(menu_root: Control)` in `_ready()`.
  - `MainMenu.tscn`: `MenuScopeInitializer`-Node unter Root ergänzt.
  - `ServiceOrchestrator._ready()`: `_watch_for_menu_initializer()` — `get_tree().node_added`
    lauscht **dauerhaft** (nicht one-shot wie beim World-Pendant, da MainMenu bei jedem
    `main_menu_requested` neu geladen wird) auf `MenuScopeInitializer`-Instanzen und injiziert
    `SaveSystem` aus dem App-Scope in den MainMenuController-Root.
- Test: `tests/unit/test_main_menu_controller.gd` (neu, 3 Tests) — Injektion füllt Charakterliste,
  fehlende Injektion lässt sie leer (reproduziert exakt den Log-Befund), `MenuScopeInitializer`
  emittiert den korrekten Parent.
- `docs/services.md`: BUG-21-Hinweis im EventBus/DI-Abschnitt ergänzt (kein `IUIContext`-Fall,
  separater Mechanismus).

#### BUG-22: `TerminalController.handle_button_input()` — `global_position` auf Touch-Events ✅
- **Root Cause:** `InputEventScreenTouch`/`InputEventScreenDrag` haben nur `position` (Viewport-
  lokal), kein `global_position` — das existiert nur auf `InputEventMouseButton`/`MouseMotion`.
  Der Code griff für beide Eventfamilien einheitlich auf `.global_position` zu.
- **Symptom:** Bei jedem Touch auf den Terminal-Toggle-Button: `Invalid access to property or key
  'global_position' on a base object of type 'InputEventScreenTouch'` (Zeilen 25 + 30, wiederholt
  bei jedem Touch — betrifft ausschließlich mobile/Touch-Eingabe, Maus war nie betroffen).
- **Fix:** `_event_position(event: InputEvent) -> Vector2` Helper — liefert `global_position` für
  Maus-Events, `position` für Touch/Drag-Events. Ersetzt alle 3 `.global_position`-Zugriffe in
  `handle_button_input()` (inkl. Zeile 34, die denselben Bug für Drag noch nicht gezeigt hatte,
  aber denselben Fehler produziert hätte).
- Test: `tests/unit/test_terminal_controller.gd` (neu) — Drag/Toggle mit `InputEventScreenTouch`
  und `InputEventScreenDrag`, keine Errors, Button bewegt sich korrekt.

**Nicht Teil dieser Runde (aus GUT-Log ersichtlich, aber nicht Ursache der App-Log-Crashes):**
`require('savesystem') FEHLT` (10 Vorkommen) und diverse `GameSave`/`Equipment`-Fehler in
Tests, die eigene Mock-Wiring-Lücken zu sein scheinen (unverifiziert) — als Folgearbeit
vorgemerkt, nicht in dieser Runde angefasst.

`QueuePresentKHR failed / VK_ERROR_SURFACE_LOST_KHR` am Logende: Vulkan-Renderer-/Fenster-Fehler
beim Schließen, kein GDScript-Code-Pfad betroffen — keine Änderung, als Infra-Beobachtung notiert.

---

## ROUND 25 — Regression + systemischer Test-Fixture-Rückstand (neuer GUT-Lauf: 99 Failing, neues Game-Log)

Ausgangslage: Nutzer hat nach Runde 24 ein frisches Game-Log
(`wildgrove_2026-07-02_01-53-45.log`) und einen frischen GUT-Lauf
(`gut-test-log__2_.zip`, 99/1010 Failing, vorher 95/1002) geliefert.

#### BUG-23: BUG-21-Fix hält im echten Betrieb nicht — MainMenuController/SaveSystem-Injection

Das neue Game-Log zeigt den EXAKT gleichen Fehler wie vor dem BUG-21-Fix in
Runde 24 ("[ERROR] [MainMenuController] SaveSystem nicht injiziert."), obwohl
BUG-21 als ✅ dokumentiert war. Auffällig: im Log fehlen komplett die
INFO-Zeilen von `BootPipeline.boot_app()` (z. B. "APP BOOT START", "Phase 1
OK" etc.) vor dem Fehler — das deutet darauf hin, dass `ServiceOrchestrator`
(Autoload #4) zum Zeitpunkt von `MainMenuController._ready()` noch nicht
(vollständig) gelaufen ist, entgegen der eigentlich garantierten
Autoload-vor-Hauptszene-Reihenfolge. Konnte die genaue Ursache dafür NICHT
zweifelsfrei statisch verifizieren (kein Godot zum Ausführen verfügbar) —
siehe Diagnose-Log unten für den nächsten Capture.

Root-Cause-unabhängiger Fix (robust gegen die exakte Ready-Reihenfolge):
- `MainMenuController.inject_save_system()` ruft jetzt selbst
  `_refresh_character_list()` auf, wenn die aktuelle Ansicht CHARAKTERE zeigt
  (Selbstheilung — die Charakterliste füllt sich, sobald die Injektion
  eintrifft, egal wann).
- Log-Level für "SaveSystem noch nicht injiziert" von ERROR auf WARN
  runtergestuft (erwarteter Zwischenzustand, kein echter Fehler — hat auch
  GUT-Tests unnötig als failed markiert).
- `ServiceOrchestrator._ready()`: Diagnose-Log als allererste Zeile, damit
  ein künftiger Log-Capture sofort zeigt ob/wann der Autoload überhaupt
  läuft.
- Tests in `test_main_menu_controller.gd` aktualisiert/ergänzt (Selbstheilung
  jetzt explizit getestet).

**NICHT abgeschlossen** — falls der nächste Log-Capture (mit dem neuen
Diagnose-Log) zeigt, dass `ServiceOrchestrator` wirklich zu spät oder gar
nicht läuft, ist das ein separater, tieferliegender Boot-Order-Bug, der noch
untersucht werden muss.

#### BUG-24: `WorldService.configure()` — `event_bus` fälschlich `.require()` statt `.get_optional()` ✅

Einzige der ~15 Deps in `WorldService.configure()`, die `.require()` nutzte —
im Widerspruch zum eigenen Doc-Kommentar der Testdatei ("configure() ohne
optionale Deps → kein Crash, null-Guards greifen") und zu
`test_configure_without_deps_does_not_crash()`. Fix: `get_optional()` +
Null-Guards an allen `_bus`-Nutzungsstellen (`on_ready()`, `on_cleanup()`,
`on_world_scene_ready()`). Behebt 7 von 9 Failures in
`test_world_service.gd` (die restlichen 2 sind ein separates, unten
vermerktes EntityOrchestrator-Problem).

#### Systemischer Test-Fixture-Rückstand: fehlende `MockEventBus`/`SaveSystem`-Injection ✅ (teilweise)

Dominante Fehlersignatur im neuen GUT-Lauf: `require('event_bus') FEHLT`
(225×) und `require('savesystem') FEHLT` (92×) über 29 Testdateien verteilt.
Ursache: mehrere Services verlangen `event_bus`/`savesystem` inzwischen als
Pflicht-Dependency (`.require()`), aber viele `before_each()`-Fixtures wurden
nie mit `MockEventBus`/`SaveSystem`-Instanzen nachgezogen — Runde 24 war der
ERSTE echte GUT-Lauf überhaupt, das war vorher nie sichtbar.

Diese Runde gefixt: `test_game_manager.gd` (11), `test_network_bridge.gd`
(8 von 11 — 3 sind separate, unten vermerkte Probleme),
`test_world_service.gd` (7 von 9 via BUG-24).

**NICHT abgeschlossen** — noch offen (gleiche Ursache, mechanisch
nachziehbar): `test_boot_pipeline.gd`, `test_player_state_service.gd`,
`test_harvestable_entity.gd`, `test_game_save_service_signals.gd`,
`test_inventory_system.gd`, `test_network_bridge_contract.gd`,
`test_service_factory.gd`, `test_service_validator.gd`,
`test_session_manager.gd`, `test_bootstrap_config_integration.gd`,
`test_combat_system.gd`, `test_equipment_service.gd`,
`test_game_save_service.gd`, `test_property_based.gd`, `test_quest_npc.gd`,
`test_quest_service_signals.gd`, `test_stat_modifier.gd`,
`test_player_gd.gd`, `test_player_state_service_signals.gd`,
`test_quest_custom_trigger.gd`, `test_quest_service.gd`,
`test_service_deps.gd`, `test_service_installer.gd`,
`test_service_orchestrator_lifecycle.gd`, `test_skill_system_signals.gd`.

#### Separat vermerkt, NICHT in dieser Runde angefasst (andere Ursache):
- `EntityOrchestrator.spawn_entity()` loggt ERROR ("Kein world_root") bei
  absichtlichen Negativ-Pfad-Tests (uninitialisiert) — GUT markiert das als
  "Unexpected Error" obwohl der Test genau das erwartet. Betrifft
  `test_world_service.gd` (2 Tests) und `test_network_bridge.gd` (1 Test).
- `test_join_game_invalid_address_returns_false`: ENet-eigene Engine-Logs bei
  ungültiger Adresse — gleiche Kategorie (erwarteter Negativ-Pfad, von GUT
  als Fehler gewertet).
- `test_inventory_request_add_item_tier1_without_data`: erwarteter
  "Item-ID unbekannt"-Log, gleiche Kategorie.
- Mögliche generelle Lösung für alle drei: prüfen ob GUT eine
  `expect_error`/`ignore_pending_errors`-API hat und projektweit einführen,
  statt einzelne Log-Level zu ändern.

#### BUG-25: `TerminalController` — Touch-Drag durch `emulate_mouse_from_touch` doppelt angewendet ✅

Nutzer-Report: Der Terminal-Toggle/Close-Button ließ sich seit dem
BUG-22-Fix (Touch-Support für `handle_button_input()`) nicht mehr draggen.
Ursache: `project.godot` hat `pointing/emulate_touch_from_mouse` UND
`pointing/emulate_mouse_from_touch` aktiv — pro physischer Berührung kommen
also ZWEI Events an (z. B. echtes `InputEventScreenDrag` +
dazu emuliertes `InputEventMouseMotion`). Vor BUG-22 wurden Touch-Events
komplett ignoriert (nur Maus verarbeitet → ein Event pro Geste, funktionierte
zufällig). Seit BUG-22 beide Familien verarbeitet werden, wird die
Drag-Bewegung doppelt angewendet → Button "hakelig"/nicht sauber draggbar.

Fix: `TerminalController` sperrt jetzt auf die Event-Familie (Touch ODER
Maus), die die Geste gestartet hat, und ignoriert das jeweils andere
(emulierte) Event bis zum Release. Zwei neue Regressionstests in
`test_terminal_controller.gd`.

## ROUND 26 — BUG-23 tatsächlicher Root-Cause-Fix (Nutzer-Report + Live-Log)

Nutzer-Report: "Neues Spiel" tut nach Klick nichts, Spiel bleibt im
Hauptmenü hängen. Mitgeliefertes Terminal-Log (kompletter Export, nicht nur
Clipboard) zeigt ab dem allerersten Frame:

```
[DEBUG] [Terminal] SimpleTerminal bereit. Befehle: 16
[WARN]  [MainMenuController] SaveSystem noch nicht injiziert — warte auf Push.
[INFO]  [MainMenuController] MainMenuController bereit.
[INFO]  [MainMenuController] Neuer Charakter: 'charakter_...'.
[INFO]  [Events/System] Session angefordert für Charakter 'charakter_...'.
```
— und danach nichts mehr. Insbesondere fehlt komplett die in Round 25 als
Diagnose ergänzte allererste Zeile von `ServiceOrchestrator._ready()`
("_ready() gestartet."). `emit_session_requested()` feuert (Log-Zeile
existiert), aber `ServiceOrchestrator._on_session_requested()` reagiert nie
— kein `╔══ CHARACTER BOOT START ══╗` folgt.

**Root Cause:** `ServiceOrchestrator._ready()` verdrahtete
`EventBus.system.session_requested.connect(_on_session_requested)` sowie
`_watch_for_menu_initializer()` erst NACH `boot_app()`. Jeder Request, der
ankommt bevor dieser Connect passiert ist (Timing-Race zwischen Autoload-
Boot und Main-Szene — die exakte Ursache dafür ließ sich ohne laufendes
Godot nicht weiter eingrenzen, siehe Round 25), geht spurlos verloren:
kein Fehler, keine Log-Zeile, einfach nie eine Reaktion. Das erklärt sowohl
die fehlende SaveSystem-Injektion als auch das tote "Neues Spiel".

**Fix (root-cause-unabhängig, siehe Round-25-Notiz zur selben Strategie):**
- `ServiceOrchestrator._ready()`: `session_requested`-Connect und
  `_watch_for_menu_initializer()` jetzt VOR `boot_app()`.
- Neues `_boot_complete`-Flag + `_pending_session_request`-Puffer:
  `_on_session_requested()` puffert den Request statt ihn zu verlieren,
  falls er vor Boot-Abschluss ankommt; `_ready()` holt ihn nach
  erfolgreichem `boot_app()` automatisch nach.
- Boot-Fehler waren zusätzlich strukturell unsichtbar: der einzige
  `boot_failed`-Listener saß in `Main.gd`/`Main.tscn`, das nie geladen wird
  (`run/main_scene` ist `MainMenu.tscn` direkt, `Main.tscn` ist totes Code).
  `ServiceOrchestrator` loggt Boot-Fehler jetzt zusätzlich selbst laut per
  `AppLogger.log_error()`, und `MainMenuController` hört jetzt ebenfalls auf
  `boot_failed` und zeigt eine sichtbare Status-Meldung statt stillem Hängen.

**Nicht behoben, weil nicht statisch verifizierbar:** die genaue Ursache
der Race selbst (warum `boot_app()`/der Connect überhaupt so spät dran sein
kann) bleibt offen — der Puffer-Fix macht das Verhalten aber unabhängig
davon korrekt. Falls das Problem weiter auftritt, bitte den nächsten
Log-Export schicken: eine `"Session-Request '...' vor Boot-Abschluss —
wird gepuffert."`-WARN-Zeile würde die Race jetzt live bestätigen, statt
dass der Klick einfach nichts tut.

## ROUND 27 — BUG-23 tatsächliche Root Cause gefunden (dank vollständigem GUT-Compile-Log)

Der Nutzer lieferte den `exportlog`-Export (nicht nur Clipboard) UND einen
frischen GUT-Lauf. Der GUT-Lauf enthält, was in keinem bisherigen Log zu
sehen war — den nativen Godot-Compile-Fehler ganz am Anfang:

```
SCRIPT ERROR: Parse Error: Expression is of type "Control" so it can't be
  of type "MainMenuController".
    at: GDScript::reload (res://scripts/core/ServiceOrchestrator.gd:147)
SCRIPT ERROR: Parse Error: Invalid cast. Cannot convert from "Control" to
  "MainMenuController".
    at: GDScript::reload (res://scripts/core/ServiceOrchestrator.gd:151)
ERROR: Failed to load script "res://scripts/core/ServiceOrchestrator.gd"
  with error "Parse error".
ERROR: Failed to create an autoload, script
  'res://scripts/core/ServiceOrchestrator.gd' is not compiling.
```

**Root Cause:** `MainMenuController.gd` deklarierte `extends Node`, ist in
`MainMenu.tscn` aber auf einem `[node name="MainMenu" type="Control"]`
angeheftet. `ServiceOrchestrator._on_menu_initializer_ready(menu_root:
Control)` prüft `menu_root is MainMenuController` und castet
`menu_root as MainMenuController` — der GDScript-Static-Type-Checker sieht
`Control` und `MainMenuController` (deklariert als direktes `Node`-Kind,
nicht `Control`-Kind) als zwei unverwandte Zweige derselben Hierarchie und
lehnt den Cast als statisch unmöglich ab. Das ist kein Warning, sondern ein
harter Compile-Fehler — `ServiceOrchestrator.gd` kompiliert dadurch
komplett nicht, der Autoload wird nie erstellt, `_ready()` läuft NIE (auch
nicht die Round-26-Diagnosezeile, auch nicht der neue Puffer-Pfad — beides
erklärt, warum Round 26 keine Wirkung zeigte: der Fix saß in totem Code).

Das erklärt rückwirkend JEDEN bisherigen Befund zu BUG-23 (Round 24, 25, 26)
lückenlos: keine SaveSystem-Injektion, keine Reaktion auf
`session_requested`, keine Boot-Logs — weil der komplette Autoload nie
existierte, nicht wegen eines Timing-Races.

**Fix:** `MainMenuController.gd`: `extends Node` → `extends Control`
(passend zum tatsächlichen Node-Typ in `MainMenu.tscn`). Damit ist
`MainMenuController` ein echter `Control`-Nachkomme, der Cast in
`ServiceOrchestrator._on_menu_initializer_ready()` ist statisch gültig,
`ServiceOrchestrator.gd` kompiliert wieder, der Autoload läuft.

**Sweep:** alle anderen `WorldScopeInitializer`/`MenuScopeInitializer`-
artigen Cross-Script-Casts geprüft (`WorldScopeInitializer.world_ready`
→ `Node3D`, `World.gd` → `extends Node3D`) — dort stimmen Skript-Basisklasse
und Scene-Root-Typ überein, kein weiterer Fall dieses Musters gefunden.

Die Round-26-Änderungen (Listener vor `boot_app()`, Session-Request-Puffer,
sichtbare `boot_failed`-Anzeige) bleiben als zusätzliche Robustheit
erhalten, waren aber nicht die eigentliche Lösung.

## ROUND 39 — Toter Compat-Shim + veraltete Legacy-Tests/Docs (WorldData-API)

Kein neuer Bug-Report — Anlass war eine strukturelle Durchsuchung des Repos nach
veralteten Kommentaren und unnötig bewahrtem Legacy-Verhalten.

**Fund 1 — `ChunkManager._update_chunks()`:** als "Compat-Shim" kommentiert
("verhindert Brüche in Tests"), aber 0 Aufrufer im gesamten Repo, auch nicht in
Tests. Reiner Leichenfund. Entfernt, dazugehöriger veralteter Kommentar in
`_sync_chunks()`-Kontext korrigiert.

**Fund 2 — vier Testdateien liefen noch gegen die WorldData/WorldService-API von
vor dem Round-38-Cleanup** (`WorldData.gd` selbst dokumentiert im Header, dass
`tree_positions`/`ore_positions` entfernt wurden — die Tests wurden dabei nicht
mitgezogen):
- `test_world_spawner.gd` — 2 Tests riefen `_data.tree_positions`/`.ore_positions`
  auf (nicht mehr existente Felder) um den alten oak_tree/iron_ore-Fallback zu
  testen, den es in `WorldSpawner.spawn_all()` gar nicht mehr gibt. Entfernt,
  nicht ersetzt — das Verhalten existiert nicht mehr, ein Test dafür wäre selbst
  wieder Legacy-Bewahrung.
- `test_harvestable_entity.gd` — 4 Stellen riefen `is_tree_harvested()`/
  `is_ore_harvested()`/`.tree_positions`/`.ore_positions` auf. Die beiden
  "legacy"-benannten Tests entfernt (Methoden existieren nicht mehr, bereits
  durch `test_p0_mark_key_matches_is_harvested_by_type` abgedeckt), die beiden
  `add_typed_*`-Tests auf die tatsächliche typed-only API reduziert.
- `test_world_save_handler.gd` — durchgehend `add_tree()`/`add_ore()`/
  `mark_tree_harvested()` (nicht mehr existent) auf `add_typed_tree()`/
  `add_typed_ore()`/`mark_harvested(type_id, pos)` umgestellt, Save-Key-Checks
  von `tree_positions`/`ore_positions` auf `typed_tree_positions`/
  `typed_ore_positions` korrigiert.
- `test_world_service.gd` — `mark_tree_harvested()`/`mark_ore_harvested()`
  (nicht mehr existent) durch das generische `mark_harvested(type_id, pos)`
  ersetzt, Assertions entsprechend auf `is_harvested_by_type()` umgestellt.

Alle vier Dateien hätten mit der aktuellen `WorldData`/`WorldService`-API gar
nicht kompiliert/laufen können (Zugriff auf nicht deklarierte Member in
statisch typisiertem GDScript ist ein Parse-Fehler, kein Laufzeit-Fehler).

**Fund 3 — `docs/services.md` und `docs/architecture.md`:** Save-Schema-Tabelle
für `WorldService` nannte noch `tree_positions`/`world_seed` (Feld wird laut
Code-Sweep aktuell gar nicht persistiert — nicht in dieser Runde behoben,
siehe unten) statt der tatsächlich gespeicherten Keys. Auf den echten
`WorldSaveHandler.get_save_data()`-Output korrigiert: `typed_tree_positions`,
`typed_ore_positions`, `harvested`, `saved_pets`.

**Nicht behoben, bewusst zurückgestellt:** `world_seed` wird laut Sweep an
keiner Stelle gespeichert oder wiederhergestellt — jede Welt bekäme nach
einem Reload einen neuen Seed. Das ist ein Verhaltens-Bug, kein
Kommentar-/Legacy-Fund, und außerhalb des Scopes dieser Runde. Sollte als
eigener Bug-Report behandelt werden.

## ROUND 40 — BUG-25: world_seed wurde nie persistiert

Direkte Folge des in Round 39 in `docs/services.md`/`docs/architecture.md`
gefundenen, aber bewusst zurückgestellten Docs-Mismatch: `world_seed` stand in
der (jetzt korrigierten) Schema-Doku, wurde von `WorldSaveHandler` aber nie
geschrieben oder gelesen. Jede geladene Welt bekam dadurch einen neuen
Zufallsseed statt des ursprünglichen — Terrain-Form an bereits gespeicherten
Baum-/Erz-Positionen konnte nach einem Reload nicht mehr zur Höhe passen,
und neu betretene Chunks unterschieden sich von Session zu Session.

**Fix:**
- `WorldSaveHandler.get_save_data()` / `restore_world()`: `world_seed`
  wird jetzt mitserialisiert bzw. wiederhergestellt (Default `0` für alte
  Saves ohne das Feld — identisch zum bestehenden "0 = noch nicht gesetzt"-
  Verhalten, daher kein Migrationsschritt nötig).
- `WorldService.configure()`: Reihenfolge-Bug behoben. `restore_world()`
  lief bisher NACH der Seed-Ableitung für `factory.world_seed` — zu dem
  Zeitpunkt war `data.world_seed` immer noch die frische `0` der gerade neu
  erzeugten `WorldData`, ein gespeicherter Seed kam bei `WorldFactory` also
  nie an, selbst mit persistiertem Wert. `restore_world()` läuft jetzt zuerst,
  die Seed-Ableitung danach.
- `docs/services.md` / `docs/architecture.md`: `world_seed` wieder in die
  Save-Schema-Tabelle aufgenommen.
- Regressionstest `test_restore_world_seed()` in `test_world_save_handler.gd`.

## ROUND 41 — ADR-023: Entity-Reference-Kontrakt implementiert

Erste Umsetzungsrunde aus der R-1..R-7-Root-Cause-Recherche (siehe
`TODO-offene-probleme.md`). ADR-023 liegt unter ADR-020/021 und wird deshalb
zuerst umgesetzt — beide ADRs referenzieren `resolve_for_player()`, das ohne
diese Runde nicht existiert hätte.

#### ADR-023: `EntityOrchestrator.resolve_for_player(uuid, player_id, max_range)` ✅
- Neue Methode: löst `uuid` über das bestehende `get_entity()` auf, prüft
  danach Distanz zwischen einem Player-Node mit passendem `owner_peer_id` und
  der Entity. `null` bei unbekannter UUID, fehlendem Player, oder
  Reichweiten-Überschreitung — jeweils mit kontextreichem `log_warn`.
- `_find_player_by_id(player_id)`: privater Helfer, identisches Muster zu
  `IEntityContext.get_local_player()` / `PetComponent._find_owner()` (Gruppe
  `"player"` + `owner_peer_id`-Meta-Abgleich), hier für einen beliebigen
  `player_id` statt für den lokalen Peer.
- Bewusst kein globaler `max_range`-Default — der Aufrufer (künftig ADR-020)
  übergibt ihn explizit pro Interaktionsart.
- `NetworkContract.gd`: `resolve_for_player()` im server-autoritativen
  Abschnitt dokumentiert, inkl. Hinweis dass dies ein Plausibilitätsfilter
  ist, kein Movement-Anti-Cheat (Position bleibt client-reported bis
  ADR-024/025 umgesetzt sind).
- `docs/adr/023-entity-reference-contract.md`: Status → "Angenommen —
  umgesetzt", neuer Abschnitt "Umsetzung" dokumentiert was gebaut wurde und
  was bewusst nicht (die eigentliche Umstellung von `InteractionExecutor`
  usw. gehört zu ADR-020, nicht zu diesem ADR).
- `TODO-offene-probleme.md`: ADR-023-Eintrag um Umsetzungsstatus ergänzt.

**Tests:** `tests/unit/test_entity_orchestrator.gd` (neu, 5 Tests) —
unbekannte UUID, fehlender Player, außerhalb Reichweite, Erfolgspfad,
Auflösung über `owner_peer_id`-Meta statt Node-/Iterationsreihenfolge (Regression
gegen einen naheliegenden, aber falschen "erster Player in der Gruppe"-Bug).
Neuer Test-Double `tests/mocks/MockHarvestable.gd` (leerer `Node3D`-Nachkomme,
für `EntityRegistry.register()`/`instantiate()` in isolierten Tests ohne
Abhängigkeit von einer echten Spiel-Entity).

**Bewusst nicht Teil dieser Runde:** ADR-020 (Interaction Authority Guard,
R-1/R-2/R-3/R-4/R-6), ADR-021 (Quest Objective Networking, R-5), ADR-022
(Economy Backsync + UI Identity, R-7) — jeweils eigene Runden, da sie
`resolve_for_player()` erst jetzt zur Verfügung haben und die "Anpassungshinweise"
aus ADR-023 selbst noch textlich in die ADR-020/021-Entwürfe eingearbeitet
werden müssen, bevor an deren Code gegangen wird.

**Nächster Schritt:** ADR-020 textlich an ADR-023 angleichen (`request_interact(uuid,
action_id, player_id)` statt `action_id, player_id`), dann `InteractionExecutor`/
`InteractableComponent`/`HarvestableEntity`/`AnimalCatcher`/`EnemyAttack` auf
Authority-Guards + `resolve_for_player()` umstellen (R-1, R-2, R-3, R-6).

## Round 42 — ADR-020 Transport-Mechanismus (R-2 Transport-Hälfte, R-3, R-6)

**Scope-Entscheidung:** ADR-020 Option B hat zwei trennbare Hälften — (a) den
Transport, der eine Interaktion überhaupt zur Autorität bringt, und (b) die
Verschiebung der Loot-/XP-*Berechnung* selbst in einen serverseitigen
`InteractionResolver`. (b) ist der größere, eigenständige Umbau
(`InteractionExecutor` verliert seine heutige Rolle, siehe ADR-020
„Konsequenzen/Negativ"). Diese Runde liefert (a) vollständig und wendet ihn
einheitlich auf alle drei bestehenden Interaktions-Consumer an — nicht als
Einzel-Patch pro Entity-Typ, sondern zentral in `InteractableComponent`.

**Cheat-Vektor im eigenen Entwurf gefunden und geschlossen, bevor Code
geschrieben wurde:** Der ursprüngliche Entwurf sah vor, `max_range` als
RPC-Parameter mitzuschicken (aus der lokalen `detection_radius`). Ein
modifizierter Client hätte dort einfach einen beliebig großen Wert einsetzen
können und die Plausibilitätsprüfung aus ADR-023 wertlos gemacht. Fix: die
Autorität liest `max_range` aus ihrer **eigenen** Kopie der Entity
(`InteractableComponent.detection_radius`, servereigener State), nie aus dem
RPC. `player_id` kam schon vorher korrekt aus `multiplayer.get_remote_sender_id()`,
nicht aus einem Client-Parameter — dieses Muster wurde nur auf den neuen RPC
übertragen, nicht neu erfunden.

**Was gebaut wurde:**
- `WorldService.request_entity_interaction(uuid, action_id, player_id)` —
  Client-seitiger Einstieg. Tier 1 / bereits-Autorität: löst direkt auf.
  Tier 2/3 als Nicht-Autorität: delegiert an `NetworkBridge.send_entity_interaction()`.
- `WorldService.resolve_and_dispatch_interaction(uuid, action_id, player_id)` —
  Autoritäts-seitig. Nutzt `EntityOrchestrator.resolve_for_player()` (ADR-023);
  `max_range` kommt aus `_max_interaction_range_for()` (liest die
  `InteractableComponent`-Meta der Entity, s.o.), mit einer festen,
  servereigenen Fallback-Konstante nur für den (eigentlich nie erreichbaren)
  Fall einer Entity ohne Component.
- `NetworkBridge.send_entity_interaction()` / `_rpc_request_entity_interaction()` —
  überträgt ausschließlich `entity_uuid` + `action_id`, keine Position/Reichweite.
- `InteractableComponent._handle_completion()` — zentraler Fix-Punkt: lokaler
  Emit bleibt (Autorität wirkt direkt darüber; Nicht-Autorität bekommt darüber
  höchstens ein durch den jeweiligen Hook selbst wirkungsloses Feedback), plus
  Weiterleitung an `WorldService.request_entity_interaction()` wenn
  `not parent.is_multiplayer_authority()`.
- Authority-Guards ergänzt in `AnimalBase._on_interacted()` und
  `HarvestableEntity._on_interacted()` (bisher nur `EnemyNPC` hatte das).
- Zyklus-Vermeidung: `NetworkBridge` bekommt `world` als regulären configure()-Dep
  (einseitig); `WorldService` bekommt `NetworkBridge` umgekehrt NICHT als Dep,
  sondern über denselben Phase-C8-Late-Inject-Mechanismus wie
  Inventory/Quest/SkillSystem/Equipment (`BootPipeline.gd`,
  `WorldService.inject_network_bridge()`).
- `NetworkContract.gd` und `docs/adr/020-interaction-authority-guard.md` (neuer
  Abschnitt „Umsetzungsstand") dokumentieren exakt, was geschlossen ist und was
  bewusst offen bleibt. `TODO-offene-probleme.md`: R-3 und R-6 auf erledigt
  gesetzt, R-2 als "Transport-Hälfte geschlossen, Berechnungs-Hälfte offen"
  markiert.

**Unerwarteter Fund während der Umsetzung (dokumentiert, nicht separat
gefixt):** `EnemyNPC._on_interacted()`s Guard-Kommentar ("Server übernimmt:
läuft dort erneut als Autorität") war auf einem Nicht-Host-Client vor diesem
Fix **niemals erreichbarer Code** — der zugrundeliegende `interacted`-Emit kam
strukturell nie über den ausführenden Prozess hinaus (`InteractionExecutor`
läuft pro Peer lokal, siehe R-6-Analyse). D.h. Nahkampfschaden von einem
Nicht-Host-Spieler erreichte den Server in der Vergangenheit nie — ein
funktionaler Multiplayer-Bug, den erst die Suche nach R-6 aufgedeckt hat, weil
es nie einen echten Zwei-Peer-Integrationstest dafür gab. Mit dieser Runde
erreicht der Hook die Autorität; die XP-Menge selbst bleibt bis zum
`InteractionResolver` (R-1/R-2-Berechnungs-Hälfte) client-bemessen.

**Tests (neu):**
- `tests/unit/test_interaction_authority_dispatch.gd` — `resolve_and_dispatch_
  interaction()` (Erfolg, unbekannte UUID, außerhalb Reichweite, fehlender
  Player, Reichweite kommt aus der Entity nicht aus einem großzügigen Fallback,
  Fallback-Konstante bei fehlender Component), `request_entity_interaction()`
  Tier-1- und Tier-2-Routing, `_rpc_request_entity_interaction()` mit
  Sender-basierter `player_id`.
- `tests/unit/test_interactable_component_authority_routing.gd` —
  `_handle_completion()`: Autorität nur lokal, Nicht-Autorität leitet weiter,
  fehlende UUID/WorldService crasht nicht.
- `tests/unit/test_harvestable_entity.gd` / `test_animal_catcher.gd`: je zwei
  neue Guard-Tests (Autorität wirkt weiterhin, Nicht-Autorität wirkt nicht).
- Neuer Mock `tests/mocks/MockInteractableEntity.gd`.

**Bewusst nicht Teil dieser Runde (siehe ADR-020 „Umsetzungsstand" für Details):**
- R-1 (Loot-Roll/XP-Bemessung bleibt client-seitig in `InteractionExecutor`)
- R-2, Berechnungs-Hälfte (Combat-XP-Menge bleibt client-bemessen)
- R-4 (`_rpc_equip_item` prüft weiterhin nicht `InventorySystem.has_item()`) —
  unabhängiger Fund, kein Bestandteil des Interaktions-Transports
- Movement-Anti-Cheat (`player.global_position` bleibt client-reported, siehe
  ADR-023/024/025) und Rate-Limiting auf `any_peer`-RPCs — beide bereits vorher
  bekannt und separat getrackt, hier nicht mitgelöst.

**Nächster Schritt:** `InteractionResolver` als eigenständiger Service (ADR-020
Option B, Rest) — verschiebt Loot-Roll + XP-Bemessung aus `InteractionExecutor`
auf die Autorität, schließt R-1 und die Berechnungs-Hälfte von R-2. Danach R-4
(Equip-Besitzprüfung) als kleinerer, unabhängiger Fix.

## Round 43 — InteractionResolver (R-1, R-2 Berechnungs-Hälfte) — ABGESCHLOSSEN

Schließt R-1 und die Berechnungs-Hälfte von R-2 formal ab (siehe
`TODO-offene-probleme.md` und ADR-020 „Umsetzungsstand — Round 43").

**Gebaut und verdrahtet (siehe ADR-020 „Umsetzungsstand — Round 43" für Details):**
- `scripts/interaction/InteractionResolver.gd` (neu) — statische Utility,
  rollt Loot + emittiert XP über `IEventBus`, kein eigener Autoritäts-Guard
  (bleibt Aufgabe des Aufrufers).
- `InteractionExecutor._on_tween_finished()` — Loot/XP-Berechnung entfernt,
  `_stat_modifiers`-Dep komplett entfernt (war nie in `BootstrapConfig.tres`
  verdrahtet — Nebenbefund, siehe ADR-020).
- `HarvestableEntity._on_interacted()` — ruft `InteractionResolver.resolve()`
  vor dem Despawn, weiterhin hinter dem bestehenden Autoritäts-Guard.
- `EnemyNPC._on_interacted()` — ruft `InteractionResolver.resolve()` für
  `AttackInteractable` nach der Schadensanwendung.
- `test_interaction_executor.gd` — die beiden alten (einer davon bereits vorher
  kaputten) Reward-Tests durch zwei Regressions-Tests ersetzt.

**Mit diesem Abschluss ergänzt:**
- Neu: `tests/unit/test_interaction_resolver.gd` — dedizierte Unit-Tests mit
  echten `LootTable`/`LootEntry`/`StatModifierService`-Instanzen (kein Mock für
  die Berechnung selbst). Deckt Drop-Emission, XP-Emission (inkl.
  `xp_type == "none"`/`xp_amount <= 0` als Nicht-Emit-Fälle), `player_id`-
  Attribution statt Default, Yield-Skalierung inkl. Skalierung PRO `player_id`
  (der konkrete Bug-Fix aus dieser Runde), sowie defensive Guards ohne Crash.
- `test_harvestable_entity.gd` — drei neue Guard-Tests: Autorität löst über
  `InteractionResolver` tatsächlich XP/Loot aus, Nicht-Autorität löst nichts
  aus, `_ctx.get_stat_modifiers()` kommt nachweislich bei der Loot-Skalierung an.
- `TODO-offene-probleme.md`: R-1/R-2 formal auf "geschlossen" gesetzt.
- `docs/adr/020-interaction-authority-guard.md`: Status-Header und
  „Umsetzungsstand (Round 43)" von "IN ARBEIT" auf "geschlossen" aktualisiert.

**Bewusst nicht Teil dieser Runde:**
- `EnemyNPC._on_interacted()`s neuer `InteractionResolver`-Aufruf bleibt mangels
  Headless-Instanziierbarkeit (siehe `test_enemy_npc_pool_reuse.gd`-Kommentar)
  nur indirekt über die `InteractionResolver`-Unit-Tests verifiziert, nicht über
  eine eigene `EnemyNPC`-Instanz — bestehende Testbarkeits-Lücke, keine neue.
- R-4 (`_rpc_equip_item` prüft weiterhin nicht `InventorySystem.has_item()`) —
  unabhängiger Fund, kein Bestandteil dieser Runde.
- Movement-Anti-Cheat und Rate-Limiting auf `any_peer`-RPCs — unverändert
  separat getrackt.

**Nächster Schritt:** R-4 (`_rpc_equip_item` → `InventorySystem.has_item()`-Prüfung
vor dem Ausrüsten) als kleinerer, unabhängiger Fix — letzter offener Punkt aus
der ursprünglichen ADR-020-Familie (R-1..R-4, R-6).

## Round 44 — R-4-Recherche: Mutations-Onion-Befund, kein Code-Fix

**Kein Code geändert.** Nur Befund + Dokumentation (`TODO-offene-probleme.md`,
`docs/adr/020-interaction-authority-guard.md`), auf ausdrücklichen Wunsch vor
jeder Implementierung — Methode wie AUDIT-05: Code zuerst, jeder Befund mit
Datei+Zeile belegt, kein Fix im selben Schritt.

Beim Versuch, R-4 (`_rpc_equip_item` prüft nie `InventorySystem.has_item()`)
umzusetzen, zeigte sich vor dem ersten Zeilen-Edit: die naheliegende Prüfung in
`EquipmentService.on_equip_confirmed()` würde am tatsächlichen Spielverhalten
nichts ändern, weil dieser Codepfad im Spiel gar nicht benutzt wird.

**Befund 1 — zwei parallele Equip-Mutations-Pfade (AUDIT-05 "Mutations-Zwiebel"):**
- Pfad A (vermeintlich sicher): `request_equip()` → `on_equip_confirmed()` →
  `equip()`. Einziger Aufrufer: `NetworkBridge._rpc_equip_item()`.
- Pfad B (tatsächlich genutzt): `InventoryUIController._on_equip_weapon()` und
  `EquipmentUIController` rufen `_equipment.equip()` direkt auf — an Pfad A
  komplett vorbei. Kein Gameplay-Call-Site nutzt Pfad A.
- Ursache für Pfad B: `request_equip()` nimmt keinen `visuals`-Parameter entgegen
  und kann `on_equip_confirmed()`s optionalen `visuals`-Parameter folglich nie
  befüllen — die UI-Panels brauchten das Visual und sind deshalb am sicheren
  Pfad vorbeigegangen.

**Befund 2 — Voraussetzung für eine saubere Lösung fehlt:** "Player-Node zu
`owner_peer_id` finden" ist fünffach unabhängig dupliziert
(`EntityOrchestrator._find_player_by_id()` [privat, einzige Version mit
beliebigem `player_id`], `IUIContext.get_local_player()`,
`IEntityContext.get_local_player()`, `PetComponent._find_owner()`,
`WorldService._on_peer_cleanup_requested()` [nur je der lokale/eigene Peer]) —
keine davon ist eine öffentliche, für beliebige `player_id` aufrufbare Utility.
Deshalb konnte `EquipmentService` `on_equip_confirmed()` bisher nicht sauber mit
Visual-Auflösung bauen, ohne entweder Pfad B stehen zu lassen oder einen
sechsten Duplikat-Scan einzubauen.

**Dokumentiert, nicht gefixt** — siehe TODO-Dokument, R-4-Eintrag, für die
vorgeschlagene Reihenfolge (zentrale Player-Lookup-Utility → Visual-Auflösung
auf der Autorität → UI auf `request_equip()` umstellen → erst dann
`has_item()`-Prüfung ergänzen).



## Round 46 — BUG-26: Doppel-Count bei npc_talked_to + test_quest_service.gd Compile-Fix

Anlass: Klarstellung durch den Owner, dass NICHT das ganze Quest-System an
ADR-025/026 (Movement-Authority) hängt — nur `custom_objective_triggered`.
`npc_talked_to`/`interaction_finished` sind Entities/Services mit eigenem
Autoritäts-Hook und sollten unabhängig davon fertig gemacht werden können.
Bei der Verifikation zeigte sich: der Code aus Round 45 (ADR-021 Option C)
hatte alle drei Fälle bereits vollständig über `report_domain_event()`
verdrahtet — aber mit einem bis dahin unentdeckten Bug bei `npc_talked_to`.

#### BUG-26: `QuestNPC._on_interacted()` — fehlender Autoritäts-Guard, Doppel-Count ✅

**Root Cause:** Anders als `HarvestableEntity._on_interacted()` und
`EnemyNPC._on_interacted()` (beide seit ADR-020 mit `if not
is_multiplayer_authority(): return`-Guard) hatte `QuestNPC._on_interacted()`
keinen solchen Guard. `InteractableComponent._handle_completion()` (ADR-020)
ruft diesen Hook für einen Nicht-Host-Spieler zweimal auf: einmal lokal auf
dem Client (als reines UI-Feedback gedacht), einmal erneut auf der Autorität
über `WorldService.resolve_and_dispatch_interaction()`. Beide Läufe meldeten
unabhängig voneinander `report_domain_event("npc_talked_to", …)` — TALK-
Quest-Objectives zählten pro Gespräch doppelt hoch für jeden Nicht-Host-Spieler.

**Betrifft nur `npc_talked_to`:** `interaction_finished` läuft ausschließlich
über `InteractionExecutor._on_tween_finished()` (kein entity-gebundener
Zweit-Aufruf möglich), `custom_objective_triggered` hat keinen entity-
gebundenen Autoritäts-Hook (reiner `Area3D`-Trigger) — beide sind vom
Doppel-Count-Muster nicht betroffen.

**Fix:** Guard `if not is_multiplayer_authority(): return` in
`QuestNPC._on_interacted()` ergänzt, nach dem lokalen Dialog-Feedback (das
bleibt für jeden Peer bestehen) und vor Bus-Emit + `report_domain_event()`.

**Tests:** `tests/unit/test_quest_npc.gd` — 2 neue Regressionstests:
Nicht-Autorität meldet kein Domain-Event (Dialog-Feedback bleibt aber
erhalten); voller Round-Trip (Nicht-Autorität-Aufruf gefolgt vom Autoritäts-
Aufruf) meldet zusammen genau ein Event statt zwei.

**Docs:** `docs/adr/021-quest-objective-networking.md` — neuer Abschnitt
„Umsetzungsstand (Round 46) — BUG-26" dokumentiert Befund + Fix.
`TODO-offene-probleme.md` — R-5 als geschlossen markiert (war seit Round 45
im Code umgesetzt, aber im TODO-Dokument nie nachgezogen worden).

#### Compile-Fix: `test_quest_service.gd` ✅

`update_objective(quest_id, objective_id, delta, player_id)` verlor in
Round 45 bewusst seinen `player_id`-Default (Root Cause des ursprünglichen
R-5-Bugs, siehe ADR-021 Umsetzungsplan Punkt 7) — zehn Testaufrufe in
`test_quest_service.gd` riefen die Methode weiterhin mit nur drei Argumenten
auf, was mangels Default zum Compile-Fehler führt. Alle zehn Aufrufe um den
expliziten Tier-1-Wert `player_id=1` ergänzt — kein Verhaltensunterschied
zum vorherigen Default.

**Bewusst nicht Teil dieser Runde:** `custom_objective_triggered` bleibt wie
vom Owner bestätigt als dokumentierte Abhängigkeit von ADR-025/026 im TODO
stehen (Area3D-Proximity ohne server-autoritative Positionswahrheit) — kein
Grund, den Movement-Umbau deswegen jetzt zu starten, zumal `QuestCustomTrigger`
noch in keiner Szene platziert ist.

## Round 48 — Schritt 3: Rate-Limiting auf `any_peer`-RPCs ✅

Nächster Punkt aus `TODO-offene-probleme.md`s "Nächster Schritt"-Liste — bisher
konnte jeder verbleibende `@rpc("any_peer")`-Endpunkt beliebig oft pro
Zeiteinheit aufgerufen werden (kein Schutz gegen Flood/Spam, unabhängig von
R-1..R-7).

**Gebaut:** Fixed-Window-Rate-Limiter direkt in `NetworkBridge` (kein neuer
Service — der State ist reiner RPC-Empfangs-Bookkeeping, gehört zur selben
Klasse wie die RPCs selbst):
- `RATE_LIMIT_WINDOW_SEC` (1.0s) + `RATE_LIMITS: Dictionary` — Methodenname →
  Aufrufe pro Fenster. Kein Eintrag = kein Limit.
- `_rate_limit_state: Dictionary` — Key `"<peer_id>:<rpc_name>"`, Value
  `{window_start, count}`. Zeitquelle `Time.get_ticks_msec()` — kein
  Abhängigkeit von `SceneTreeTimer`/`_process()`.
- `_is_rate_limited(rpc_name, peer_id) -> bool` — geprüft als allererstes nach
  dem bestehenden `_is_authority()`-Guard in jedem gelisteten RPC-Handler:
  `_rpc_start_quest` (5/s), `_rpc_complete_quest` (5/s), `_rpc_set_state` (10/s),
  `_rpc_equip_item` (10/s), `_rpc_unequip_item` (10/s),
  `_rpc_request_entity_interaction` (10/s), `_rpc_report_domain_event` (10/s),
  `_rpc_client_requests_initial_state` (2/s).
- `on_cleanup()` leert `_rate_limit_state` — kein Stale-State über Session-Grenzen.

**Bewusst ausgenommen:** `_rpc_submit_movement_input` (ADR-025) — läuft
absichtlich mit 20+ Hz über `unreliable_ordered`; ein Sekunden-Fenster-Limiter
würde dort legitimen Bewegungs-Input verwerfen statt Spam abzuwehren. Ein
DoS-Schutz für diesen Kanal (falls je nötig) bräuchte eine andere Strategie
(z.B. Paketgrößen-/Frequenz-Cap auf ENet-Ebene) und ist kein Bestandteil
dieser Runde.

**Nicht behoben, bewusst zurückgestellt:** kein Auto-Kick/-Ban bei wiederholter
Überschreitung — der Limiter verwirft aktuell nur den einzelnen Aufruf und
loggt eine WARN-Zeile. Eskalation (z.B. Peer nach N Überschreitungen trennen)
wäre ein separater, größerer Design-Punkt (Fehlalarme durch Paket-Bursts bei
schlechter Verbindung vs. echter Spam) und ist hier nicht mitgelöst.

**Tests:** `tests/unit/test_network_bridge.gd` — 6 neue Tests: Aufrufe
innerhalb des Limits gehen durch, der Aufruf über dem Limit wird blockiert,
Limit ist pro Peer isoliert (ein anderer Peer bleibt unberührt), Limit ist pro
RPC-Name isoliert (ein anderer Endpunkt für denselben Peer hat sein eigenes
Fenster), `_rpc_submit_movement_input` wird nie limitiert (50 Aufrufe im
selben Fenster), `on_cleanup()` setzt den State zurück.

**Docs:** `TODO-offene-probleme.md` — Punkt als geschlossen markiert.

**Nächster Schritt:** von den verbleibenden Kandidaten aus der "Nächster
Schritt"-Liste (siehe TODO-Dokument) sind noch offen: R-7 (Server→Client-
Rücksync für Economy-Mutationen, ADR-022, Status "Vorgeschlagen") und der
volle Zwei-Peer-Gameplay-Round-Trip unter realer Latenz (IT-03, aktuell
`pending()`) — Letzteres braucht eine laufende Godot-Instanz mit zwei echten
Peers, nicht statisch lösbar.

## Round 50 — IT-03: echter Zwei-Prozess-Gameplay-Round-Trip ✅ (+ Bugfix aus unterbrochener Vorrunde)

Fortsetzung des einzigen verbliebenen offenen Punkts aus der "Nächster
Schritt"-Liste, der nicht rein statisch (ohne laufende Godot-Instanz) lösbar
war: R-7/R-8 (Round 49, ADR-022) sind bereits geschlossen, siehe TODO-Dokument.

**Ausgangslage dieser Runde:** ein vorheriger Anlauf hatte bereits
`scripts/testing/IT03Harness.gd` (CI-only Autoload, Zwei-Prozess-Treiber) und
den zugehörigen CI-Job "IT-03 — Two-Process Movement Round Trip"
(`build-apk.yml`) entworfen, wurde aber unterbrochen, bevor der Harness
tatsächlich ins Projekt integriert wurde — die Datei existierte nur als
loses Artefakt, war nicht im Repo (`scripts/testing/` fehlte komplett), nicht
als Autoload registriert, und enthielt einen Bug, der den Test strukturell
nie hätte grün laufen lassen können: `_read_seq()` ruft
`player_node.call("get_last_processed_input_seq")` hinter einem
`has_method()`-Guard auf — diese Methode existierte in `Player.gd` nie
(nur das private Feld `_last_processed_input_seq`, per Konvention mit `_`
markiert, aber ohne öffentlichen Getter). `has_method()` wäre also immer
`false` zurückgegeben, `_read_seq()` hätte immer `-1` geliefert, und der Client-
Prozess wäre nach `SEQ_TIMEOUT_SEC` (20s) zuverlässig mit `_fail(...)`
(Exit-Code 1) gestorben — unabhängig davon, ob der eigentliche Movement-Input-
Round-Trip in Wirklichkeit funktioniert.

**Fix:**
- `Player.gd`: neuer öffentlicher Getter `get_last_processed_input_seq() -> int`
  neben dem bestehenden privaten Feld — reiner Lesezugriff, keine
  Verhaltensänderung an der Reconciliation-Logik selbst
  (`_reconcile_if_needed()` liest weiterhin direkt das Feld).
- `scripts/testing/IT03Harness.gd` unverändert aus der Vorrunde übernommen —
  nach Gegenprüfung gegen den tatsächlichen Code (`EventBus.networking`/
  `EventBus.session`-Signalnamen und -Signaturen, `SessionManager.
  get_local_peer_id()`, `WorldService.get_player_by_id()`,
  `ServiceKeys.SESSION_MANAGER`/`WORLD`, den Client-Auto-Boot-Pfad über
  `SessionManager.client_connected_to_server` → `ServiceOrchestrator.
  _on_client_connected()`) war der Rest korrekt konstruiert — der fehlende
  Getter war der einzige Fund.
- `project.godot`: `IT03Harness="*res://scripts/testing/IT03Harness.gd"` als
  fünfter Autoload registriert (nach `ServiceOrchestrator`, wie von
  `build-apk.yml`s Strip-Schritt bereits vorausgesetzt — die `sed`-Zeile dort
  existierte schon, lief vorher nur ins Leere, weil die Zeile, die sie
  entfernen sollte, nie existiert hatte).

**Docs:**
- `tests/integration/test_movement_two_peer.gd` — Kopfkommentar + der
  `pending()`-Test umbenannt/umformuliert: erklärt jetzt, warum IT-03 bewusst
  NICHT als GUT-Test in diesem Prozess läuft (ein Godot-Prozess kann keine
  zwei unabhängigen App-Boots mit eigener Autorität sauber nebeneinander
  betreiben) und verweist auf den echten Zwei-Prozess-Job. `pending()` bleibt
  bestehen statt gelöscht zu werden — dient als Fundstelle für jeden, der nur
  `tests/` durchsucht.
- `docs/adr/025-server-authoritative-movement.md` / `026-client-side-
  prediction-reconciliation.md` — je ein "Update (Round 50)"-Absatz an die
  bestehende Umsetzungsstand-Sektion angehängt (nicht überschrieben — der
  Round-47-Text bleibt als historischer Kontext stehen). Ehrlich weiterhin als
  offen markiert: künstliche Latenz, Paketverlust, Tier-2-Geräte-Grenze. Ein
  Zwei-*Prozess*-Test auf demselben Loopback-Runner ist kein Latenz-Test.
- `TODO-offene-probleme.md` — Punkt "Kein echter Zwei-Peer-Integrationstest"
  als teilweise geschlossen markiert (Gameplay-Round-Trip: ja; Latenz/
  Paketverlust/Tier-2: weiterhin nein), "Nächster Schritt"-Sektion entsprechend
  auf den verbleibenden Rest umformuliert.

**Nicht Teil dieser Runde:** die künstliche Latenz-/Paketverlust-Injektion und
die Tier-2-Geräte-Grenzmessung selbst — beide brauchen entweder ein
Netzwerk-Throttling-Tool zwischen zwei CI-Prozessen oder echte, physisch
getrennte Hardware, keins von beidem ist in dieser Sandbox herstellbar. Auch
nicht angefasst: die Round-49-Lücke, dass diese Datei (`ImplementAgent.md`)
nie einen eigenen "Round 49"-Eintrag bekommen hat, obwohl R-7/R-8 laut
TODO-Dokument in Round 49 geschlossen wurden — außerhalb des Scopes dieser
Runde, aber als Beobachtung hier vermerkt statt stillschweigend ignoriert.

## Round 51 — IT-03: künstliche Latenz/Paketverlust ✅

Fortsetzung von Round 50 — der zuletzt verbleibende Netzwerk-Teil der
"Nächster Schritt"-Liste: der Zwei-Prozess-Test lief real, aber über
127.0.0.1 zwischen zwei Prozessen auf demselben Runner — quasi
verzögerungsfrei, quasi nie Paketverlust. Kein Beleg dafür, dass ADR-025/026
(server-autoritatives Movement, Client-Side Prediction/Reconciliation) unter
den Bedingungen funktionieren, für die sie eigentlich gebaut wurden.

**Gebaut:** `scripts/ci/udp_latency_proxy.py` — bidirektionales UDP-Relay,
reine Python-Standardbibliothek (`asyncio`), kein Extra-Install im
CI-Runner nötig. Sitzt zwischen Host- und Client-Prozess: der Client
verbindet sich gegen den Proxy-Port statt gegen den Host direkt, der Proxy
lernt die Client-Adresse beim ersten Paket und verzögert/verwirft danach
jedes Paket in beide Richtungen unabhängig (getrennte Up-/Down-Profile
möglich, per Default symmetrisch). Lokal gegen einen Echo-Server verifiziert
(nicht nur gelesen, tatsächlich mit `asyncio`-Testskript gegen echten
Delay/Loss gemessen): 50ms Delay ergab ~100ms gemessene RTT (korrekt, 2×
Ein-Weg-Delay), 20%/20% Up-/Down-Loss ergab ~35.6% gemessenen
Round-Trip-Verlust bei 500 Testpaketen (rechnerisch erwartet: 1 − 0.8² = 36%,
Messwert liegt im erwarteten Rauschband).

**CI-Integration (`build-apk.yml`):**
- Neue `env:`-Werte `IT03_HOST_PORT`/`IT03_PROXY_PORT`/`IT03_LATENCY_MS`/
  `IT03_JITTER_MS`/`IT03_LOSS_PCT` — zentral im Workflow-Kopf, nicht in
  einzelnen Steps verstreut.
- Neuer Step "Start network simulation proxy (background)" zwischen "Start
  host process" und "Run client process" — analog zum bestehenden
  PID-Tracking-Muster des Host-Prozesses (`proxy.pid`, `proxy.log`).
- Client verbindet sich jetzt gegen `IT03_PROXY_PORT` statt `IT03_HOST_PORT`.
- "Stop host process" → "Stop host and proxy processes" (beide PIDs).
- Proxy-Log zusätzlich in Job-Summary und als Artefakt (`it03-logs`).
- Job-Name umbenannt: "IT-03 — Two-Process Movement Round Trip (simulated
  latency + loss)" — der alte Name hätte nach diesem Fix stillschweigend
  mehr behauptet, als er testet, wenn man ihn nicht anpasst.

**Werte-Herleitung:** 80ms±20ms Jitter, 2% Verlust pro Richtung (~4% auf dem
vollen Round-Trip) — ein realistisches Durchschnittsprofil für
Breitband/WLAN, bewusst kein Worst-Case (Mobilfunk-Rand, Satellit), damit ein
echter Regressions-Fund den Job zuverlässig rot macht statt bei jedem Lauf
durch Zufalls-Timeouts zu flakern. Bei Bedarf über die neuen `env:`-Werte
ohne Code-Änderung verstellbar (z. B. für einen separaten, bewusst härteren
"Worst-Case"-Lauf).

**Docs:** `docs/adr/025-server-authoritative-movement.md` /
`026-client-side-prediction-reconciliation.md` — je ein "Update (Round 51)"-
Absatz. `TODO-offene-probleme.md` — Punkt umformuliert: Latenz/Paketverlust
geschlossen, nur noch Tier-2-Geräte-Grenzmessung offen (explizit als
Hardware-, nicht Netzwerkfrage benannt, damit der nächste Versuch nicht
wieder an `tc netem` vorbeiläuft, wo eigentlich `cpulimit`/ein echtes Gerät
gebraucht wird).

**Bewusst nicht Teil dieser Runde:** asymmetrische Realwelt-Profile (z. B.
Download schneller als Upload, wie bei den meisten Heimanschlüssen) — die
`--down-*`-Flags existieren im Skript dafür, werden aber im CI-Job (noch)
nicht mit abweichenden Werten befüllt, weil ein symmetrisches Profil für
einen Regressions-Rauchtest ausreicht und das Werte-Herleitungsproblem
(welche Asymmetrie ist realistisch genug, ohne willkürlich zu wirken) nicht
in dieser Runde beantwortet werden musste. Ebenfalls nicht angefasst: die
Round-49-Lücke aus dem vorherigen Eintrag (weiterhin offen, weiterhin nur
vermerkt statt bearbeitet).

## Round 52 — Tier-2-Geräte-Grenzmessung: Infrastruktur + Protokoll (nicht die Messung selbst) ✅

Letzter Punkt aus der "Nächster Schritt"-Liste. Wichtiger Unterschied zu
Round 50/51: dieser Punkt konnte NICHT durch Code allein geschlossen werden
— ADR-025 verlangt explizit einen gemessenen, nicht geschätzten Wert auf
echter Hardware ("kein geschätzter 'sollte reichen'-Wert"). Ein
CPU-gedrosselter CI-Runner (`cpulimit`/cgroups, wie ursprünglich als Option
im TODO-Dokument genannt) wäre genau das gewesen, was das ADR ausschließt —
deshalb bewusst NICHT gebaut, um den Punkt nicht fälschlich als "gemessen"
erscheinen zu lassen, obwohl er nur simuliert wäre.

**Stattdessen gebaut:** die Mess-*Infrastruktur*, damit die eigentliche
Messung auf echter Hardware überhaupt praktikabel durchführbar ist, statt
sie von Hand mit einer Stoppuhr zu improvisieren:

- `Player.gd`: `_loop_free_authoritative()` misst sich selbst
  (`Time.get_ticks_usec()` vor/nach der Simulation), aggregiert über
  `static var`-Felder **pro Physik-Frame über ALLE gleichzeitig
  authoritativ simulierten Spieler** (nicht pro Spieler einzeln — die
  Zahl, die für die Geräte-Grenze zählt, ist die Gesamtkosten pro Tick).
  Ringpuffer über die letzten ~600 Frames (~10s bei 60Hz). Neue öffentliche
  statische API: `get_tier2_perf_stats()` (Sample-Anzahl, avg/p95/max in
  Mikrosekunden) und `reset_tier2_perf_stats()`.
- `SimpleTerminal.gd`: zwei neue Debug-Konsolen-Befehle, `tier2stats` und
  `tier2reset` — laufen direkt im Spiel, kein Cmdline-Trick nötig (wichtig,
  weil `IT03Harness`s `--it03-*`-Cmdline-Args auf einem normal gestarteten
  Android-Build nicht praktikabel wären, siehe unten).
- `docs/tier2-device-verification.md` (neu): vollständiges manuelles
  Protokoll — warum das nicht automatisierbar ist, was gemessen wird, welches
  Referenzgerät (Anhaltspunkt: `export_presets.cfg`s bereits committetes
  `min_sdk=24`/`arm64-v8a` als untere Grenze, kein aktuelles
  Entwickler-Flagship), Schritt-für-Schritt-Ablauf, wie das Ergebnis
  einzuordnen ist (60Hz-Tick-Budget ~16667µs, geteilt mit allem anderen —
  Movement-Sim ist nur ein Verbraucher davon, kein eigenes Budget), und wohin
  die Messwerte gehören (ADR-025 „Umsetzungsstand", datiert, mit
  Gerätemodell + Spielerzahl).
- Praktischer Kniff im Protokoll: nur das HOSTENDE Gerät muss das
  Referenzgerät sein (es simuliert die gesamte Physik) — die Mitspieler-
  Clients können von beliebiger anderer Hardware kommen, solange ihr Input
  echt und gleichzeitig eintrifft. Hält den Beschaffungsaufwand für den
  Project Owner klein (ein Referenzgerät, nicht N).

**Docs:** `TODO-offene-probleme.md` — Punkt umformuliert: Infrastruktur
fertig, Messung selbst bewusst als offener Action-Item für den Project Owner
stehen gelassen (nicht als erledigt markiert, obwohl der Code-Anteil fertig
ist — die Formulierung unterscheidet ausdrücklich zwischen beidem).
`docs/adr/025-server-authoritative-movement.md` — "Update (Round 52)"-Absatz
mit Verweis auf das neue Protokoll-Dokument.

**Ergebnis dieser Runde:** damit sind alle Punkte aus der "Nächster
Schritt"-Liste, die sich innerhalb dieser Sandbox lösen ließen, bearbeitet.
Der einzige verbleibende offene Punkt in `TODO-offene-probleme.md`s
"Nächster Schritt"-Sektion ist die tatsächliche Durchführung der
Tier-2-Messung selbst — kein Engineering-Task mehr, sondern eine Aktion, die
außerhalb dieser Sandbox liegt.



## Round 53 — SessionManager-Rest: rohe Signale → EventBus.networking() ✅

Letzter offener Punkt im 🟠-Abschnitt von `TODO-offene-probleme.md`, vom
Owner explizit priorisiert. ADR-018 (Runde 5) hatte `SystemEvents` in
Domain-Namespaces aufgeteilt, aber `SessionManager` selbst nie mitgezogen:
acht eigene rohe Godot-Signale liefen parallel zu (teils identischen)
`EventBus.networking()`-Events, und zwei Consumer (`WorldService`,
`ServiceOrchestrator`) verbanden sich direkt auf die Service-Instanz statt
über den Bus — derselbe Locator-artige Kopplungsfehler, den ADR-018
eigentlich beseitigen sollte.

**Fix:**
- `NetworkingEvents.gd`: vier neue Signale + `emit_*()` (`peer_joined`,
  `peer_left`, `peer_cleanup_requested`, `retry_attempt`). Vier weitere
  hatten bereits ein Äquivalent (`hosting_started`, `joined_as_client`,
  `connection_to_server_failed`, `network_peer_disconnected`).
- `SessionManager.gd`: alle acht eigenen `signal`-Deklarationen entfernt,
  jede Emission läuft jetzt ausschließlich über `_bus.networking().emit_*()`,
  konsequent mit `is_instance_valid(_bus)`-Guard (vorher inkonsistent).
- `WorldService`: Connect/Disconnect von `_session_manager.peer_cleanup_requested`
  auf `_bus.networking().peer_cleanup_requested` umgestellt — gleiches Muster
  wie die bestehenden `_bus.world()`/`_bus.persistence()`-Connects im selben
  Service.
- `ServiceOrchestrator`: `_connect_session_manager()` entfernt.
  `EventBus.networking.joined_as_client.connect(_on_client_connected)` läuft
  jetzt direkt in `_ready()` zusammen mit den beiden anderen BUG-23-Connects
  (vorher erst nach `boot_app()` möglich, weil an die Service-Instanz
  gebunden — `EventBus.networking` ist ein AutoLoad und existiert schon
  vorher, kein Grund mehr zu warten).

**Tests:** `test_session_manager.gd` — `before_each()` injiziert `MockEventBus`,
alle Signal-Assertions laufen über `_bus.networking()` statt über `_sm`
selbst; neuer Test `test_peer_disconnected_without_event_bus_does_not_crash()`
für den jetzt tatsächlich geprüften "kein Crash ohne Bus"-Vertrag.

**Docs:** `docs/adr/018-systemevents-domain-split.md` — Abschnitt „Update
(Runde 53)"; `TODO-offene-probleme.md` — Punkt als geschlossen markiert.

**Ergebnis:** kein direkter Service-zu-Service-Signal-Connect mehr im
gesamten Projekt — jede Cross-Service-Kommunikation läuft über `EventBus`.


## Round 54 — Settings.gd-Persistenz: ehrliche Antwort war "Nein" ✅

Letzter offener Punkt im 🟢-Abschnitt von `TODO-offene-probleme.md`
("Settings.gd — persistiert Audio/Grafik/Input-Remapping wirklich
zuverlässig?"). Verifikation ergab: **nein, gar nicht.** `Settings.gd` hielt
`_settings` als reines In-Memory-`Dictionary`; `_set_setting()` schrieb den
neuen Wert nur ins Dictionary, der einzige auskommentierte Persistenz-Pfad
(`# Optional: ProjectSettings.set_setting(...)`) war nie aktiv. Jeder
Neustart verlor Joystick-Modus, Kamera-/Zoom-Speed und Bildschirm-Rotation
kommentarlos.

**Fix — kein Workaround (z.B. `ProjectSettings` direkt aus dem UI-Panel
befüllen), sondern derselbe Service-Schnitt wie beim Rest des Projekts:**

- `SettingsService.gd` (neu, `scripts/persistence/`): `extends Service`,
  global-scoped wie `SaveSystem`/`DataService` (ADR-009-Entscheidungsbaum:
  kein Charakter-State → `global_services`). Atomic Write (tmp → rename)
  nach `user://settings.json`, analog `SaveSystem._atomic_write()` — bewusst
  eigenständig statt geteilte Utility, da beide Services unabhängig
  lebensfähig bleiben sollen. `DEFAULTS` ist jetzt die einzige Quelle der
  Wahrheit für bekannte Keys; unbekannte Keys aus der Datei werden beim
  Laden verworfen + geloggt (Symmetrie zu `DataManifest`/
  `SaveMigrationService` — kein stilles Datendrift).
- `ServiceKeys.SETTINGS_SERVICE` ergänzt, in `BootstrapConfig.tres` als
  Global-Service registriert (keine Deps).
- `BootPipeline._bridge_app_services_into_session()`: `SETTINGS_SERVICE` zur
  expliziten Cross-Scope-Bridge-Liste ergänzt — Session-UI kann den
  App-Scope-Service dadurch sehen, ohne einen zweiten Nachschlage-Pfad.
- `IUIContext`/`UIContext`: neuer Getter `get_settings()`, aufgelöst in
  `from_registry()` genau wie `get_data()`/`bus()`.
- `Settings.gd`: kein eigenes `_settings`-Dictionary mehr. `setup(ctx)` (muss
  vor `add_child()` laufen, da `_ready()` das Panel direkt aus den
  Live-Werten baut) injiziert den `SettingsService`; `_get_setting()`/
  `_set_setting()` delegieren vollständig. Ohne Service (z.B. Editor-Preview)
  degradiert das Panel explizit auf `SettingsService.DEFAULTS` im
  Nur-RAM-Modus statt zu crashen — dasselbe Muster wie `get_optional()`
  an anderer Stelle im Projekt, kein stiller Datenverlust vorgetäuscht.
- `PauseMenuController._create_and_show_settings()`: ruft `settings_node.setup(_ctx)`
  vor dem `add_child()`.

**Tests:** `tests/unit/test_settings_service.gd` (neu) — Defaults ohne Datei,
Roundtrip pro Typ (bool/float/int), mehrere `set_setting()`-Aufrufe verlieren
keine vorherigen Keys, Merge-Verhalten, korrupte Datei → Fallback, unbekannte
Keys werden beim Laden verworfen. `test_ui_context.gd` — `get_settings()`
Basisvertrag + `from_registry()`-Bridge-Pfad, analog den bestehenden
`bus()`-Tests.

**Docs:** `docs/services.md` — Zeile für `SettingsService` ergänzt.
`TODO-offene-probleme.md` — 🟢-Abschnitt jetzt leer, "Nächster Schritt"
aktualisiert.

**Bewusst nicht angefasst:** kein UI-Test für `Settings.gd` selbst (dünne
Glue-Klasse nach diesem Fix, die komplette Logik liegt jetzt in
`SettingsService` und ist dort abgedeckt — ein CanvasLayer-SceneTree-Test
hätte hier wenig zusätzlichen Wert bei spürbaren zusätzlichen Kosten).

## Round 55 — ADR-010 Tier 3 (Dedizierter Server): bewusste Abweichung, dokumentiert statt versteckt

Auftrag: "ADR 10 T3" umsetzen, ausdrücklich mit sauberer Architektur, keine
praktischen Workarounds.

Vor dem Coden geprüft: der TODO-Eintrag bündelte zwei Dinge — (1) einen
stale Node-Wrapper-Vermerk (tatsächlich längst durch `NetworkBridge extends
ServiceNode` gelöst, nur nie zurückgemeldet) und (2) Tier 3 selbst, dessen
eigene ADR-Reihenfolge-Bedingung ("erst wenn Tier 2 in echter Umgebung
nachweislich stabil läuft") durch die noch offene Geräte-Grenzmessung aus
Round 52 nicht erfüllt war. Das wurde dem Nutzer vorgelegt statt stillschweigend
übergangen — Antwort: Reihenfolge bewusst überschreiben, mit dokumentierter
Begründung.

Beim Bauen zeigte sich eine strukturelle Lücke, die ADR-010 nicht beantwortet
hatte: das Session-Modell (ADR-009) geht immer von genau einem lokal spielenden
Charakter aus (`boot_character()` lädt einen `player_id`-Save). Ein dedizierter
Server hat keinen — aber braucht trotzdem eine dauerhafte, geteilte Welt-Session.
Lösung: eine reservierte, echte Save-Identität (`DEDICATED_SERVER_WORLD_ID`),
die denselben Boot-Pfad durchläuft wie jeder Charakter — kein Sonderfall in der
Persistenz, nur `spawn_local_player=false` beim Welt-Spawn. Kein Fake-Save,
keine übersprungene Persistenz — das wäre der Workaround gewesen, den der
Auftrag ausdrücklich ausschloss.

**Geändert:**
- `scripts/session/SessionManager.gd` — `DEDICATED_SERVER_WORLD_ID`-Konstante,
  `enable_dedicated_server_mode()`/`is_dedicated_server()`, `_tier_name()`
  unterscheidet jetzt Tier 2 (Host spielt mit) von Tier 3.
- `scripts/platform/DedicatedServerBootstrap.gd` (neu, Autoload) — Cmdline-gated
  (`--dedicated-server`), bootet Host + reservierte Welt-Session, Fail-Fast
  (`quit(1)`) statt stillem Hängen bei Hosting-Fehlern.
- `scripts/world/core/WorldSpawner.gd` / `WorldService.gd` — `spawn_local_player`-
  Parameter (Default `true`, Tier 1/2 unverändert).
- `export_presets.cfg` — Preset "Linux Dedicated Server" (`dedicated_server=true`).
- `scripts/economy/inventory/InventorySystem.gd` — Slot-/Gewichts-Re-Validierung
  direkt in `on_item_add_confirmed()` als Verteidigung in der Tiefe (kein
  konkreter Angriffsweg mehr vorhanden seit Round 45, aber Tier-3-Prinzip
  "Server vertraut niemandem" heißt: an der Mutationsstelle prüfen, nicht nur
  der Caller-Konvention vertrauen).
- `docs/adr/010-multiplayer-authority-tiers.md` — Abschnitt "Update (Round 55)":
  Abweichungsbegründung, strukturelle Lücke, Umsetzungsstand, was bewusst offen
  bleibt (CI-Build-Job für den Server-Export, Lastvalidierung, Ops-Tooling).
- `docs/MIGRATION-010.md` — zwei stale Einträge korrigiert (Node-Wrapper,
  Slot-/Gewichts-Re-Validierung — beide bereits gelöst bzw. gegenstandslos seit
  Round 45, nie zurückgemeldet).
- `TODO-offene-probleme.md` — Eintrag geschlossen, mit Verweis auf das
  ADR-010-Update statt nur abgehakt.
- Tests: `test_session_manager.gd`, `test_world_spawner.gd`,
  `test_inventory_system.gd` — je 3–4 neue Fälle für die obigen Änderungen.

**Bewusst nicht Teil dieser Runde** (siehe ADR-010-Update): kein CI-Job, der den
Server-Export tatsächlich baut; keine Lastvalidierung mit echten Clients gegen
eine reale Tier-3-Instanz; kein Admin-/Ops-Tooling.

## Round 56 — ADR-028: Kein Host-Migration-Konzept, aber der eigentliche Hänger behoben

Nächster 🟠-Punkt: "Kein Host-Migration-Konzept. Host disconnected = Session tot."

Root-Cause vor dem Coden geprüft statt direkt draufloscodiert: es gab bereits zwei
Drittel eines Fixes, die nirgendwo ankamen. `SessionManager._on_server_disconnected()`
emittiert korrekt `network_peer_disconnected`; `MainMenuController` hört bereits
darauf und würde einen Statustext zeigen — nur ist die MainMenu-Szene während des
Spiels gar nicht sichtbar. Der fehlende Teil: `GameManager` (einzige Instanz, die
State-Wechsel + Szenenwechsel auslöst) hörte auf dieses Signal überhaupt nicht.
Der Client blieb nach Host-Verlust für immer im State PLAYING hängen, mit totem
Peer, nie abgebauter CharacterScope/WorldScope — kein Rückweg außer App-Neustart.

Entscheidung dokumentiert in [ADR-028](docs/adr/028-host-disconnect-session-teardown.md):
bewusst KEINE echte Host-Migration (Re-Election + State-Handoff) — das listen-server-
Modell aus ADR-010 hat keine der Voraussetzungen (keine redundante Weltkopie bei
Clients, kein Rollenwechsel zur Laufzeit), wäre ein eigener großer Umbau, kein
inkrementeller Fix. Stattdessen: geordnete Session-Beendigung, per Wiederverwendung
des bereits existierenden Teardown-Pfads (`ServiceOrchestrator._on_state_changed()`
bei Übergang zu MAIN_MENU) — kein zweiter Teardown-Mechanismus.

**Geändert:**
- `scripts/platform/GameManager.gd` — neue `_on_host_connection_lost()`, verdrahtet
  in `on_ready()` auf `EventBus.networking.network_peer_disconnected`.
- `docs/adr/028-host-disconnect-session-teardown.md` (neu) + Index-Eintrag.
- `TODO-offene-probleme.md` — Eintrag geschlossen.
- `tests/unit/test_game_manager.gd` — 5 neue Fälle (PLAYING/LOADING/PAUSED →
  MAIN_MENU, No-op falls schon im Menü, Kontrollfall ohne `on_ready()`).

**Bewusst offen gelassen** (siehe ADR-028 "Negativ/Risiken"): kein Auto-Save bei
Disconnect — identisch zum bereits bestehenden Verhalten des regulären
Menü-Exits, keine neue Regression, aber hängt am ungelösten TODO-Punkt
"Save-Konflikt-Handling fehlt" (Save-Semantik in Multiplayer generell ungeklärt).

## Round 57 — ADR-029: Stabile Spieler-Identität (Entscheidung dokumentiert, noch nicht umgesetzt)

Bei der Vorbereitung von "Reconnect-Recovery" (🟠) zeigte sich beim Rückfragen
ein tieferliegendes Problem: der komplette multi-tenante Session-State
(`InventorySystem`/`QuestService`/`SkillSystem`/`EquipmentService`) ist per
ENet-`peer_id` verschachtelt, nicht per stabiler Spieler-Identität —
`ServiceOrchestrator._on_client_connected()` vergibt Save-Identitäten sogar
direkt als `"client_%d" % local_peer`. Das ist nicht nur eine
Reconnect-Voraussetzung, sondern ein bestehender Korrektheits-Bug im
produktiven Tier-2-Pfad: zwei unterschiedliche Freunde, die in zwei Sessions
beide als "Peer 2" verbinden, teilen sich denselben gespeicherten Bucket.

Auf Nachfrage ("was ist die sauberste Lösung, auch wenn viel Arbeit") die
volle Lösung skizziert und in [ADR-029](docs/adr/029-stable-player-identity.md)
dokumentiert: `player_uuid` im Save statt `peer_id`, Join-Handshake (Server
liest die Zuordnung aus dem RPC-Absender, nie aus einem Client-Argument),
`SessionManager._peer_slots` wird die kanonische Übersetzung, Rekeying der
vier Session-Services auf `String`-Keys, Save-Migration für Bestandsdaten.
Explizit als mehrere Runden Aufwand markiert, keine Ein-Runden-Lösung.

Diese Runde: **nur** das ADR + TODO-Priorisierung, auf ausdrücklichen Wunsch
noch keine Implementierung.

**Geändert:**
- `docs/adr/029-stable-player-identity.md` (neu) + Index-Eintrag. Grenzt sich
  explizit von ADR-015 ab (Routing-`peer_id` bleibt korrekt, nur die
  zusätzliche Persistenz-Nutzung ist das Problem).
- `TODO-offene-probleme.md` — neuer 🔴🔴-Block ganz oben (höchste Priorität,
  vor der bereits gelösten `multiplayer_authority`-Sektion), mit
  Querverweisen von "Kein Reconnect-Recovery" und "Save-Konflikt-Handling
  fehlt" (beide 🟠), da beide laut ADR-029 an diesem Fund hängen.
  "Nächster Schritt" entsprechend aktualisiert.

## Round 58 — ADR-029 Phase 1: Vorarbeit dokumentiert, Implementierung noch offen

Auf "Go ahead" mit der Phase-1-Umsetzung (`player_uuid` im Save + Join-Handshake)
begonnen. Vor dem ersten Zeilencode Architektur-Fakten geprüft (Scope von
`NetworkBridge`/`SaveSystem`, bestehender Code in `BootPipeline.boot_character()`
Phase C9, aktueller Join-UI-Flow) — dabei zeigte sich, dass der Umfang größer
ist als die ursprüngliche verbale Skizze ("player_uuid + Handshake"):

1. `NetworkBridge` ist session-/charakterscoped (wird bei jedem
   `teardown_character()` mit zerstört) — ein neuer `PlayerCredentialStore`
   darf seinen Zustand deshalb nicht im Node selbst halten, sondern muss über
   `SaveSystem`s Pull-Provider-Konvention (`ISaveProvider`) persistieren.
2. `BootPipeline.boot_character()` Phase C9 registriert bereits
   `SessionManager.register_player_slot(local_peer, player_id)` — sieht aus
   wie die geforderte Übersetzung, ist es aber nicht: läuft rein lokal, pro
   Prozess für sich selbst. Der Server erfährt nie, welche Identität ein
   *remote* Client gewählt hat. Das ist die konkrete Lücke, die der
   Join-Handshake schließt — Phase C9 selbst bleibt unverändert korrekt.
3. Der Join-Flow in `MainMenuController` überspringt Charakterauswahl
   komplett (IP:Port → direkt `PLAYING` via `"client_%d"`-Auto-Boot in
   `ServiceOrchestrator._on_client_connected()`). Damit ein Client überhaupt
   einen echten lokalen Charakter für den Handshake auswählen kann, braucht's
   einen neuen UI-Zwischenschritt — nicht nur Backend-Plumbing.

Auf Nutzerwunsch diese Runde **nur dokumentiert statt durchimplementiert** —
die Funde sind in [ADR-029 "Implementierungsnotizen (Round 58)"](docs/adr/029-stable-player-identity.md)
festgehalten, dazu eine konkrete 5-Punkte-Checkliste in
`TODO-offene-probleme.md`, damit die nächste Runde nicht erneut bei Null
recherchieren muss.

**Geändert:**
- `docs/adr/029-stable-player-identity.md` — Abschnitt 3a (`player_secret`/
  Trust-on-First-Use-Credential-Abstraktion), erweiterte "Ablösung" (Option-C-
  Kurzplan: getrennter Account-Service, E-Mail/Passwort-Reset, Handshake
  bleibt strukturell gleich), neuer Abschnitt "Implementierungsnotizen
  (Round 58)".
- `TODO-offene-probleme.md` — Phase-1-Checkliste unter dem 🔴🔴-Punkt ergänzt.

**Kein Code diese Runde.** Nächster Schritt: die fünf Checklisten-Punkte
tatsächlich umsetzen — `SaveSystem`-Felder zuerst (keine Abhängigkeiten zu
anderen Punkten), dann `PlayerCredentialStore`, dann Handshake-RPC, dann
UI-Flow, dann `ServiceOrchestrator`-Anpassung.

## Round 59 (läuft) — ADR-029 Phase 1, Schritt 1/5: `player_uuid`/`player_secret` in SaveSystem

**Fertig:** `scripts/persistence/UuidGen.gd` (neu, lokale UUID-v4-Erzeugung,
bewusst eigenständig von `EntityOrchestrator._generate_uuid()` — andere
Aufrufer-Constraints, siehe Kommentar dort). `SaveSystem`: generiert/persistiert
`player_uuid`+`player_secret` pro Charakter-Save, Getter, Alt-Save-Migration
(fehlt das Feld, wird beim Laden einmalig erzeugt).

**Beim Umsetzen gefunden, sofort mitgefixt (nicht Teil der ursprünglichen
Checkliste):** `get_full_state()` wird per Sprint-D-Snapshot an JEDEN neu
verbindenden Client geschickt — ohne Gegenmaßnahme wäre `player_secret` der
Autorität an jeden Joiner mitgeschickt worden und hätte das komplette
Trust-on-First-Use-Modell aus ADR-029 (3a) ausgehebelt. Fix: `player_uuid`/
`player_secret` werden in `begin_session()` aus `_loaded_state` in eigene
Felder extrahiert und sofort aus `_loaded_state` entfernt — `get_full_state()`
sieht sie nie. Zusätzlich in `apply_remote_state()` defensiv nochmal entfernt
(Verteidigung in der Tiefe, falls ein künftiger Pfad sie doch hineinschmuggelt).

**Tests:** `tests/unit/test_uuid_gen.gd` (neu, 3 Fälle), `test_save_system.gd`
+8 Fälle (Erzeugung, Stabilität über Save/Load, unterschiedliche Charaktere,
Alt-Save-Migration, `end_session()`-Clearing, die beiden Leak-Fälle oben,
Disk-Persistenz).

**Noch offen (Schritte 2-5 der Checkliste):** `PlayerCredentialStore`,
Join-Handshake-RPC, MainMenu-Charakterauswahl nach Join, `_on_client_connected()`-
Umbau. Weiter mit Schritt 2.

## Round 59 (Fortsetzung) — Kurskorrektur: Handshake gehört zu SessionManager, nicht NetworkBridge

Beim Verdrahten von `PlayerCredentialStore` (Schritt 2) zeigte sich ein
Sequenzierungsproblem: `NetworkBridge` existiert erst innerhalb einer bereits
gebooteten `CharacterScope` (`boot_character()` Phase C7) — der Handshake muss
aber VOR der Charakterauswahl laufen, weil der Client über dessen Ergebnis
hinweg erst entscheidet, welchen Charakter er bootet. Zu dem Zeitpunkt gibt es
noch kein `NetworkBridge`, also keine Stelle für `@rpc`-Methoden.

Korrektur: `SessionManager` (`extends ServiceNode`, app-scoped, lebt für die
ganze App-Laufzeit, bereits die Quelle der Wahrheit für `_peer_slots`) ist der
richtige Ort. `PlayerCredentialStore`-Klasse bleibt unverändert (reine
TOFU-Logik, unabhängig davon wer sie hält), nur die geplante Verdrahtung in
`NetworkBridge.configure()` wurde zurückgebaut — hätte sonst falschen,
irreführenden Code verschickt.

Dabei eine weitere offene Frage gefunden, bewusst nicht in dieser Runde
gelöst: auf einem Tier-2-Host kann ein Client verbinden und handshaken, BEVOR
der Host selbst einen Charakter gewählt hat (`HOST_ACTIVE`-Zustand wartet auf
UI-Klick) — `SaveSystem` hat dann noch keine aktive Session, `PlayerCredentialStore`
kann nirgendwo persistieren. Zwei Optionen skizziert (RAM-Puffer vs.
Handshake zurückstellen), Entscheidung auf die nächste Runde verschoben, bevor
der eigentliche Handshake gebaut wird. Tier 3 ist nicht betroffen (Welt-Session
bootet automatisch ohne UI-Warten, Round 55).

**Geändert:**
- `scripts/networking/PlayerCredentialStore.gd` (neu) — TOFU-Verifikation,
  Doc-Kommentar auf `SessionManager` als korrekten Halter korrigiert.
- `scripts/networking/NetworkBridge.gd` — Wiring-Versuch zurückgebaut.
- `docs/adr/029-stable-player-identity.md` — Checkliste aktualisiert, neuer
  Abschnitt "Korrektur (Round 59)".
- `TODO-offene-probleme.md` — Checkliste synchronisiert.

**Kein weiterer Code diese Runde** — nächster Schritt: die Tier-2-Timing-Frage
entscheiden, dann `SessionManager`-Wiring + `_rpc_join_handshake` bauen.

## Round 60 — ADR-029 Phase 1, Schritte 2+3: PlayerCredentialStore + Join-Handshake-RPC

Timing-Problem aus Round 59 gelöst (siehe Chat): `PlayerCredentialStore` war
fälschlich über `ISaveProvider` an die Charakter-Save gekoppelt — TOFU-Secrets
gehören aber zur Server-Installation, nicht zum Charakter. Umgestellt auf
eigene Datei (`user://server_credentials.json`), geladen einmalig in
`SessionManager.on_ready()` — löst die Tier-2-Race vollständig auf statt sie
zu umgehen.

**Geändert:**
- `scripts/networking/PlayerCredentialStore.gd` — von `ISaveProvider` auf
  eigenständiges Atomic-Write-Datei-I/O umgestellt (`load()`/`save()`).
- `scripts/session/SessionManager.gd` — `_credentials`-Feld (geladen in
  `on_ready()`), `_handshake_done`-Tracking (getrennt von `_peer_slots`, weil
  letzteres schon bei rohem ENet-Connect einen synthetischen `"peer_%d"`-
  Platzhalter bekommt), `send_join_handshake()` (Client-API),
  `_rpc_join_handshake()`/`_rpc_join_handshake_result()` (RPC-Paar, analog
  NetworkBridge-Konventionen). Bewusst kein Rate-Limiting — als eigener
  TODO-Punkt vermerkt statt stillschweigend ausgelassen.
- `scripts/networking/NetworkingEvents.gd` — neues Signal
  `join_handshake_result(accepted, reason)` + Emit-Funktion.
- `docs/adr/029-stable-player-identity.md` / `TODO-offene-probleme.md` —
  Checkliste synchronisiert (Schritte 1-3 von 5 jetzt erledigt).

**Tests bewusst zurückgestellt** (Nutzerwunsch) — folgen für Schritt 2+3
gemeinsam in der nächsten Runde, vor Schritt 4 (MainMenuController).

**Noch offen:** Schritt 4 (`MainMenuController`-Charakterauswahl nach Join),
Schritt 5 (`ServiceOrchestrator._on_client_connected()`-Umbau).

## Round 61 — ADR-029 Phase 1: Tests für PlayerCredentialStore + Handshake nachgezogen

Wie in Round 60 angekündigt, Tests für Schritte 2+3 nachgeliefert.

Beim Schreiben zwei kleine, aber notwendige Code-Anpassungen (keine reinen
Testdateien):

1. `PlayerCredentialStore`: Pfad war als `const SAVE_PATH` hart codiert —
   jeder Test hätte in die echte `user://server_credentials.json` geschrieben.
   Umgestellt auf `_init(save_path: String = DEFAULT_SAVE_PATH)` — Produktion
   nutzt weiter den Default, Tests injizieren einen Testpfad.
2. `SessionManager._rpc_join_handshake()`: Kernlogik in eine testbare
   `_handle_join_handshake(sender, player_uuid, player_secret)` aufgetrennt —
   `multiplayer.get_remote_sender_id()` liefert außerhalb eines echten
   eingehenden RPC-Aufrufs immer 0, exakt dasselbe Problem, das
   `NetworkBridge._is_rate_limited(rpc_name, peer_id)` schon lange löst
   (dort als etabliertes Muster übernommen, nicht neu erfunden). Dazu ein
   Test-Seam `set_credentials_for_testing()`, klar als Test-only
   dokumentiert (kein DI-Dep, keine Produktions-Konfigurationsmöglichkeit).

**Geändert:**
- `scripts/networking/PlayerCredentialStore.gd` — Pfad überschreibbar.
- `scripts/session/SessionManager.gd` — `_handle_join_handshake()` extrahiert,
  `set_credentials_for_testing()` Test-Seam.
- `tests/unit/test_player_credential_store.gd` (neu, 13 Fälle).
- `tests/unit/test_session_manager.gd` (+7 Fälle: Erst-Kontakt, Wiederholung,
  Secret-Mismatch, Multi-Peer-Isolation, das ADR-029-Kernszenario "zwei
  Menschen teilen sich eine player_uuid nicht ohne passendes Secret", sowie
  Persistenz über einen simulierten Server-Neustart).
- `TODO-offene-probleme.md` — Checkliste synchronisiert (Tests für Schritt 2+3 ✓).

**Weiter offen:** Schritt 4 (`MainMenuController`-Charakterauswahl nach Join),
Schritt 5 (`ServiceOrchestrator._on_client_connected()`-Umbau) — beide noch
nicht angefangen.

## Round 62 — ADR-029 Phase 1, Schritte 4+5: Charakterauswahl nach Join, Auto-Boot entfernt

Die beiden letzten offenen Punkte der Phase-1-Checkliste umgesetzt und
getestet.

**`MainMenuController`:** neuer View-Zustand `JOIN_CHARACTER_SELECT`. Nach
`joined_as_client` wird jetzt die Charakterliste gezeigt statt automatisch zu
booten; Auswahl (Charakter-Button oder `[Neues Spiel]`) löst
`SaveSystem.begin_session()` + `SessionManager.send_join_handshake()` aus.
`join_handshake_result` bootet bei Erfolg (`session_requested`), bei Ablehnung
`SaveSystem.end_session()` + zurück zur Auswahl mit Fehlertext.

**`ServiceOrchestrator`:** `_on_client_connected()`/`"client_%d"`-Auto-Boot
entfernt — musste zwangsläufig mit rein, sonst wäre der neue View-Zustand
toter Code gewesen, den der alte Auto-Boot beim selben Signal sofort überholt
hätte. `SessionManager` wird jetzt zusätzlich zu `SaveSystem` ins MainMenu
injiziert (`inject_session_manager()`, analog zum bestehenden Muster).

**Zwei Bugs unterwegs gefunden und mitgefixt, keine reinen Testdateien:**

1. `SaveSystem.begin_session()`-Idempotenz-Guard. Der neue Flow ruft
   `begin_session()` zwangsläufig zweimal für dieselbe `player_id` auf — einmal
   vom Menü vor dem Handshake (um `player_uuid`/`player_secret` zu lesen),
   einmal danach regulär von `BootPipeline.boot_character()` Phase C1. Ohne
   Guard hätte der zweite Aufruf bei einem frisch angelegten Charakter (noch
   kein Save auf Disk) eine zweite, andere Zufalls-Identität erzeugt als die
   im Handshake bereits verschickte — Client wäre mit einer vom Server nie
   akzeptierten Identität gebootet, ohne sichtbaren Fehler. Gefunden beim
   Nachvollziehen des Flows vor dem eigentlichen Coden, nicht erst beim
   Testen — Guard direkt mit eingebaut. Fix: zweiter Aufruf für dieselbe
   `player_id` bei bereits aktiver Session ist ein No-Op.
2. Status-Text-Überschreibung im Ablehnungsfall. Erst beim Schreiben des
   Ablehnungs-Tests gefunden: `_on_join_handshake_result()` setzte den
   Ablehnungsgrund, bevor es `_show_view(JOIN_CHARACTER_SELECT)` aufrief —
   `_show_view()` setzt für diesen Zustand aber selbst einen generischen
   Status-Text, der die eigentliche Fehlermeldung sofort wieder überschrieben
   hätte, bevor der Spieler sie lesen kann. Reihenfolge getauscht.

**Tests:** `test_main_menu_controller.gd` bekommt einen `SessionManagerDouble`
(Spy für `send_join_handshake()`) neben dem erweiterten `SaveSystemDouble`
(Tracking für `begin_session()`/`end_session()`, feste Uuid/Secret-Getter) —
neun neue Fälle: Handshake-Auslösung statt Direkt-Boot (Charakter- und
`[Neues Spiel]`-Pfad), akzeptierter/abgelehnter Handshake inkl. Statustext,
verspätetes Ergebnis ohne laufenden Handshake (Ignorieren statt
versehentlichem Boot), fehlende `SessionManager`-Injektion (Guard-Reihenfolge
vor `begin_session()`), Verbindungsabbruch während eines laufenden
Handshakes. `test_save_system.gd` bekommt fünf neue Fälle für den
`begin_session()`-Guard (inkl. beider Abgrenzungen: nicht über verschiedene
`player_id`s hinweg, nicht nach zwischenzeitlichem `end_session()`).

**Geändert:**
- `scripts/ui/MainMenuController.gd` — `JOIN_CHARACTER_SELECT`-Zustand,
  `inject_session_manager()`, Handshake-Start/-Ergebnis-Handler,
  Statustext-Reihenfolgen-Fix.
- `scripts/platform/ServiceOrchestrator.gd` — Auto-Boot entfernt,
  `SessionManager`-Injektion ins MainMenu ergänzt.
- `scripts/persistence/SaveSystem.gd` — Idempotenz-Guard in `begin_session()`.
- `tests/unit/test_main_menu_controller.gd` (+9 Fälle, neue Doubles
  `SaveSystemDouble`/`SessionManagerDouble`).
- `tests/unit/test_save_system.gd` (+5 Fälle für den Guard).
- `docs/adr/029-stable-player-identity.md` — Checkliste synchronisiert (Schritt
  4+5 ✓), neuer Abschnitt "Implementierungsnotizen (Round 62)".
- `TODO-offene-probleme.md` — Checkliste synchronisiert.

**Damit ist die Phase-1-Checkliste aus ADR-029 vollständig abgehakt.** Der
größere, noch offene Teil des ADR ist unverändert: das eigentliche Rekeying
von `InventorySystem`/`QuestService`/`SkillSystem`/`EquipmentService` von
`peer_id: int` auf `player_id: String` (ADR-Plan-Schritt 4) sowie die
Save-Migration für Bestandsdaten (ADR-Plan-Schritt 5) — das sind die
numerierten Schritte im ADR-Fließtext, nicht identisch mit der Phase-1-
Checkliste, die hier abgeschlossen wurde. Reconnect-Recovery und
Save-Konflikt-Handling (beide 🟠 in der TODO) bleiben bis dahin blockiert.

## Round 63 — ADR-029 Plan-Schritt 4 begonnen: InventorySystem auf `player_id: String` rekeyed

Phase 1 der ADR-029-Checkliste war mit Round 62 abgeschlossen. Round 63 beginnt
den eigentlich größeren Umbau aus dem ADR-Fließtext ("Rekeying der
Session-Services", Plan-Schritt 4) — als ersten vollständigen Vertikalschnitt
an `InventorySystem`, dem kleinsten der vier Services (`QuestService`,
`SkillSystem`, `EquipmentService` folgen in künftigen Runden nach demselben
Muster).

**Vorab-Recherche vor dem Coden** (Code gelesen statt der verbalen Skizze
gefolgt) ergab zwei Kopplungsstellen außerhalb dessen, was ursprünglich
skizziert war:

1. `NetworkBridge._sender_as_player_id()` wird von sechs `_rpc_*`-Handlern
   geteilt, die in noch nicht migrierte Services reichen — eine sofortige
   Umstellung auf `String` hätte die anderen fünf gebrochen. Stattdessen: ein
   neuer, separater `_sender_as_player_uuid()`-Helfer, vorerst ungenutzt
   (`InventorySystem` hat seit Round 45 gar keinen `_rpc_*`-Handler mehr —
   Item-Grants laufen ausschließlich autoritätsseitig über
   `RewardDispatcher`/`InteractionResolver`/`EnemyNPC._die()`).
2. `InventorySystem` hat zwei Aufrufer, die selbst noch nicht migriert sind
   (`RewardDispatcher.dispatch()`, `EquipmentService.on_equip_confirmed()`) —
   beide übersetzen jetzt an genau der einen Aufrufgrenze in den migrierten
   Service, über denselben kanonischen `NetworkBridge.get_player_id_for_peer()`-
   Getter, den `NetworkBridge` bereits für sich selbst nutzt. Bewusst keine
   neue Abstraktion für zwei Aufrufer — und bewusst Übergangs-Verkabelung,
   keine Dauerlösung: sobald `SkillSystem`/`EquipmentService` selbst migriert
   sind, verschwindet die jeweilige Übersetzungszeile ersatzlos.

Beide Funde + die Begründung, warum das die etablierte Übergangs-Form aus
ADR-015 wiederholt statt ein neues Muster einzuführen, stehen ausführlicher in
[ADR-029 "Implementierungsnotizen (Round 63)"](docs/adr/029-stable-player-identity.md).

**Beim Verdrahten gefundener Zirkulär-Dep-Fehler, mitgefixt statt nur
notiert:** `RewardDispatcher` hätte `NetworkBridge` fast als normalen
`configure()`-Dep bekommen — wäre ein Zyklus gewesen
(`network_bridge → quest → reward_dispatcher → network_bridge`, da `quest`
`reward_dispatcher` als Dep deklariert). Gefunden beim Abgleich gegen
`BootstrapConfig.tres`, vor dem Testen. Fix: `RewardDispatcher` bekommt
`inject_network_bridge()` und kommt über denselben Phase-C8-Late-Inject wie
Inventory/Quest/SkillSystem/Equipment/World (`BootPipeline.gd`-Loop um
`ServiceKeys.REWARD_DISPATCHER` ergänzt).

**Parameter-Reihenfolge geändert, nicht nur Typ.** `player_id` ist jetzt auf
allen öffentlichen `InventorySystem`-Methoden Pflichtparameter ohne Default
(keine sinnvolle String-Entsprechung zum früheren `= 1`) — GDScript erlaubt
keinen Pflichtparameter nach einem Default-Parameter, deshalb mussten
`has_item()`/`remove_item()`/`request_add_item()` umsortiert werden
(`player_id` jetzt vor dem optionalen `quantity`).

**Save-Migration (Plan-Schritt 5) entfällt.** Auf Bestätigung: keine
nennenswerten Bestandsdaten in existierenden Coop-Saves — sauberer Schnitt,
`_restore_from_save()` erwartet direkt `player_id`-Strings als Keys.

**Geändert:**
- `scripts/session/SessionManager.gd` — `get_local_player_id()`,
  `get_peer_id_for_player()`.
- `scripts/networking/NetworkBridge.gd` — String-Fassaden,
  `_sender_as_player_uuid()` (vorbereitet), `send_economy_update_for_player()`.
- `scripts/economy/inventory/InventorySystem.gd` — vollständig migriert.
- `scripts/economy/rewards/RewardDispatcher.gd`,
  `scripts/economy/equipment/EquipmentService.gd` — Übersetzung an der
  jeweiligen Inventory-Aufrufgrenze.
- `scripts/platform/BootPipeline.gd` — `REWARD_DISPATCHER` in Phase-C8-Liste.
- `scripts/platform/interfaces/IUIContext.gd`, `UIContext.gd`,
  `InventoryUIController.gd`, `EquipmentUIController.gd` — `get_local_player_id()`.
- Tests: `test_inventory_system.gd`, `test_inventory_ui_signal.gd`,
  `test_equipment_service_r4.gd`, `test_network_bridge.gd`,
  `test_entity_context.gd`, `test_ui_context.gd` (+4), `test_session_manager.gd`
  (+5, SM-13/SM-14), `test_player_identity_access_boundary.gd` (neu).
- `docs/adr/029-stable-player-identity.md`, `TODO-offene-probleme.md` —
  Plan-Schritt-4-Checkliste synchronisiert.

**Noch offen:** `QuestService`/`SkillSystem`/`EquipmentService` nach
demselben Muster (vermutlich schneller, da das Muster jetzt steht). Alle
Test-Änderungen in dieser Runde sind nur statisch geprüft — kein
Godot/GUT-Runtime in diesem Coding-Environment verfügbar, folgt als
nächster Schritt.

## Round 94 — NPC-Shop-System: Kristall-/Scroll-Beschaffung über ShopService

Nächster Schritt aus Round 93 ("Als Nächstes: NPC-Shop-System"). Vor dem
Coden geprüft, ob wirklich ein neuer Service/ADR nötig ist — Ergebnis: nein.
`ShopService` (Round 88) ist bereits ein reiner Katalog-Kauf-Mechanismus
(item_id → Preis in Gold, netzwerksicher über `NetworkBridge`, serverseitige
Neuvalidierung von Gold/Inventarplatz) — exakt das, was ADR-038/ADR-039
unter "Ablösung"/"Mitigationen" für die Scroll-/Kristall-Beschaffung
skizzieren. Ein neues ADR hätte hier nur eine bereits gelöste Frage erneut
aufgerollt.

**Geändert:**
- `scripts/economy/shop/ShopService.gd` — `BUY_CATALOG` um alle drei
  ADR-038-Scrolls (`scroll_pve_protection` 40, `scroll_theft_protection` 40,
  `scroll_pvp_protection` 80) und alle drei ADR-039-Kristalle
  (`theft_crystal_weak` 15, `theft_crystal_normal` 60,
  `theft_crystal_strong` 400) erweitert. Preise dokumentierte Platzhalter,
  wie alle anderen Balance-Werte im Projekt (AURA_VULNERABILITY_THRESHOLD,
  TIER_BONUS, ...) - Kristall-Preise gestaffelt nach
  PickpocketService.TIER_BONUS/TIER_COOLDOWN_SEC (der "strong"-Kristall
  ist trotz nur +20% Bonus durch seinen 24h-Cooldown der mit Abstand
  teuerste). Kein anderer Code-Pfad geändert.
- `docs/adr/038-item-protection-triad.md` / `docs/adr/039-pickpocketing.md`
  - je ein "Update (Round 94)"-Abschnitt.
- `TODO-offene-probleme.md` - Round-94-Eintrag ergänzt.
- `tests/unit/test_shop_service.gd` - 5 neue Tests: Preise für alle sechs
  neuen Katalog-Einträge (2 Tests), is_buyable() für alle sechs (1 Test),
  zwei End-to-End-Kauf-Tests (Scroll und der teuerste Kristall).

**Ehrlich offen (wie in jeder Runde seit 89):** kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar - nur strukturell
geprüft, nicht gegen die echte Godot/GUT-Runtime gelaufen.

**Als Nächstes:** Wetter-Events (weather_changed), PvP-Events
(player_killed_by_player), oder eines der weiterhin offenen Themen in
TODO-offene-probleme.md (Chat/Social, Reporting/Moderation, Telemetrie,
Tutorial/Onboarding) - alle vier bisher 0 Treffer im Code.

## Round 95 — ADR-041: Wetter-Events (`weather_changed`)

Nächster Schritt aus Round 94 ("Als Nächstes: Wetter-Events"). Erster der
drei in Round 90 gebündelten Punkte; PvP-Events und Achievement-Events
bleiben offen (eigene Trigger-Analysen, eigene Folge-Runden).

Vor dem Coden geprüft: gibt es bereits einen "an alle Peers"-Broadcast-
Mechanismus, den ein serverseitig gewürfeltes Wetter nutzen könnte? Nein —
ADR-035 dokumentiert dieselbe Lücke bereits für Auktionshaus-Live-Updates.
Ein neues RPC dafür zu bauen wäre kein reiner Feature-Fix mehr gewesen,
sondern zusätzlich ein Infrastruktur-Umbau. Stattdessen: deterministischer
Wurf pro Peer aus bereits geteilten, deterministischen Werten
(`world_seed` + `day_count`) — exakt dasselbe Prinzip wie
`TerrainGenerator`/`ChunkManager`. Volle Optionsabwägung siehe ADR-041.

**Geändert:**
- `scripts/world/weather_time/WeatherService.gd` (neu, `RefCounted`,
  Sibling zu `WorldTimeService`) — `WEATHER_TYPES`
  (clear/rain/storm/fog/snow), `roll_for_day(day_count, world_seed)`
  (idempotent pro Tag, `RandomNumberGenerator.seed = world_seed * 1000003 +
  day_count`), `restore()`/`get_save_data()`.
- `scripts/world/core/WorldEvents.gd` — neues Signal
  `weather_changed(new_weather, old_weather)` + `emit_weather_changed()`.
- `scripts/world/core/WorldService.gd` — `_weather`-Feld, instanziiert in
  `configure()` neben `_time`; erster Wurf am Ende von `configure()` (nach
  `data.world_seed` final gesetzt UND nach `restore_world()`); weitere
  Würfe in `on_tick()` bei jedem `day_count`-Rollover. Neue
  `current_weather`-Property. Lokale UI-Notification bei tatsächlicher
  Änderung über `EventBus.ui().emit_notification()` (rein pro Peer, gleiches
  Prinzip wie `QuestCustomTrigger.hint_text`, Round 73).
- `scripts/world/core/WorldSaveHandler.gd` — `weather`/
  `weather_last_rolled_day` im Save-Snapshot. Konstruktor-Parameter
  `weather: WeatherService = null` (optional) — bestehende Aufrufer/Tests
  ohne WeatherService bleiben unverändert kompilierbar, Wetter-Keys werden
  dann einfach ausgelassen statt zu crashen.
- `docs/adr/041-weather-events.md` (neu), `docs/adr/000-index.md`,
  `docs/services.md` (WorldService-Zeile, `world_state`-Schema,
  `weather_changed`-Event-Zeile).
- `TODO-offene-probleme.md` — Wetter-Events aus der Dreier-Bündelzeile
  herausgelöst (erledigt), Round-95-Eintrag ergänzt.
- Tests: `tests/unit/test_weather_service.gd` (neu, 13 Fälle —
  Default-Zustand, Determinismus über zwei unabhängige Instanzen,
  statistische Streuung über Seeds/Tage, Idempotenz pro Tag,
  Signal-Emission nur bei tatsächlicher Änderung, Verhalten ohne EventBus,
  Save/Restore-Roundtrip inkl. Alt-Save-Fallback), `test_world_save_handler.gd`
  (+4: mit/ohne WeatherService, Restore-Roundtrip, Alt-Save-Verträglichkeit),
  `test_world_service.gd` (+2: `current_weather`-Property, Save-Data-Keys).

**Ehrlich offen (wie in jeder Runde seit 89):** kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar - nur strukturell
geprüft (Klammern, Signaturen gegen die echten Service-APIs abgeglichen),
nicht gegen die echte Godot/GUT-Runtime gelaufen. Zusätzlich bewusst nicht
Teil dieser Runde: visuelle Wetter-Effekte, Gameplay-Auswirkungen
(Angel-/Ernte-Boni etc.), Biom-Abhängigkeit der Wetter-Gewichtung,
serverseitig erzwungene Wetterwechsel — siehe ADR-041 "Bewusst nicht Teil
dieser Runde" für die volle Liste.

**Als Nächstes:** PvP-Events (player_killed_by_player), Achievement-Events,
oder eines der weiterhin offenen Themen in TODO-offene-probleme.md
(Chat/Social, Reporting/Moderation, Telemetrie, Tutorial/Onboarding).

## Round 96 — ADR-042: An-alle-Peers-Broadcast-Mechanismus

Explizit angeforderter nächster Schritt (nicht aus der Round-95-"Als
Nächstes"-Liste, sondern direkte Vorgabe). Schließt die Lücke, die ADR-035
(Auktionshaus, Round 89) und ADR-041 (Wetter, Round 95) beide unabhängig
voneinander als fehlend dokumentiert hatten: das Projekt hatte keinen
Mechanismus, um eine Nachricht an ALLE aktuell verbundenen Peers zu
schicken, nur 1:1-Adressierung (`send_economy_update_for_player()`,
`send_zone_update_for_peer()`).

Vor dem Coden geprüft: Round 95 hatte bewusst gegen ein neues RPC für
Wetter entschieden, weil das ein Infrastruktur-Umbau statt Feature-Fix
gewesen wäre. Jetzt, mit expliziter Vorgabe, genau diesen Umbau als
eigenständigen Schritt zu bauen — ohne ihn an einen konkreten Konsumenten
zu koppeln, damit er wiederverwendbar bleibt (Auktionshaus, PvP-/
Achievement-Events, alles was künftig "alle Spieler gleichzeitig" braucht).

**Geändert:**
- `scripts/networking/NetworkBridge.gd` —
  neues Signal `broadcast_event_received(kind, payload)`; neue Fassade
  `get_all_joined_peer_ids() -> Array[int]` auf
  `SessionManager.get_all_slots().keys()`; neuer Sender
  `broadcast_to_all_peers(kind: String, payload: Dictionary)` (gleicher
  Guard wie `send_zone_update_for_peer()`: `_has_peer() and
  multiplayer.is_server()`, überspringt den lokalen Peer, iteriert über
  `get_all_joined_peer_ids()` statt `multiplayer.get_peers()` wegen der
  Boot-Race mit noch nicht gehandshakten Peers); neuer Empfänger
  `_rpc_receive_broadcast_event(kind, payload)`
  (`@rpc("authority", "call_remote", "reliable")`, redundanter
  `is_server()`-Guard analog `_rpc_receive_economy_update()`).
- `docs/adr/042-broadcast-to-all-peers.md` (neu) — volle Optionsabwägung,
  explizite Abgrenzung zu ADR-041 (Wetter bleibt unverändert beim
  deterministischen Wurf), explizite "bewusst nicht Teil dieser Runde"-Liste
  (kein Konsument, kein Late-Join-Sync-Pfad).
- `docs/adr/000-index.md` — neue Zeile.
- `TODO-offene-probleme.md` — Round-96-Eintrag ergänzt; die Auktionshaus-
  Zeile (Round 89) aktualisiert: der dort genannte Blocker ("kein an-alle-
  Peers-Mechanismus") ist behoben, die eigentliche `AuctionHouseService`-
  Verdrahtung bleibt aber ein separater offener Punkt.
- Tests: `tests/unit/test_network_bridge.gd` (+5 — Tier-1-No-Op ohne Peer,
  keine lokale Signal-Emission im Guard-Return-Pfad, leere Peer-Liste ohne
  SessionManager, Peer-Liste spiegelt `register_player_slot()`-Einträge,
  `_rpc_receive_broadcast_event()` emittiert nie auf der Autorität selbst).

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner verfügbar, nur strukturell geprüft (Guard-Reihenfolge,
Signaturen, RPC-Annotation gegen die drei bestehenden `send_*()`/
`_rpc_receive_*()`-Paare abgeglichen), nicht gegen eine echte
Zwei-Peer-Verbindung gelaufen. Kein Integrationstest analog
`test_network_bridge_rpc_guards_two_peer.gd` in dieser Runde — ohne
konkreten `kind`-Anwendungsfall wäre das nur ein reiner Transport-
Rauchtest gewesen; sinnvoller mit dem ersten echten Konsumenten
nachzuholen. Bewusst nicht Teil dieser Runde: kein Konsument
(Auktionshaus-Live-Broadcast, PvP-/Achievement-Events), kein Sync-Pfad für
spät joinende Clients — siehe ADR-042.

**Als Nächstes:** PvP-Events (`player_killed_by_player`) oder
Achievement-Events — beide könnten jetzt wahlweise den bestehenden
Einzel-RPC-Weg oder `broadcast_to_all_peers()` nutzen, je nachdem ob der
Trigger nur den betroffenen Spieler oder alle Spieler betrifft.

## Round 97 — Live-Broadcast-Konsument: `AuctionHouseService` (ADR-035 + ADR-042)

Explizite Vorgabe aus Round 96 ("als nächsten Konsumenten und sync"), mit
Auswahl unter drei Optionen (Auktionshaus/PvP-Events/Achievement-Events) —
Auktionshaus-Live-Updates gewählt: der ursprüngliche in ADR-035 (Round 89)
zurückgestellte Punkt, jetzt möglich durch die in Round 96 gebaute
`broadcast_to_all_peers()`-Infrastruktur.

**Geändert:**
- `scripts/economy/trading/AuctionHouseService.gd` —
  neue private `_broadcast_listings_update()`, aufgerufen am Ende von
  `on_list_item_confirmed()`/`on_buy_confirmed()`/
  `on_cancel_listing_confirmed()` (nach der jeweils bereits bestehenden
  `_send_to()`-Einzel-Bestätigung, NICHT in `_fail()` — fehlgeschlagene
  Aktionen ändern nichts am öffentlichen Zustand). Sendet einen vollen
  `get_all_listings()`-Snapshot im selben `event: "listings_snapshot"`-
  Format, das `request_listings_snapshot()` (Pull-Pfad) bereits nutzt —
  kein zweites Payload-Format, kein zweiter Client-Merge-Pfad nötig.
  `_connect_economy_sync()`/`on_cleanup()` verbinden/trennen jetzt zusätzlich
  `NetworkBridge.broadcast_event_received` mit demselben
  `_on_economy_state_received()`-Handler wie `economy_state_received`
  (identische Signatur, identisches Payload-Format — ein Handler reicht).
- `docs/adr/035-trading.md` — neue Sektion "Umsetzungsstand (Round 97)";
  die Round-89-Randnotiz zum zurückgestellten Broadcast verweist jetzt
  darauf.
- `docs/adr/042-broadcast-to-all-peers.md` — "Bewusst nicht Teil dieser
  Runde" um einen "Update Round 97"-Verweis ergänzt.
- `TODO-offene-probleme.md` — Auktionshaus-Zeile final aktualisiert (Round-
  96-Blocker-Fix + Round-97-Verdrahtung), Round-97-Eintrag ergänzt.
- Tests: `tests/unit/test_auction_house_service.gd` (+5 — `SpyNetworkBridge`
  analog `test_zone_service.gd`s Muster: Broadcast bei Listen/Kaufen/
  Stornieren mit korrektem Snapshot-Inhalt, kein Broadcast bei
  fehlgeschlagenem Kauf, `broadcast_event_received` routet clientseitig
  korrekt in `listings_updated`).

**Sync-Entscheidung:** kein neuer Sync-Baustein für spät joinende Clients
nötig — der bestehende Pull-Pfad (`request_listings_snapshot()`, seit
Round 89) deckt den initialen Zustand beim ersten Öffnen des
Marktplatz-Panels bereits ab, für jeden Client, unabhängig vom
Beitrittszeitpunkt. Der neue Broadcast liefert ausschließlich laufende
Änderungen an Clients mit bereits offenem Panel — exakt die Echtzeit-Lücke,
die Round 89 als "Pull statt Push"-Einschränkung dokumentiert hatte.

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner verfügbar, nur strukturell geprüft (Guard-Reihenfolge,
Payload-Form gegen `request_listings_snapshot()` abgeglichen), nicht gegen
eine echte Zwei-Peer-Verbindung gelaufen. Bewusst nicht Teil dieser Runde:
PvP-/Achievement-Events (weiterhin offen), Rate-Limiting des Broadcasts bei
sehr vielen kurz aufeinanderfolgenden Änderungen (für `MAX_CLIENTS = 8`
unproblematisch, siehe ADR-042 "Negativ/Risiken").

**Als Nächstes:** PvP-Events (`player_killed_by_player`) oder
Achievement-Events — beide offenen `broadcast_to_all_peers()`-Konsumenten
aus Round 96 — oder eines der weiterhin offenen Themen in
TODO-offene-probleme.md.

## Round 98 — Konsument: PvP-Kill-Feed-Broadcast (`player_killed_by_player`)

Explizite Vorgabe ("PvP-/Achievement-Events als weitere mögliche
Konsumenten. Dann mach da weiter"). Vor dem Coden geprüft: PvP-Events hat
einen klaren, bestehenden Einstiegspunkt (`PvPDeathLossService.
apply_death_loss()`, ADR-036); Achievement-Events hat KEINEN — 0 Treffer im
Code für ein Achievement-System überhaupt. Entscheidung: PvP-Events
umsetzen, Achievement-Events explizit als eigenständiges, deutlich
größeres Feature abgrenzen statt es notdürftig an einen nicht-existenten
Trigger zu hängen.

**Geändert:**
- `scripts/entities/combat/CombatEvents.gd` (neu) — EventBus-Namespace
  `combat`, ein Signal `player_killed_by_player(victim_player_id,
  killer_player_id, victim_was_skulled, gold_lost, items_lost_count)`,
  analog `ZoneEvents.gd` (ADR-030).
- `scripts/eventbus/EventBus.gd`/`IEventBus.gd`/`EventBusAdapter.gd`,
  `tests/mocks/MockEventBus.gd` — `combat`/`combat()` nach demselben
  Muster wie die bestehenden acht Namespaces registriert.
- `scripts/entities/combat/PvPDeathLossService.gd` — neue `_bus:
  IEventBus`-Dep (optional); neue `_notify_kill()`, aufgerufen direkt nach
  der bestehenden `death_loss_applied`-Emission in `apply_death_loss()`:
  emittiert `EventBus.combat.player_killed_by_player` lokal auf der
  Autorität (kein RPC-Rundweg, ADR-042-Konvention) UND broadcastet
  `kind == "pvp_kill"` an alle Peers. Neue `_connect_broadcast()`/
  `on_cleanup()`/`_on_broadcast_event_received()` für den Client-Empfang
  — Service hatte bisher gar kein `on_cleanup()`, jetzt nachgezogen (wird
  bereits generisch von `ServiceTeardownManager` aufgerufen, keine
  zusätzliche Registrierung nötig).
- `docs/adr/036-pvp-death-loss.md` — neue Sektion "Umsetzungsstand
  (Round 98)"; `docs/adr/018-systemevents-domain-split.md` und
  `docs/adr/042-broadcast-to-all-peers.md` verweisen jetzt darauf.
- `TODO-offene-probleme.md` — PvP-Events-Checkbox auf erledigt,
  Achievement-Events als eigener offener Punkt mit Begründung, Round-98-
  Eintrag ergänzt.
- Tests: `tests/unit/test_pvp_death_loss_service.gd` (+5 — lokale
  Autoritäts-Emission ohne NetworkBridge, Broadcast-Payload-Form über
  `SpyNetworkBridge`, kein Broadcast beim bestehenden No-Op-Guard,
  `broadcast_event_received`-Routing in `player_killed_by_player`,
  Ignorieren fremder `kind`-Werte). `_bus` (`MockEventBus`) jetzt zusätzlich
  in `_loss.configure()` verdrahtet (vorher unbenutzt im Test-Setup
  vorhanden, aber nicht übergeben).

**Bewusste Abgrenzung `death_loss_applied` vs. `player_killed_by_player`:**
Ersteres bleibt die vollständige autoritative Quelle (volle
`items_lost`-Liste, für Opfer/Killer-eigene UI). Letzteres ist bewusst
schmaler (nur eine Item-Stack-Anzahl) und für ALLE Spieler gedacht — siehe
`CombatEvents.gd`-Klassenkommentar.

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft (Signatur-/Guard-Abgleich gegen
`AuctionHouseService`s Round-97-Dual-Channel-Muster). Kein
UI-Kill-Feed-Panel — reine Signal-Infrastruktur, analog wie
`weather_changed` zunächst auch nur als Signal existierte.

**Als Nächstes:** Achievement-System von Grund auf (eigene Design-Runde:
Datenmodell, Trigger-Punkte, Persistenz, danach ggf. eigener
Broadcast-Konsument), oder eines der weiterhin offenen Themen in
TODO-offene-probleme.md (Chat/Social, Reporting/Moderation, Telemetrie,
Tutorial/Onboarding).

## Round 99 — Chat/Social (ADR-043)

Explizite Vorgabe ("Chat/Social next"). Erstes wirklich grünes Feld dieser
Runden-Serie — 0 Treffer im Code vorher, keine bestehende Service-Instanz
zum Anhängen (anders als Round 97/98, die auf bereits verdrahtete Services
aufsetzten). Dadurch mehr Neuland: neuer Ordner `scripts/social/`, neue
`ServiceDefinition` in `config/BootstrapConfig.tres`, neues dediziertes
RPC-Paar in `NetworkBridge.gd`.

**Geändert:**
- `scripts/social/chat/ChatService.gd` (neu) — zwei Kanäle (`global`,
  `whisper`), Validierung (leer/Whitespace verworfen, 240-Zeichen-Cap,
  Rate-Limit pro Absender), `request_send_message()`/
  `on_send_message_confirmed()` nach dem exakten
  `AuctionHouseService.request_list_item()`-Guard-Muster
  (`_network.has_peer() and not _network.is_server()` — beim ersten
  Entwurf falsch als reines `is_instance_valid(_network)` geschrieben,
  beim Gegenlesen gegen das Auktionshaus-Muster korrigiert, bevor es in
  die Tests eingebaut wurde).
- `scripts/networking/NetworkBridge.gd` — neues dediziertes RPC-Paar:
  `send_chat_message()`/`_rpc_chat_send_message()` (Client→Autorität,
  `any_peer`) und `send_chat_message_for_player()`/
  `_rpc_receive_chat_message()` + Signal `chat_message_received`
  (Autorität→Ziel-Client, `authority`, für `whisper`). `global` läuft über
  das bestehende `broadcast_to_all_peers()` (ADR-042), kein neuer Kanal
  dafür nötig. Neuer `_chat`-Dep in `configure()`, neuer Rate-Limit-Eintrag.
- `scripts/platform/ServiceKeys.gd` — `CHAT`.
- `scripts/platform/BootPipeline.gd` — `ServiceKeys.CHAT` in der
  NetworkBridge-Injektionsliste ergänzt.
- `config/BootstrapConfig.tres` — neue `ServiceDefinition` `Resource_chat`
  (keine Deps), in `session_services` eingehängt, `load_steps` erhöht;
  `network_bridge`s `optional_deps` um `"chat"` ergänzt.
- `docs/adr/043-chat-social.md` (neu), `docs/adr/000-index.md`,
  `docs/adr/018-systemevents-domain-split.md`,
  `docs/adr/042-broadcast-to-all-peers.md` verweisen jetzt darauf.
- `TODO-offene-probleme.md` — Chat/Social-Checkbox erledigt, Round-99-
  Eintrag ergänzt.
- Tests: `tests/unit/test_chat_service.gd` (neu, 19 Tests — Validierung,
  Rate-Limit, Kanal-Routing, `SpyNetworkBridge`-basierte Broadcast-/
  Whisper-Zustellung, Bystander-Privatsphäre-Guard für Whisper,
  Client-Empfangspfade, `on_cleanup()`-Verbindungstrennung).

**Nebenbei gefunden und behoben — echter Bug aus Round 98:**
`PvPDeathLossService.configure()` liest seit Round 98
`ServiceKeys.EVENT_BUS`, aber `config/BootstrapConfig.tres` listete
`event_bus` nie in dessen `optional_deps` — in Produktion wäre `_bus` dort
also immer `null` geblieben, der komplette Kill-Feed-Pfad hätte nie
gefeuert. Die Round-98-Unit-Tests hatten das nicht auffangen können, weil
sie `ServiceDeps.from_dict()` direkt mit dem Key befüllen, unabhängig von
dieser Konfigurationsdatei. Beim Nachbauen der `ChatService`-
`ServiceDefinition` als Vergleichsfall gegen die bestehenden Blöcke
aufgefallen und sofort mitkorrigiert (`config/BootstrapConfig.tres`,
`Resource_pvp_death_loss`).

**Bewusste Architektur-Entscheidung:** `ChatService` bekommt bewusst KEINEN
neuen `EventBus`-Namespace (anders als `CombatEvents` in Round 98) —
eigenes Signal `message_received`/`message_rejected` reicht, analog
`AuctionHouseService.listings_updated`. Begründung: Chat ist ein
in-sich-geschlossenes Feature mit eigenem Service und eigener UI-Anbindung,
kein cross-cutting Signal, das mehrere unabhängige Systeme betrifft (im
Unterschied zu einem PvP-Kill, der potenziell für Quests, Achievements,
Weltereignisse etc. relevant sein könnte).

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft (u. a. `load_steps`-Zähler in der
`.tres`-Datei erhöht, aber nicht gegen eine tatsächliche
Godot-Resource-Ladephase verifiziert — dieses Feld ist in Godot ohnehin nur
ein Lade-Fortschritts-Hinweis, kein harter Validierungswert, aber ohne
Editor lässt sich das nicht abschließend bestätigen). Kein Chat-UI-Panel,
kein Verlauf/Scrollback, keine Moderation — siehe ADR-043 „Bewusst nicht
Teil dieser Runde".

**Als Nächstes:** Achievement-System von Grund auf (eigene Design-Runde),
Reporting/Moderation (jetzt mit Chat als konkretem ersten Zielsystem
sinnvoller als vorher), Telemetrie, oder Tutorial/Onboarding.

## Round 100 — Reporting/Moderation (ADR-044)

Explizite Vorgabe (Vorschlag aus Round 99s "Als Nächstes" bestätigt:
"Fang damit an"). Zwei bewusst getrennte Bausteine statt einem
gemeinsamen "Moderations"-Service — siehe ADR-044 „Entscheidung" für die
volle Begründung (Mute ist lokal+augenblicklich, Meldung ist
autoritativ+persistent, fachlich zwei verschiedene Dinge).

**Geändert:**
- `scripts/social/moderation/ReportService.gd` (neu) — Melder→Autorität-
  Meldungen, feste Grund-Kategorien (`REASON_HARASSMENT`/`SPAM`/
  `CHEATING`/`INAPPROPRIATE_NAME`/`OTHER`), Details-Cap (500 Zeichen),
  Rate-Limit (30s/Melder — bewusst großzügiger als Chats 1s, siehe
  ADR-044). Persistiert (`SAVE_KEY = "reports"`,
  `MAX_STORED_REPORTS = 500`, älteste zuerst verworfen), Save-Interface
  exakt nach `AuraService`-Muster (`get_save_key()`/`get_save_data()`/
  `_restore_from_save()`). `get_reports()`/`get_reports_against()` für
  künftiges Review-Tooling (kein UI in dieser Runde).
- `scripts/social/chat/ChatService.gd` — `mute_player()`/
  `unmute_player()`/`is_muted()` (neu), neue `_emit_if_not_muted()` als
  einziger Ort, an dem `message_received` noch feuert — alle drei
  bisherigen `.emit()`-Stellen (global lokal, whisper lokal, beide
  Netzwerk-Empfangspfade) darauf umgestellt. Rein transient, `on_cleanup()`
  leert die Mute-Liste mit.
- `scripts/networking/NetworkBridge.gd` — neues Client→Autorität-only-
  RPC-Paar `send_report_submit()`/`_rpc_report_submit()` (`any_peer`,
  analog `send_chat_message()`/`_rpc_chat_send_message()`, aber ohne
  Gegenstück für eine Zustellung an andere Spieler — Meldungen sind nie
  für andere Spieler sichtbar). Neuer `_report`-Dep, neuer
  Rate-Limit-Eintrag.
- `scripts/platform/ServiceKeys.gd` — `REPORT`.
- `scripts/platform/BootPipeline.gd` — `ServiceKeys.REPORT` in der
  NetworkBridge-Injektionsliste ergänzt.
- `config/BootstrapConfig.tres` — neue `ServiceDefinition`
  `Resource_report` (`optional_deps = ["savesystem"]`), in
  `session_services` eingehängt, `load_steps` erhöht; `network_bridge`s
  `optional_deps` um `"report"` ergänzt.
- `docs/adr/044-reporting-moderation.md` (neu), `docs/adr/000-index.md`.
- `TODO-offene-probleme.md` — Reporting/Moderation-Checkbox erledigt,
  Round-100-Eintrag ergänzt.
- Tests: `tests/unit/test_report_service.gd` (neu, 16 Tests — Validierung,
  Selbst-Meldung, unbekannter Grund, Details-Cap, Rate-Limit pro Melder,
  `get_reports()`/`get_reports_against()`, Save-Round-Trip, Kapazitäts-
  grenze, Netzwerk-Guard-Pfad via `SpyNetworkBridge`).
  `tests/unit/test_chat_service.gd` (+7 — Mute unterdrückt lokale UND
  beide Netzwerk-Empfangspfade, ist pro-Absender, `unmute_player()`
  stellt Zustellung wieder her, `on_cleanup()` leert die Liste).

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft. Bewusst nicht Teil dieser Runde: kein
Review-/Admin-UI, keine automatischen Konsequenzen (Bans/Kicks/
serverseitige Mutes), kein Wortfilter/Inhalts-Moderation, keine
Mute-Persistenz über Sitzungen hinweg — siehe ADR-044.

**Als Nächstes:** Achievement-System von Grund auf (eigene Design-Runde:
Datenmodell, Trigger-Punkte über mehrere Systeme, Persistenz), Telemetrie,
oder Tutorial/Onboarding.

## Round 101 — Telemetrie/Crash-Reporting (ADR-045)

Explizite Vorgabe, nach kurzer Abwägung dreier offener Themen begründet
empfohlen: Telemetrie/Crash-Reporting vor Achievement-System und Tutorial/
Onboarding, weil (a) es der größte Hebel ist, um die seit Round 89
ungetesteten neuen Systeme abzusichern, und (b) es Backend-/Service-Arbeit
ist, die in dieser Umgebung ohne Godot-Editor zuverlässig geht — im
Unterschied zu Tutorial/Onboarding, das überwiegend UI-Flow wäre.

**Kern-Entscheidung:** beide Hälften bauen auf der bestehenden `AppLogger`-
Infrastruktur auf (Thread-sicheres File-I/O, NDJSON, Ring-Puffer gibt es
seit vielen Runden bereits), statt sie zu duplizieren — siehe ADR-045
„Optionen (verworfen)" für die explizite Begründung gegen ein zweites
File-I/O-System.

**Geändert:**
- `scripts/logger/Logger.gd` — neue `build_crash_report()` (reine
  Dictionary-Konstruktion, kein I/O — bewusst von `write_crash_report()`
  getrennt, analog wie `_to_ndjson()` von der Schreib-Logik getrennt ist)
  und `write_crash_report()` (Datei-I/O, dieselbe Downloads-Ordner-
  Degradationskette wie `_resolve_log_file_path()`/`request_log_export()`).
  `fatal()` ruft `write_crash_report()` jetzt vor dem bestehenden
  synchronen Flush auf. `_notification()` bekommt einen neuen, separaten
  `NOTIFICATION_CRASH`-Zweig dafür — bewusst NICHT im bestehenden
  gemeinsamen Flush-Block (`WM_CLOSE_REQUEST`/`CRASH`/`PREDELETE`), weil
  die anderen beiden normale Beendigungen sind, kein Absturz.
- `scripts/telemetry/TelemetryService.gd` (neu) — `record_event()` als
  dünner Wrapper um `AppLogger.log_trace(..., "Telemetry")`, zusätzlich
  Session-Zähler pro Event-Name (`get_event_counts()`/`get_event_count()`,
  transient). Automatische `session_start`-/`session_end`-Events (letzterer
  mit `duration_sec`), damit die neue Infrastruktur nicht mit null
  tatsächlichen Aufrufern startet.
- `scripts/platform/ServiceKeys.gd` — `TELEMETRY`. Bewusst OHNE Eintrag in
  `BootPipeline.gd`s NetworkBridge-Injektionsliste — `TelemetryService`
  braucht kein Netzwerk (kein Upload-Endpunkt existiert).
- `config/BootstrapConfig.tres` — neue `ServiceDefinition`
  `Resource_telemetry` (keine Deps), in `session_services` eingehängt,
  `load_steps` erhöht.
- `docs/adr/045-telemetry-crash-reporting.md` (neu), `docs/adr/000-index.md`.
- `TODO-offene-probleme.md` — Telemetrie-Checkbox erledigt, Round-101-
  Eintrag ergänzt.
- Tests: `tests/unit/test_telemetry_service.gd` (neu, 9 Tests —
  automatischer `session_start`, Zähl-Logik, leere Namen ignoriert,
  Kopie-statt-Referenz, `on_cleanup()` zeichnet `session_end` auf und
  leert danach). `tests/unit/test_logger_crash_report.gd` (neu, 6 Tests —
  `build_crash_report()`-Inhalt/Schlüssel/Zeitstempel,
  `write_crash_report()` mit echtem Datei-I/O inkl. JSON-Parse-Check und
  Aufräumen danach). **Wichtig:** `fatal()` wird in KEINEM Test
  aufgerufen — es beendet den Prozess über `get_tree().quit(1)`, das hätte
  den gesamten Testlauf abgebrochen.

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft. `write_crash_report()` allerdings mit
echtem Datei-I/O getestet (nicht nur die reine Datenkonstruktion) — die
tatsächlichen Aufrufer (`fatal()`/`NOTIFICATION_CRASH`) selbst konnten aus
naheliegenden Gründen nicht end-to-end ausgelöst werden. Bewusst nicht
Teil dieser Runde: kein Netzwerk-Upload/Server, kein Dashboard/UI, kein
Rate-Limiting für `record_event()` — siehe ADR-045.

**Als Nächstes:** Achievement-System von Grund auf (eigene Design-Runde),
oder Tutorial/Onboarding.

## Round 102 — Achievement-System (ADR-046)

Explizite Vorgabe ("Go ahead bei achievements"). Größter verbleibender
Brocken aus der Round-53-Liste, seit Round 96 wiederholt als "eigene
Design-Runde nötig" zurückgestellt.

**Kern-Entscheidungen (siehe ADR-046 für die volle Begründung):**
- Feste `DEFINITIONS`-Liste statt Resource-/Editor-Workflow — für fünf
  Beispiel-Achievements überdimensioniert.
- Nur drei Trigger-Quellen, alle bewusst geprüft: sie müssen NACHWEISLICH
  nur auf der Autorität feuern, sonst wäre Fortschritt Multiplayer-
  inkonsistent. `PvPDeathLossService.death_loss_applied`,
  `AuctionHouseService.listing_created`, `ReportService.report_submitted`
  qualifizieren sich (alle hinter `_require_authority()`-Guards). Bewusst
  NICHT `ChatService.message_received` — feuert auf jedem Client, auch
  Empfängern, wäre also Multiplayer-inkonsistent als Trigger-Quelle.
- Keine Belohnungen beim Freischalten — eigenständige Design-Entscheidung,
  nicht Teil der Infrastruktur-Runde.

**Geändert:**
- `scripts/progression/achievements/AchievementService.gd` (neu) —
  `DEFINITIONS` (5 Einträge), `grant_progress()`/`_unlock()` (autoritäts-
  gated), Signale `achievement_unlocked`/`achievement_progress`,
  `get_progress()`/`get_unlocked()`/`is_unlocked()`/`get_definition()`/
  `get_all_definitions()` (statisch). `configure()` verbindet sich direkt
  mit den drei injizierten Quell-Services' Signalen; `on_cleanup()` trennt
  sie wieder. Save-Interface exakt nach `AuraService`/`ReportService`-
  Muster.
- `scripts/networking/NetworkBridge.gd` — neues RPC-Paar
  `send_achievement_unlocked_for_player()`/
  `_rpc_receive_achievement_unlocked()` + Signal
  `achievement_unlocked_received` (Autorität→Ziel-Spieler, analog
  `send_chat_message_for_player()`). Bewusst OHNE Tier-1-Fallback-Zweig
  und OHNE `_achievement`-Rückreferenz — kein Client-Request löst
  Achievements aus.
- `scripts/platform/ServiceKeys.gd` — `ACHIEVEMENT`.
- `scripts/platform/BootPipeline.gd` — `ServiceKeys.ACHIEVEMENT` in der
  NetworkBridge-Injektionsliste ergänzt.
- `config/BootstrapConfig.tres` — neue `ServiceDefinition`
  `Resource_achievement` (`optional_deps = ["pvp_death_loss",
  "auction_house", "report", "savesystem", "telemetry"]`, bewusst OHNE
  `"network_bridge"`, exakt wie bei chat/report/pvp_death_loss), in
  `session_services` eingehängt, `load_steps` erhöht. Reihenfolge in der
  Datei irrelevant — der `ServiceDependencyResolver` (Kahn's Algorithmus
  über `all_deps()`, required+optional zusammen) sortiert automatisch
  korrekt.
- `docs/adr/046-achievement-system.md` (neu), `docs/adr/000-index.md`.
- `TODO-offene-probleme.md` — Achievement-Events-Checkbox erledigt,
  Round-102-Eintrag ergänzt.
- Tests: `tests/unit/test_achievement_service.gd` (neu, 19 Tests).
  Testmuster: unkonfigurierte ECHTE Instanzen von `PvPDeathLossService`/
  `AuctionHouseService`/`ReportService` werden injiziert, deren Signale
  direkt manuell emittiert, um zu prüfen, dass `AchievementService`
  korrekt reagiert.

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft. Bewusst nicht Teil dieser Runde: kein
Resource-/Editor-Workflow, keine Belohnungen, kein Snapshot-/Sync-Pfad für
spät joinende Clients, kein UI-Panel — siehe ADR-046.

Damit sind alle vier zuletzt offenen TODO-Themen (Chat/Social, Reporting/
Moderation, Telemetrie/Crash-Reporting, Achievement-Events) umgesetzt.

**Als Nächstes:** Tutorial/Onboarding (letztes verbliebenes Thema aus der
Round-53-Liste), oder eine kleinere Folge-Runde (neues Achievement/neue
Trigger-Quelle, Achievement-Snapshot-Sync für spät joinende Clients).

## Round 103 — Statistiken (ADR-047) + Achievement-Erweiterung (ADR-046 Round 103)

Explizite Vorgabe: stat-basierte Achievements (Meter gelaufen/gesprungen/
gefallen, NPCs getötet) — mit korrekter Vorab-Einschätzung des Nutzers,
dass dafür erst ein Statistik-System nötig ist — PLUS alle vier in Round
102 offen gelassenen Punkte (Editor-Workflow, Belohnungen, Sync-Pfad,
UI-Panel), explizit als "das auch noch machen" benannt.

**Größte Einzel-Entscheidung dieser Runde:** wo Bewegungs-Tracking
ansetzt. Das Projekt nutzt server-autoritative Bewegung mit Client-
Prediction (ADR-025/026) — die Autorität hat durch Input-Replay eine echte
Position, kein Client-Trust-Problem. `_track_movement_stats()` wurde
deshalb bewusst NUR in `Player.gd._loop_free_authoritative()` eingehängt,
nie in den Prediction-/Resimulation-Zweigen — rein additiv (neue Felder,
ein neuer Funktionsaufruf, keine Änderung an bestehender Physik-/
Reconciliation-Logik), aber `Player.gd` ist die reconciliation-
kritischste Datei im Projekt und dieser Eingriff ließ sich ohne Godot-
Editor nicht gegen echte Physik verifizieren — offen als größtes
verbleibendes Risiko dieser gesamten Session festgehalten (siehe ADR-047
"Risikobewertung"/"Ehrlich offen").

**Geändert (Auswahl, Details in ADR-047 und ADR-046 „Umsetzungsstand
(Round 103)"):**
- `scripts/progression/stats/StatsService.gd` (neu) — kumulative Stats,
  zwei autoritative Quell-Signale (`enemy_killed`, neu
  `movement_stats_batch`), Signal `stat_changed` als vierte
  Achievement-Trigger-Quelle.
- `scripts/entities/player/Player.gd` — additive Stat-Akkumulation +
  gebündelter 5-Sekunden-Flush (kein Pro-Tick-Signal-Spam).
  `scripts/entities/player/PlayerEvents.gd` — neues Signal.
- `scripts/progression/achievements/AchievementService.gd` — komplett
  überarbeitet: `float` statt `int` für Fortschritt, vierte Trigger-Quelle,
  vier neue Achievements, Gold-Belohnungen (`CurrencyService` direkt, NICHT
  `RewardDispatcher` — quest-spezifisch gekoppelt), Snapshot-Sync
  (`request_snapshot()`, neues RPC-Paar), datengetriebene Definitionen.
- `scripts/progression/achievements/AchievementDefinition.gd` (neu),
  `data/achievements/*.tres` (9), `DataManifest.ACHIEVEMENTS`,
  `DataService._load_achievements()`/`get_achievement()`/
  `get_all_achievements()` — exakt das Quest/Item/Skill-Muster.
- `scripts/networking/NetworkBridge.gd` — neues Snapshot-RPC-Paar,
  `network_bridge`s eigene `optional_deps` bekommt jetzt doch
  `"achievement"` (Round 102 hatte das bewusst ausgelassen — der neue
  Snapshot-Pfad braucht die Rückreferenz).
- `ServiceKeys.STATS`, `BootPipeline`-Injektionsliste,
  `config/BootstrapConfig.tres` (neue `Resource_stats`, `achievement`s
  Deps um `stats`/`currency`/`data` erweitert).
- `docs/adr/047-statistics.md` (neu), `docs/adr/046-achievement-system.md`
  (Round-103-Abschnitt), `docs/adr/000-index.md`.
- Tests: `tests/unit/test_achievement_service.gd` (+14),
  `tests/unit/test_stats_service.gd` (neu, 16 Tests).

**Bewusst NICHT umgesetzt: UI-Panel.** Ausdrücklich als höchstes Risiko
eingeschätzt und deshalb übersprungen — ein `.tscn` blind zu bauen, ohne
es im Editor öffnen/verifizieren zu können, ist der Bereich, in dem am
ehesten etwas unbemerkt kaputt geht. Alle Backend-Signale für ein
künftiges Panel sind vorhanden (`achievement_unlocked`,
`achievement_progress`, `stat_changed`).

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft. Der `Player.gd`-Eingriff ist davon am
stärksten betroffen — dringend empfohlen, ihn vor jeder weiteren
Bewegungs-Feature-Arbeit im echten Editor zu testen (Sprünge, Stürze,
Reconciliation unter Latenz).

**Als Nächstes:** Tutorial/Onboarding, oder — dringender — den
`Player.gd`-Eingriff aus dieser Runde im Editor verifizieren.

## Round 104 — Achievement-UI-Panel (ADR-046)

Explizite Vorgabe ("nächstes UI von Achievement vor Tutorial/Onboarding").
Round 103 hatte das Panel bewusst zurückgestellt, mit der Begründung, ein
blind gebautes `.tscn` sei das höchste Risiko im ganzen System — dieses
Risiko gilt nicht für den programmatischen Panel-Weg, den das Projekt
bereits für Skill/Quest/Shop/Bank/Trade/Auktionshaus nutzt (reine
GDScript-Node-Konstruktion, kein Editor-Scene-File). Das Achievement-Panel
folgt exakt diesem Muster — kein neues Risiko eingegangen.

**Geändert:**
- `scripts/progression/achievements/ui/AchievementPanelVisuals.gd` (neu),
  `AchievementPanelController.gd` (neu, analog SkillPanelController),
  `AchievementPanelComponent.gd` (neu) — Toggle 🏆 bei Offset 304–384
  (nächster freier Slot), Kategorien-Sektionen, Fortschrittsbalken +
  Gold-Anzeige, gesperrt/freigeschaltet visuell unterschieden, Unlock-Toast
  über bestehenden `NotificationController`.
- `scripts/ui/HUDBuilder.gd` — `achievement_panel` registriert.
- `scripts/platform/interfaces/IUIContext.gd` / `UIContext.gd` — neuer
  Getter `get_achievement_service()`.

**Unerwarteter Fund, sofort mitgefixt:** `NetworkBridge.
achievement_unlocked_received`/`achievement_snapshot_received` (Round 103)
hatten nie einen Listener — ohne Fix wäre das Panel auf jedem
Nicht-Host-Client dauerhaft leer geblieben. `AchievementService.gd`:
neue `_on_remote_unlock_received()`/`_on_remote_snapshot_received()` +
neues Signal `achievements_synced(player_id)`, verbunden über
`_connect_network_receive()` (in `configure()` UND
`inject_network_bridge()`, analog `AuctionHouseService.
_connect_economy_sync()`). Neuer optionaler Dep `session_manager` für
`_local_player_id()` auf dem Client; `config/BootstrapConfig.tres`
entsprechend ergänzt (`Resource_achievement.optional_deps`).
Details: `docs/adr/046-achievement-system.md` „Umsetzungsstand (Round 104)".

**Tests:** `tests/unit/test_achievement_service.gd` (+10, Client-Empfang),
`tests/unit/test_achievement_panel_controller.gd` (neu, 9 Tests).

**Ehrlich offen:** wie immer — kein Godot-Editor/Headless-Runner
verfügbar, nur strukturell geprüft (Node-Konstruktion gegen das exakte
SkillPanelVisuals/QuestPanelVisuals-Muster abgeglichen, kein visueller
Vergleich möglich). Bewusst nicht Teil dieser Runde: kein `hidden`-Flag,
keine Kategorien-Filter/Sortierung im Panel, kein Kill-Feed für fremde
Unlocks.

**Als Nächstes:** Tutorial/Onboarding (letztes offenes Thema aus der
Round-53-Liste), oder — weiterhin unverändert dringend — den
`Player.gd`-Bewegungs-Tracking-Eingriff aus Round 103 im Editor
verifizieren.

## Round 105 — Charaktererstellung (ADR-048, Tutorial-Teil 1 von 2)

Explizite Vorgabe: Fragenreihe ähnlich Animal Crossing bestimmt Aussehen +
Charakterzüge, danach Spawn in der Welt + erklärender NPC. Diese Runde
deckt nur den ersten Teil ab (Fragenreihe → Aussehen), der NPC ist
bewusst eine eigene Folgerunde. Vor der Umsetzung drei Architekturfragen
geklärt (Chat 2026-08): Charakterzüge vorerst rein kosmetisch (Flavor/
Stat-Boni als Spike vorgemerkt), Aussehen wird aus den Antworten
abgeleitet statt direkt gewählt (vier Presets, Feintuning vertagt),
überspringbar mit je einem Achievement für Abschluss ODER Überspringen.

**Geändert:**
- `scripts/onboarding/CharacterCreationService.gd` (neu) — 4 Fragen × 4
  Optionen, Mehrheitsentscheid über vier Aussehens-Archetypen (sonnig/
  wald/flut/asche), `submit_answers()`/`skip_creation()` autoritäts-
  gated, Persistenz analog `StatsService`.
- `scripts/onboarding/ui/CharacterCreationVisuals.gd`/`Controller.gd`/
  `Component.gd` (neu) — Vollbild-Overlay (kein `.tscn`), registriert in
  `HUDBuilder.gd`. Zeigt sich nur, wenn `has_seen_creation()` false ist.
- `scripts/entities/player/PlayerVisuals.gd` — neue, additive
  `apply_appearance(color)`.
- `scripts/progression/achievements/AchievementService.gd` — zwei neue
  Definitionen (`character_creator_complete`/`character_creator_skipped`),
  fünfte/sechste Trigger-Quelle, entkoppelt verdrahtet (Service kennt
  `CharacterCreationService` nicht, nur umgekehrt).
- `scripts/platform/interfaces/IUIContext.gd`/`UIContext.gd` — neuer
  Getter `get_character_creation_service()`.
- `config/BootstrapConfig.tres` — neuer Service `character_creation`
  registriert, `achievement` um den Dep ergänzt.

Details: `docs/adr/048-character-creation.md`.

**Tests:** `tests/unit/test_character_creation_service.gd` (neu, 18),
`tests/unit/test_character_creation_controller.gd` (neu, 13),
`tests/unit/test_player_visuals.gd` (neu, 2), `tests/unit/
test_achievement_service.gd` (+5, neue Trigger-Quelle).

**Ehrlich offen:** wie immer kein Godot-Editor verfügbar. Die
Aussehen-Anwendung auf einen echten `Player`-Node
(`ctx.get_local_player()` → `PlayerVisuals.apply_appearance()`) ist NICHT
gegen einen echten spawnenden Player getestet — dafür bräuchte es einen
vollständigen `CharacterBody3D`-Aufbau im Test, was selbst ein
ungetesteter Pfad wäre. Funktioniert strukturell (Signatur/Typen stimmen,
`is_instance_valid()`-Guards überall), aber die tatsächliche Boot-
Reihenfolge (spawnt der Player vor oder nach dem HUD-Build?) ist nicht
verifiziert — siehe ADR-048 "Bekannte, unverifizierte Lücke".

**Als Nächstes:** Tutorial-Teil 2 (NPC erklärt UI/UX nach dem Spawn),
oder das spielerbefüllte Wiki (siehe `TODO-offene-probleme.md`), oder
weiterhin der `Player.gd`-Bewegungs-Tracking-Eingriff aus Round 103 im
Editor.

## Round 106 — Charaktererstellung: Multiplayer-RPC-Pfad + Tutorial-Teil 2 (ADR-048)

Schließt die in Round 105 offen gelassene Lücke: ein Nicht-Host-Client
konnte die Fragenreihe zwar sehen und ausfüllen, aber `submit_answers()`/
`skip_creation()` liefen hinter `_require_authority()` ins Leere —
identischer Kompromiss wie `AchievementService` in Round 102, hier nach
demselben Muster nachgezogen wie dort in Round 103/104.

**Geändert:**
- `scripts/onboarding/CharacterCreationService.gd` —
  `submit_answers()`/`skip_creation()` → `on_submit_answers_confirmed()`/
  `on_skip_creation_confirmed()` (reiner Autoritäts-Pfad, unverändertes
  Verhalten). Neu: `request_submit_answers()`/`request_skip_creation()`
  als Client-Einstiegspunkte (Muster: `ReportService.
  request_submit_report()`). Neuer Rückkanal — anders als bei
  `ReportService` (Einbahnstraße) braucht der anfragende Client sein
  eigenes Ergebnis zurück: `_on_remote_creation_completed_received()`/
  `_skipped_received()`, neues Signal `character_creation_confirmed`.
  Neuer optionaler Dep `session_manager`.
- `scripts/networking/NetworkBridge.gd` — zwei neue Request-RPCs
  (`_rpc_character_creation_submit_answers`/`_skip`), zwei neue
  Rückkanal-RPCs (`_rpc_receive_character_creation_completed`/
  `_skipped`), passende `send_*()`-Funktionen (Client→Autorität UND
  gezielt Autorität→Spieler, analog `send_report_submit()`/
  `send_achievement_unlocked_for_player()`), Rate-Limits ergänzt.
- `config/BootstrapConfig.tres` — **Dependency-Zyklus vermieden:**
  `character_creation` bezog `network_bridge` bisher direkt über
  `configure()`-Deps; da `network_bridge` jetzt umgekehrt optional
  `character_creation` braucht, wäre das ein echter Zyklus im
  `ServiceDependencyResolver` gewesen. `character_creation` bezieht
  `NetworkBridge` jetzt stattdessen über `inject_network_bridge()` in
  Phase C8 — exakt das Muster von `achievement`/`report`/`chat`.
  `character_creation.optional_deps` um `session_manager` ergänzt,
  `network_bridge.optional_deps` um `character_creation` ergänzt.
- `scripts/platform/BootPipeline.gd` — `ServiceKeys.CHARACTER_CREATION`
  in die Phase-C8-Late-Inject-Liste aufgenommen.
- `scripts/onboarding/ui/CharacterCreationController.gd` — ruft jetzt
  `request_submit_answers()`/`request_skip_creation()` auf, "fertig"-
  Logik (Aussehen anwenden, Panel schließen, Toast) hängt jetzt am neuen
  `character_creation_confirmed`-Signal statt synchron direkt nach dem
  Service-Aufruf zu laufen — deckt damit auch den asynchronen
  Nicht-Host-Client-Pfad ab, ohne den synchronen Tier-1/Host-Pfad zu
  ändern (GDScript-Signale feuern synchron).

Details: `docs/adr/048-character-creation.md` „Round 106: Multiplayer-
RPC-Pfad".

**Tests:** `tests/unit/test_character_creation_service.gd` (+10 —
Netzwerk-Pfad via `SpyNetworkBridge`, Autoritäts-Guard für beide
`on_*_confirmed()`, gezielte Rückkanal-Zustellung,
`character_creation_confirmed`-Emission, Client-Empfang via
`StubSessionManager`). `tests/unit/test_character_creation_controller.gd`
(+2 — player_id-Filter auf `character_creation_confirmed`). Bestehende
Tests umbenannt (`submit_answers`/`skip_creation` →
`request_submit_answers`/`request_skip_creation`), Assertions
unverändert.

**Ehrlich offen:** wie immer kein Godot-Editor/Headless-Runner verfügbar.
Der Rückkanal selbst ist nur strukturell gegen die Spy-/Stub-Doubles
geprüft, nicht gegen einen echten Zwei-Peer-RPC-Roundtrip (siehe
`tests/integration/test_network_bridge_rpc_guards_two_peer.gd` — dort ist
`character_creation` noch nicht ergänzt, wäre ein sauberer nächster
Schritt für echte Integrationsabdeckung). Weiterhin bewusst nicht Teil
dieser Runde: kein Broadcast des Aussehens an andere Peers (siehe
ADR-048).

### Teil 2: Tutorial-Guide-NPC

Schließt den zweiten, in Round 105 bewusst vertagten Teil der
ursprünglichen ADR-048-Vorgabe ("...danach Spawn in der Welt + erklärender
NPC"). Exakt das etablierte NPC-Koordinator-Muster
(`QuestNPC`/`ShopNPC`/`BankNPC`/`AuctionHouseNPC`), bewusst die
schlankeste Variante der fünf, weil hier weder Quest-Bus-Zugriff noch ein
Panel-Open-Event noch `NetworkBridge` gebraucht wird — nur lokal
angezeigter Text.

**Geändert:**
- `scripts/onboarding/TutorialGuideNPC.gd` (neu) — Koordinator, delegiert
  Visuals an `NPCVisualBuilder` (identisches Aussehen wie alle anderen
  NPCs), Interaktion über `InteractableComponent`
  (`talk_tutorial_guide`), Dialog-Logik an `TutorialGuideDialogController`.
  Kein `NetworkBridge`-Dep, kein Autoritäts-Guard in `_on_interacted()`
  (anders als `QuestNPC`s BUG-26-Fix) — es gibt hier nichts serverseitig
  zu Trackendes.
- `scripts/onboarding/ui/TutorialGuideDialogController.gd` (neu) — sieben
  UI/UX-Tipps (Bewegung, Interaktion, Inventar, Skills, Quests,
  Errungenschaften, übrige NPCs), ein Tipp pro Gespräch, danach von vorn.
  Bewusst als generische UI-Panel-Beschreibung formuliert statt als
  Tastenkombination — das Spiel steuert sich über Joystick + Touch-Buttons
  (`HUDBuilder.gd`), keine dokumentierte Tastatur-Belegung im Projekt.
  Bus-Integration (`_show_dialog()`) 1:1 aus `QuestNPCDialogController`
  übernommen (Label3D + Timeout + `emit_interaction_reward_text()`).
- `scripts/world/core/WorldEntityRegistry.gd` — neuer Entity-Typ
  `tutorial_guide_npc`.
- `scripts/world/core/WorldSpawner.gd` — Spawn-Aufruf bei
  `Vector3(-3.0, ..., 3.0)`, bewusst näher am Player-Spawnpunkt (0,0,0)
  als die vier bestehenden NPCs auf der "Handelsstraße" (x=8..20) — der
  Guide soll das Erste sein, was ein frisch gespawnter Spieler sieht.

Details: `docs/adr/048-character-creation.md` „Round 106: Tutorial-Teil 2".

**Tests:** `tests/unit/test_tutorial_guide_dialog_controller.gd` (neu, 10
— Tipp-Reihenfolge, Abschlusszeile, Reset auf Tipp 1, Bus-Integration,
identisches Setup wie `test_quest_npc_dialog_controller.gd`).
`tests/unit/test_world_spawner.gd` (+2 — `tutorial_guide_npc` im
Tier-3-Pfad und gebündelt mit den übrigen vier NPCs im normalen
Spawn-Pfad). Kein eigener Koordinator-Test für `TutorialGuideNPC` selbst
— identisches Muster wie `BankNPC`/`ShopNPC`/`AuctionHouseNPC` (auch die
haben keinen), die interessante Logik steckt im eigenständig getesteten
Dialog-Controller.

**Ehrlich offen:** wie immer kein Godot-Editor verfügbar — Platzierung,
Kollision und Sichtbarkeit relativ zum Player-Spawnpunkt sind nur über die
Koordinaten-Logik geprüft (`WorldSpawner`-Tests), nicht visuell. Bewusst
nicht Teil dieser Runde: kein automatisches Ansprechen des Spielers direkt
nach dem Spawn, kein Fortschritts-Tracking pro Spieler — siehe
`TutorialGuideNPC.gd`-Klassenkommentar.

**Als Nächstes:** Tutorial-/Onboarding-Struktur ist damit vollständig
(ADR-048, Teil 1 + 2). Offene Themen laut `TODO-offene-probleme.md`: das
spielerbefüllte Wiki, der `Player.gd`-Bewegungs-Tracking-Eingriff aus
Round 103 im Editor, oder der Zwei-Peer-Integrationstest für
`character_creation` (siehe "Ehrlich offen" oben).

## Round 107 — Spielerbefülltes Wiki: Grundgerüst (ADR-049)

Scoping-Antworten aus Round 106 umgesetzt: pro Spieler lokal, automatisch
aus vorhandenen autoritativen Quellen abgeleitet UND an tatsächliche
Entdeckung gekoppelt, alle vier Kategorien (Gegner, Drop-Rates, Skills,
Quests) in dieser Runde. Bewusst nach demselben Zwei-Runden-Schnitt wie
Achievement (Round 102/103 Grundgerüst → Round 104 Panel): diese Runde
liefert Service + Trigger + Netzwerk + Persistenz + Tests, das UI-Panel
folgt als eigene Runde.

**Geändert:**
- `scripts/progression/wiki/WikiService.gd` (neu) — `discover()`/
  `is_discovered()`/`get_discovered()`/`get_all_discovered()` pro Spieler,
  `get_entry_details()`/`get_drop_chances()` als reine Lese-Fassade über
  `DataService`. Drei Trigger-Quellen: `EventBus.world().enemy_killed`
  (Gegner + Drop-Tabelle über `ENEMY_LOOT_TABLE_MAP`-Fallback),
  `EventBus.quest().quest_started_for_player` (neu), `SkillSystem.
  skill_changed` (bestehend). Autorität entscheidet (`_require_authority()`),
  gezielte RPC-Zustellung an den betroffenen Spieler, Snapshot-Sync
  (`request_snapshot()`/`on_snapshot_requested()`), Save-Interface
  (`SAVE_KEY = "wiki"`) — durchgehend das `AchievementService`-Muster.
- `scripts/progression/quests/QuestEvents.gd`/`QuestService.gd` — neues
  Signal `quest_started_for_player(player_id, quest_id)`, additiv neben
  dem bestehenden `quest_started(quest_id)` (das bleibt unverändert,
  `QuestPanelController` fasst es nicht an), emittiert an derselben
  Stelle in `on_quest_start_confirmed()`.
- `scripts/networking/NetworkBridge.gd` — `send_wiki_entry_discovered_
  for_player()`/`send_wiki_snapshot_request()`/`send_wiki_snapshot_
  for_player()` + `_rpc_wiki_snapshot_request`/`_rpc_receive_wiki_entry_
  discovered`/`_rpc_receive_wiki_snapshot`, neuer `_wiki`-Dep,
  Rate-Limit-Eintrag für die Snapshot-Anfrage.
- `scripts/platform/ServiceKeys.gd` — `WIKI`.
- `scripts/platform/BootPipeline.gd` — `WIKI` in der Phase-C8-
  Late-Injection-Liste für `inject_network_bridge()`.
- `config/BootstrapConfig.tres` — `Resource_wiki` registriert
  (`optional_deps`: `event_bus`, `skill_system`, `data`, `savesystem`,
  `session_manager`), `wiki` zu `network_bridge`s `optional_deps` ergänzt
  (Tier-1-Fallback-Zweig von `send_wiki_snapshot_request()`).

Details: `docs/adr/049-player-wiki.md`.

**Tests:** `tests/unit/test_wiki_service.gd` (neu, 30 — `discover()`/
Idempotenz/Per-Spieler-Isolation, alle drei Trigger-Quellen inkl.
Fallback-Loot-Tabellen-Namenskonvention, `on_cleanup()` trennt alle
Signale, `get_entry_details()`/`get_drop_chances()` für alle vier
Kategorien, Snapshot-Sync, Client-Empfang via `StubSessionManager`,
Save-Round-Trip).

**Ehrlich offen:** wie immer kein Godot-Editor/Headless-Runner verfügbar,
nur strukturell geprüft. Der RPC-Rückkanal ist nur gegen
`SpyNetworkBridge`/`MockEventBus` geprüft, nicht gegen einen echten
Zwei-Peer-Roundtrip. Bewusst nicht Teil dieser Runde: kein UI-Panel
(`get_entry_details()` ist aber bereits vollständig dafür nutzbar), keine
echte `EnemyDefinition`-Ressource (`ENEMY_LOOT_TABLE_MAP`-Fallback
stattdessen), kein Telemetrie-Event.

**Als Nächstes:** Wiki-UI-Panel (analog Achievement Round 104 — Toggle-
Button, Kategorien-Sektionen, gesperrt/entdeckt visuell unterschieden),
oder weiterhin offen: `Player.gd`-Bewegungs-Tracking-Eingriff aus Round
103 im Editor verifizieren, Zwei-Peer-Integrationstest für
`character_creation` nachziehen.

## Round 108 — Wiki-UI-Panel (ADR-049)

Schließt Round 107s zurückgestelltes UI-Panel — derselbe Zwei-Runden-
Schnitt wie bei Achievement (Round 102/103 → 104).

**Geändert:**
- `scripts/progression/wiki/ui/WikiPanelVisuals.gd` (neu),
  `WikiPanelController.gd` (neu, analog `AchievementPanelController`),
  `WikiPanelComponent.gd` (neu) — Toggle 📖 bei Offset 400–480 (nächster
  freier Slot nach Skill/Quest/Achievement), Kategorien-Sektionen
  (Gegner/Beute/Fertigkeiten/Quests), unentdeckte Einträge als
  "🔒 ???"-Platzhalter (Name/Beschreibung/Werte bleiben verborgen bis
  `is_discovered()`), Entdeckungs-Toast über bestehenden
  `NotificationController`.
- `scripts/ui/HUDBuilder.gd` — `wiki_panel` registriert.
- `scripts/platform/interfaces/IUIContext.gd`/`UIContext.gd` — neuer
  Getter `get_wiki_service()`.
- `scripts/persistence/DataService.gd` — `get_all_loot_tables()` (neu,
  analog den bestehenden `get_all_*()`-Methoden), für die
  Katalog-Enumeration der "drops"-Kategorie.

**Design-Entscheidung — Katalog vs. entdeckte Einträge:** `WikiService`
kennt nur entdeckte Einträge, keinen vollständigen Katalog (bewusst, siehe
ADR-049). Der Controller baut den Katalog stattdessen selbst aus
`DataService` — dieselben Daten liegen dem Client ohnehin bereits vor,
kein zusätzliches Leck. Unentdeckte Zeilen zeigen nur "???", nicht aber
gar keine Zeile — vollständige Verschleierung der Zeilen-Existenz wäre ein
größerer Umbau (serverseitig gefilterter Katalog + RPC-Neubefüllung pro
Entdeckung) gewesen, für ein reines Info-Wiki ohne Wettbewerbs-Charakter
nicht den Aufwand wert. Details: `docs/adr/049-player-wiki.md` "Round 108:
UI-Panel".

**Tests:** `tests/unit/test_wiki_panel_controller.gd` (neu, 8 — Signal-
Verdrahtung, Katalog-Vorbefüllung locked-by-default, Entdeckung für
lokalen/fremden Spieler, Toast, `wiki_synced`-Vollrefresh für lokalen/
fremden Spieler).

**Ehrlich offen:** wie immer kein Godot-Editor/Headless-Runner verfügbar,
nur strukturell geprüft (Node-Konstruktion gegen das exakte
`AchievementPanelVisuals`-Muster abgeglichen, kein visueller Vergleich
möglich). Bewusst nicht Teil dieser Runde: kein `hidden`-Flag, keine
Kategorien-Filter/Sortierung im Panel.

**Als Nächstes:** `Player.gd`-Bewegungs-Tracking-Eingriff aus Round 103 im
Editor verifizieren, Zwei-Peer-Integrationstest für `character_creation`/
`wiki` nachziehen — beides seit mehreren Runden aufgeschobene, rein
strukturell geprüfte Punkte ohne neue funktionale Abhängigkeiten.

## Round 109 — Tiefer graben: Schächte, Leitern, Erz-/Edelstein-Funde

**Wunsch:** deutlich tiefer als 4 m graben, Leitern zum Hochkommen (steile Wände ok), beim Graben
sichtbar Erze/Edelsteine finden.

**Geändert:**
- `TerrainEditLayer`: `MAX_DELTA_DOWN` −4 → −30; `falloff()`/`apply_brush()` mit optionalem
  `core_radius` (flacher Kern). `WorldTerrainEditor`: Pinsel auf Gitterpunkt gesnappt, `CORE_RADIUS`
  2,9 / `BRUSH_RADIUS` 5 (vorher reiner Glockenpinsel 3,5 — tiefe Löcher wurden Trichter mit
  unbetretbarer Spitze). `edit()` liefert zusätzlich `center`.
- Neu: `LadderPath`, `LadderRegistry`, `LadderPlanner`, `DigFindTable`, `DigFindRegistry`,
  `WorldDigHandler` (scripts/world/terrain/), `Ladder`, `DigFind` (scripts/world/objects/),
  `PlayerLadder` (scripts/entities/player/).
- `WorldService`: `request_ladder_place/remove`, `remove_dig_find`, `get_ladder_registry`,
  `_after_terrain_edit`, gemeinsame Chunk-Callbacks. `WorldEvents`: `ladder_place_requested`,
  `ladder_remove_requested`. `WorldData`/`WorldSaveHandler`: Keys `ladders`, `dig_finds`.
- `Player._apply_movement`: Leiter hat Vorrang. UI: dritter Button „Leiter“. 8 neue Items,
  `DataManifest`, `ShopService.BUY_CATALOG["ladder"] = 10`, `InteractableComponent.refresh_label()`.
- Tests: `test_ladder_planner.gd`, `test_dig_finds.gd` (neu), Ergänzungen in
  `test_terrain_edit_layer.gd`, `test_world_build_handler.gd`, `test_build_ui_logic.gd`,
  `test_world_save_handler.gd`.

**Ehrlich offen:** kein Godot-Editor verfügbar — nur strukturell geprüft (Syntax-Checker,
Planner-Geometrie in Python nachgerechnet), GUT-Tests nicht gelaufen. Nicht am Gerät geprüft:
Klettergefühl, Ansicht/Größe der Funde, Button-Layout (3 Buttons). Wasser: Schächte tiefer als der
globale Wasserspiegel (y=0) laufen weiter voll (bisherige Regel); ggf. eigene Entscheidung nötig.

## Round 110 — Integration Bau ↔ Schmieden

**Wunsch:** "Bau/Schmieden weiter ausbauen, bisher keine wirkliche Integration."
**Befund:** Rezepte/Skill/Events/Items existierten, aber kein `SmithingService`, keine Stations-Bauteile,
kein Panel, kein RPC; Baukosten nutzten Roherz.
**Gebaut:** `SmithingService` (+Stations-Zugang), `BuildPieceDefinition.station_kind`/`PropShape.FURNACE/ANVIL`,
`BuildPiece` "use_station", Panel (`economy/crafting/ui`), `NetworkBridge._rpc_smithing_craft`,
`BootstrapConfig`/`BootPipeline`/`UIContext`/`HUDBuilder`, `Furnace/Anvil/Smithy.tres`, Baukosten Erz→Barren,
`MockEventBus.smithing()`. Details: `docs/smithing-and-crafting.md`.
**Tests (geschrieben, nicht gelaufen):** `test_smithing_service.gd`, `test_smithing_content.gd`, Ergänzungen `test_build_system.gd`.
**Ehrlich offen:** kein Godot — nur Syntax-Check. `SmithingUIController` ungetestet, services.md nicht aktualisiert.
