# WildGrove — Test-Suite

## Ausführung

### Unit-Tests (headless, für CI)
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit
```

### Integration-Test (braucht laufende Szene)
```bash
# In Godot Editor: Scene öffnen, IntegrationTest.gd als Script-Run
```

## Dateien

### Unit-Tests (`tests/unit/`)

| Datei | Getestetes System | Schwerpunkt |
|-------|------------------|-------------|
| `test_biome_registry.gd` | BiomeRegistry | Biom-Definitionen |
| `test_combat_system.gd` | CombatSystem | Schadensberechnung, Krit, Status-Effekte |
| `test_enemy_npc_pool_reuse.gd` | EnemyNPC | Pool-Reuse |
| `test_entity_context.gd` | EntityContext | Service-Zugriff |
| `test_equipment_service.gd` | EquipmentService | Equip/Unequip, Round-Trip (A-01 Fix) |
| `test_equipment_ui.gd` | Equipment UI | Signal-Wiring |
| `test_factory3d_nature.gd` | Factory3D | Mesh-Generierung |
| `test_game_manager.gd` | GameManager | State-Maschine, Übergänge (E-02 Fix) |
| `test_game_save_service.gd` | GameSaveService | Delegation, Guard (E-02 Fix) |
| `test_goblin_loot.gd` | LootTable | Drop-Rates |
| `test_hain_skill_content.gd` | Skill-Content-Konsistenz | Skill-.tres ↔ Manifest, xp_type ↔ Skill, Loot ↔ Item, Weltobjekt ↔ KNOWN_PROP_TYPES/Biom/Respawn (siehe docs/skill-writing-guide.md) |
| `test_inventory_system.gd` | InventorySystem | Add/Remove, Limits, Round-Trip (E-02 Fix) |
| `test_inventory_ui_signal.gd` | Inventory UI | Signal-Wiring |
| `test_network_bridge.gd` | NetworkBridge | Tier-1/2 Routing |
| `test_notification_controller.gd` | NotificationController | IUIContext.bus()-Injektion, kein AutoLoad-Zugriff (I-02 Fix) |
| `test_player_hp_controller.gd` | PlayerHPController | IUIContext.bus()-Injektion, kein AutoLoad-Zugriff (I-02 Fix) |
| `test_player_state_service.gd` | PlayerStateService | State-Übergänge, Multi-Tenanz (E-02 Fix) |
| `test_quest_objective.gd` | QuestObjectiveHandler | Objective-Auflösung |
| `test_quest_service.gd` | QuestService | Start/Complete, Prereqs, Round-Trip (E-02 Fix) |
| `test_respawn_service.gd` | RespawnService | Min-Heap, Tick, Callbacks (E-02 Fix) |
| `test_save_migration.gd` | SaveMigrationService | v1→v2→v3-Migration |
| `test_save_system.gd` | SaveSystem | Slot-API, .bak-Recovery (A-02 Fix) |
| `test_service_validator.gd` | ServiceValidator | Injizierbare Config, Struktur-Validierung (H-01 Fix) |
| `test_skill_panel_controller.gd` | SkillPanelController | IUIContext.bus()-Injektion, kein AutoLoad-Zugriff (I-02 Fix) |
| `test_skill_system.gd` | SkillSystem | XP/Level, Multi-Tenanz |
| `test_stat_modifier.gd` | StatModifierService | Modifier-Berechnung |
| `test_state_validator.gd` | StateValidator | Erlaubte/Blockierte Übergänge |
| `test_ui_context.gd` | UIContext | bus()-Auflösung aus Registry, for_test()-Isolation (I-02 Fix) |
| `test_world_save_handler.gd` | WorldSaveHandler | Bäume/Erze/Position Round-Trip (E-02 Fix) |

### Integration-Test (`tests/IntegrationTest.gd`)

Drei Testgruppen (E-01 Fix):
1. **Integrity** — Services nicht null + korrekte Typen nach Boot
2. **GameManager-State** — korrekte State-Initialisierung
3. **Session-State** — `is_session_active()` konsistent mit GameManager

## Bekannte Gaps

- `ServiceOrchestrator` — Boot-Error-Paths, Character-Switch: erfordert Scene-Lifecycle-Harness.
  Scope für eigenen Sprint (nach E-01/E-02).
- `_atomic_write` in SaveSystem — plattformabhängige Dateisystem-Atomicity nicht sinnvoll in GUT testbar.
- Property-Based Testing (E-03) — GUT Fuzzer für `calculate_damage()`, `get_effective_stat()`, `migrate()`.
  Offen als P2-Backlog.
- UI-Controller (`scripts/ui/controllers/`) — I-02 (AUDIT-03) hat alle 10 Controller auf injizierten
  `IUIContext.bus()` umgestellt und das mit 3 Beispiel-Tests bewiesen (Notification/PlayerHP/SkillPanel:
  je ein RefCounted-, Node-neu- und Node-bereits-ctx-Fall). Volle Testabdeckung für die restlichen 7
  Controller bleibt IV-03 (separat getrackt) — die Architektur ist jetzt testbar, aber nicht jeder
  Controller hat bereits einen eigenen Test.
