# Architektur-Abriss (automatisch generiert)

Quelle: `config/BootstrapConfig.tres`, `scripts/eventbus/EventBus.gd`, `class_name`-Deklarationen unter `scripts/`, `docs/adr/`, `tests/unit/`. Kein manueller Cache — bei jedem Lauf frisch abgeleitet.

## Domains (17)

| Domain | .gd-Dateien | Services (DI) |
|---|---|---|
| `debug` | 3 | — |
| `economy` | 40 | auction_house, bank, currency, equipment, inventory, item_protection, reward_dispatcher, shop, stat_modifiers, trade |
| `entities` | 45 | combat, death_loot, pickpocket, playerstates, pvp_death_loss |
| `eventbus` | 5 | — |
| `interaction` | 13 | interaction_executor |
| `logger` | 2 | — |
| `networking` | 8 | network_bridge |
| `onboarding` | 6 | character_creation |
| `persistence` | 8 | data, gamesave, savesystem, settings_service |
| `platform` | 42 | gamemanager, permission_service, ticker |
| `progression` | 28 | achievement, quest, skill_system, stats, wiki |
| `session` | 5 | scenemanager, session_manager |
| `social` | 2 | chat, report |
| `telemetry` | 1 | telemetry |
| `testing` | 1 | — |
| `ui` | 31 | — |
| `world` | 45 | aura, pvp, respawn, world, world_gen, zone_service |

## Services (41) — registriert in BootstrapConfig.tres

| Service | Domain | Pfad | required_deps | optional_deps | Test? |
|---|---|---|---|---|---|
| `auction_house` | economy | `res://scripts/economy/trading/AuctionHouseService.gd` | currency, data, inventory, bank | savesystem, event_bus | ✓ |
| `bank` | economy | `res://scripts/economy/bank/BankService.gd` | currency, data, inventory | savesystem, event_bus | ✓ |
| `currency` | economy | `res://scripts/economy/currency/CurrencyService.gd` | event_bus | savesystem | ✓ |
| `equipment` | economy | `res://scripts/economy/equipment/EquipmentService.gd` | savesystem | data, inventory, stat_modifiers | ✓ |
| `inventory` | economy | `res://scripts/economy/inventory/InventorySystem.gd` | event_bus | data, savesystem | ✓ |
| `item_protection` | economy | `res://scripts/economy/protection/ItemProtectionService.gd` | inventory | — | ✓ |
| `reward_dispatcher` | economy | `res://scripts/economy/rewards/RewardDispatcher.gd` | event_bus, inventory, skill_system | — | ✓ |
| `shop` | economy | `res://scripts/economy/shop/ShopService.gd` | currency, data, inventory | event_bus | ✓ |
| `stat_modifiers` | economy | `res://scripts/economy/equipment/StatModifierService.gd` | — | — | ✓ |
| `trade` | economy | `res://scripts/economy/trading/TradeService.gd` | currency, inventory | savesystem, event_bus | ✓ |
| `combat` | entities | `res://scripts/entities/combat/CombatSystem.gd` | event_bus | equipment, pvp, skill_system, stat_modifiers, ticker | ✓ |
| `death_loot` | entities | `res://scripts/entities/combat/DeathLootService.gd` | currency, inventory | — | ✓ |
| `pickpocket` | entities | `res://scripts/entities/theft/PickpocketService.gd` | inventory, currency, skill_system, zone_service | savesystem, event_bus | ✓ |
| `playerstates` | entities | `res://scripts/entities/player/PlayerStateService.gd` | — | event_bus | ✗ |
| `pvp_death_loss` | entities | `res://scripts/entities/combat/PvPDeathLossService.gd` | pvp, currency, inventory | item_protection, aura, event_bus | ✓ |
| `interaction_executor` | interaction | `res://scripts/interaction/InteractionExecutor.gd` | event_bus | playerstates, stat_modifiers | ✓ |
| `network_bridge` | networking | `res://scripts/networking/NetworkBridge.gd` | — | bank, auction_house, chat, report, achievement, character_creation, wiki, equipment, inventory, item_protection, aura, pickpocket, playerstates, quest, savesystem, session_manager, shop, skill_system, trade, world, zone_service | ✓ |
| `character_creation` | onboarding | `res://scripts/onboarding/CharacterCreationService.gd` | — | savesystem, session_manager | ✓ |
| `data` | persistence | `res://scripts/persistence/DataService.gd` | — | — | ✗ |
| `gamesave` | persistence | `res://scripts/persistence/GameSaveService.gd` | event_bus, savesystem | — | ✗ |
| `savesystem` | persistence | `res://scripts/persistence/SaveSystem.gd` | event_bus | — | ✗ |
| `settings_service` | persistence | `res://scripts/persistence/SettingsService.gd` | — | — | ✓ |
| `gamemanager` | platform | `res://scripts/platform/GameManager.gd` | event_bus, gameconfig | scenemanager | ✗ |
| `permission_service` | platform | `res://scripts/platform/PermissionService.gd` | — | — | ✓ |
| `ticker` | platform | `res://scripts/platform/ServiceTicker.gd` | — | — | ✗ |
| `achievement` | progression | `res://scripts/progression/achievements/AchievementService.gd` | — | pvp_death_loss, auction_house, report, savesystem, telemetry, stats, currency, data, session_manager, character_creation | ✓ |
| `quest` | progression | `res://scripts/progression/quests/QuestService.gd` | event_bus, savesystem | data, reward_dispatcher, skill_system | ✓ |
| `skill_system` | progression | `res://scripts/progression/skills/SkillSystem.gd` | data, event_bus, savesystem | — | ✓ |
| `stats` | progression | `res://scripts/progression/stats/StatsService.gd` | — | event_bus, savesystem | ✓ |
| `wiki` | progression | `res://scripts/progression/wiki/WikiService.gd` | — | event_bus, skill_system, data, savesystem, session_manager | ✓ |
| `scenemanager` | session | `res://scripts/session/SceneManager.gd` | event_bus | — | ✗ |
| `session_manager` | session | `res://scripts/session/SessionManager.gd` | — | event_bus | ✓ |
| `chat` | social | `res://scripts/social/chat/ChatService.gd` | — | — | ✓ |
| `report` | social | `res://scripts/social/moderation/ReportService.gd` | — | savesystem | ✓ |
| `telemetry` | telemetry | `res://scripts/telemetry/TelemetryService.gd` | — | — | ✓ |
| `aura` | world | `res://scripts/world/pvp/AuraService.gd` | — | savesystem | ✓ |
| `pvp` | world | `res://scripts/world/pvp/PvPService.gd` | permission_service, zone_service | event_bus, savesystem, ticker, aura | ✓ |
| `respawn` | world | `res://scripts/world/respawn/RespawnService.gd` | event_bus | ticker | ✓ |
| `world` | world | `res://scripts/world/core/WorldService.gd` | — | combat, currency, data, equipment, event_bus, gamemanager, interaction_executor, inventory, playerstates, pvp_death_loss, aura, death_loot, pickpocket, respawn, savesystem, session_manager, skill_system, stat_modifiers, ticker, trade, world_gen, zone_service | ✓ |
| `world_gen` | world | `res://scripts/world/core/WorldGenerationService.gd` | — | — | ✗ |
| `zone_service` | world | `res://scripts/world/zones/ZoneService.gd` | — | event_bus | ✓ |

## EventBus-Namespaces (14)

| Namespace | Klasse | Datei |
|---|---|---|
| `EventBus.player` | `PlayerEvents` | `scripts/entities/player/PlayerEvents.gd` |
| `EventBus.world` | `WorldEvents` | `scripts/world/core/WorldEvents.gd` |
| `EventBus.system` | `SystemEvents` | `scripts/eventbus/SystemEvents.gd` |
| `EventBus.ui` | `UIEvents` | `scripts/ui/UIEvents.gd` |
| `EventBus.quest` | `QuestEvents` | `scripts/progression/quests/QuestEvents.gd` |
| `EventBus.persistence` | `PersistenceEvents` | `scripts/persistence/PersistenceEvents.gd` |
| `EventBus.session` | `SessionEvents` | `scripts/session/SessionEvents.gd` |
| `EventBus.networking` | `NetworkingEvents` | `scripts/networking/NetworkingEvents.gd` |
| `EventBus.zones` | `ZoneEvents` | `scripts/world/zones/ZoneEvents.gd` |
| `EventBus.combat` | `CombatEvents` | `scripts/entities/combat/CombatEvents.gd` |
| `EventBus.bank` | `BankEvents` | `scripts/economy/bank/BankEvents.gd` |
| `EventBus.auction` | `AuctionEvents` | `scripts/economy/trading/AuctionEvents.gd` |
| `EventBus.trade` | `TradeEvents` | `scripts/economy/trading/TradeEvents.gd` |
| `EventBus.shop` | `ShopEvents` | `scripts/economy/shop/ShopEvents.gd` |

## ADRs (4)

| Datei | Titel | Status |
|---|---|---|
| `000-index.md` | Architecture Decision Records — WildGrove | (kein Status-Feld) |
| `012-ui-eventbus-injection.md` | ADR-012 — UI-Layer EventBus-Injektion: `IUIContext.bus()` | Accepted |
| `017-cross-scope-service-access.md` | ADR-017: Cross-Scope Service Access — ein einziger Mechanismus | Akzeptiert |
| `050-native-signal-domain-event-migration.md` | ADR-050 — Native-Signal → Domain-Event-Migration (Konzept + Migrationsplan) | Proposed — Konzept akzeptiert, Umsetzung noch NICHT begonnen (siehe |
