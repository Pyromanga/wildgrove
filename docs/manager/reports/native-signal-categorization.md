# Native-Signal-Kategorisierung (Grundlage für TODO Punkt 5 / ADR)

Automatisch generiert von `scripts/agent/analyze_native_signals.py`. 87 native Signale geprüft.

- LOCAL: 52
- CROSS_LAYER: 33
- NEEDS_HUMAN: 2

Methodik: tests/-Connects zählen nicht als externe Kopplung (Round 110 Methodik-Korrektur — ein Unit-Test der ein Signal beobachtet ist kein Business-Konsument). Siehe Tool-Header für Details.

## CROSS_LAYER — Migrationskandidaten

- `achievement_progress` (scripts/progression/achievements/AchievementService.gd, class `AchievementService`) — connect von: scripts/progression/achievements/ui/AchievementPanelController.gd
- `achievement_snapshot_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/progression/achievements/AchievementService.gd
- `achievement_unlocked` (scripts/progression/achievements/AchievementService.gd, class `AchievementService`) — connect von: scripts/progression/achievements/ui/AchievementPanelController.gd
- `achievement_unlocked_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/progression/achievements/AchievementService.gd
- `achievements_synced` (scripts/progression/achievements/AchievementService.gd, class `AchievementService`) — connect von: scripts/progression/achievements/ui/AchievementPanelController.gd
- `broadcast_event_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/economy/trading/AuctionHouseService.gd, scripts/entities/combat/PvPDeathLossService.gd, scripts/social/chat/ChatService.gd
- `character_created` (scripts/onboarding/CharacterCreationService.gd, class `CharacterCreationService`) — connect von: scripts/progression/achievements/AchievementService.gd
- `character_creation_completed_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/onboarding/CharacterCreationService.gd
- `character_creation_confirmed` (scripts/onboarding/CharacterCreationService.gd, class `CharacterCreationService`) — connect von: scripts/onboarding/ui/CharacterCreationController.gd
- `character_creation_skipped` (scripts/onboarding/CharacterCreationService.gd, class `CharacterCreationService`) — connect von: scripts/progression/achievements/AchievementService.gd
- `character_creation_skipped_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/onboarding/CharacterCreationService.gd
- `death_loss_applied` (scripts/entities/combat/PvPDeathLossService.gd, class `PvPDeathLossService`) — connect von: scripts/progression/achievements/AchievementService.gd
- `domain_event_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/progression/quests/QuestService.gd
- `economy_state_received` (scripts/networking/NetworkBridge.gd, class `NetworkBridge`) — connect von: scripts/economy/currency/CurrencyService.gd, scripts/economy/equipment/EquipmentService.gd, scripts/economy/inventory/InventorySystem.gd, scripts/economy/trading/AuctionHouseService.gd, scripts/economy/trading/TradeService.gd, scripts/progression/skills/SkillSystem.gd
- `equipment_changed` (scripts/economy/equipment/EquipmentService.gd, class `EquipmentService`) — connect von: scripts/economy/equipment/ui/EquipmentUIController.gd, scripts/economy/inventory/ui/InventoryUIController.gd
- `gold_changed` (scripts/economy/currency/CurrencyService.gd, class `CurrencyService`) — connect von: scripts/economy/bank/ui/BankUIController.gd, scripts/economy/inventory/ui/InventoryUIController.gd, scripts/economy/shop/ui/ShopUIController.gd, scripts/economy/trading/ui/AuctionHouseUIController.gd, scripts/economy/trading/ui/TradeUIController.gd
- `inventory_changed` (scripts/economy/inventory/InventorySystem.gd, class `InventorySystem`) — connect von: scripts/economy/bank/ui/BankUIController.gd, scripts/economy/equipment/ui/EquipmentUIController.gd, scripts/economy/inventory/ui/InventoryUIController.gd, scripts/economy/shop/ui/ShopUIController.gd, scripts/economy/trading/ui/AuctionHouseUIController.gd, scripts/economy/trading/ui/TradeUIController.gd
- `invite_declined` (scripts/economy/trading/TradeService.gd, class `TradeService`) — connect von: scripts/economy/trading/ui/TradeUIController.gd
- `invite_received` (scripts/economy/trading/TradeService.gd, class `TradeService`) — connect von: scripts/economy/trading/ui/TradeUIController.gd
- `listing_cancelled` (scripts/economy/trading/AuctionHouseService.gd, class `AuctionHouseService`) — connect von: scripts/economy/trading/ui/AuctionHouseUIController.gd
- `listing_created` (scripts/economy/trading/AuctionHouseService.gd, class `AuctionHouseService`) — connect von: scripts/economy/trading/ui/AuctionHouseUIController.gd, scripts/progression/achievements/AchievementService.gd
- `listings_updated` (scripts/economy/trading/AuctionHouseService.gd, class `AuctionHouseService`) — connect von: scripts/economy/trading/ui/AuctionHouseUIController.gd
- `on_log` (scripts/logger/Logger.gd, class `None`) — connect von: scripts/debug/SimpleTerminal.gd
- `report_submitted` (scripts/social/moderation/ReportService.gd, class `ReportService`) — connect von: scripts/progression/achievements/AchievementService.gd
- `sale_completed` (scripts/economy/shop/ShopService.gd, class `ShopService`) — connect von: scripts/economy/shop/ui/ShopUIController.gd
- `session_cancelled` (scripts/economy/trading/TradeService.gd, class `TradeService`) — connect von: scripts/economy/trading/ui/TradeUIController.gd
- `session_started` (scripts/economy/trading/TradeService.gd, class `TradeService`) — connect von: scripts/economy/trading/ui/TradeUIController.gd
- `session_updated` (scripts/economy/trading/TradeService.gd, class `TradeService`) — connect von: scripts/economy/trading/ui/TradeUIController.gd
- `skill_changed` (scripts/progression/skills/SkillSystem.gd, class `SkillSystem`) — connect von: scripts/progression/skills/ui/SkillPanelController.gd, scripts/progression/wiki/WikiService.gd
- `stat_changed` (scripts/progression/stats/StatsService.gd, class `StatsService`) — connect von: scripts/progression/achievements/AchievementService.gd
- `trade_completed` (scripts/economy/trading/TradeService.gd, class `TradeService`) — connect von: scripts/economy/trading/ui/TradeUIController.gd
- `wiki_entry_discovered` (scripts/progression/wiki/WikiService.gd, class `WikiService`) — connect von: scripts/progression/wiki/ui/WikiPanelController.gd
- `wiki_synced` (scripts/progression/wiki/WikiService.gd, class `WikiService`) — connect von: scripts/progression/wiki/ui/WikiPanelController.gd

## NEEDS_HUMAN — manuell klären

- `close_requested` — Name-Kollision: 4 unabhängige Deklarationen (scripts/economy/bank/ui/BankVisuals.gd, scripts/economy/shop/ui/ShopVisuals.gd, scripts/economy/trading/ui/AuctionHouseVisuals.gd, scripts/economy/trading/ui/TradeVisuals.gd) — welcher .connect()-Aufruf zu welcher gehört ist ohne Typ-Checker nicht sicher auflösbar.
- `health_changed` — Name-Kollision: 2 unabhängige Deklarationen (scripts/entities/combat/HealthComponent.gd, scripts/entities/player/PlayerStats.gd) — welcher .connect()-Aufruf zu welcher gehört ist ohne Typ-Checker nicht sicher auflösbar.

## LOCAL — bleibt natives Signal

- `action_triggered` (scripts/ui/visuals/ContextMenuVisuals.gd)
- `add_item_requested` (scripts/economy/trading/ui/TradeVisuals.gd)
- `application_failed` (scripts/economy/protection/ItemProtectionService.gd)
- `aura_changed` (scripts/world/pvp/AuraService.gd)
- `buy_requested` (scripts/economy/trading/ui/AuctionHouseVisuals.gd)
- `cancel_requested` (scripts/economy/trading/ui/AuctionHouseVisuals.gd)
- `chat_message_received` (scripts/networking/NetworkBridge.gd)
- `confirm_pressed` (scripts/economy/trading/ui/TradeVisuals.gd)
- `connection_failed` (scripts/networking/NetworkBridge.gd)
- `death_loot_skipped` (scripts/entities/combat/DeathLootService.gd)
- `deposit_gold_requested` (scripts/economy/bank/ui/BankVisuals.gd)
- `died` (scripts/entities/combat/HealthComponent.gd)
- `entry_added` (scripts/debug/SimpleTerminal.gd)
- `generation_complete` (scripts/world/core/WorldGenerationService.gd)
- `generation_failed` (scripts/world/core/WorldGenerationService.gd)
- `gravestone_spawned` (scripts/entities/combat/DeathLootService.gd)
- `interacted` (scripts/interaction/InteractableComponent.gd)
- `invite_accept_requested` (scripts/economy/trading/ui/TradeVisuals.gd)
- `invite_decline_requested` (scripts/economy/trading/ui/TradeVisuals.gd)
- `list_requested` (scripts/economy/trading/ui/AuctionHouseVisuals.gd)
- `menu_ready` (scripts/ui/MenuScopeInitializer.gd)
- `message_received` (scripts/social/chat/ChatService.gd)
- `message_rejected` (scripts/social/chat/ChatService.gd)
- `modifier_changed` (scripts/economy/equipment/StatModifierService.gd)
- `option_selected` (scripts/onboarding/ui/CharacterCreationVisuals.gd)
- `pickpocket_attempted` (scripts/entities/theft/PickpocketService.gd)
- `pickpocket_failed` (scripts/entities/theft/PickpocketService.gd)
- `player_connected` (scripts/networking/NetworkBridge.gd)
- `player_disconnected` (scripts/networking/NetworkBridge.gd)
- `player_entered` (scripts/interaction/ProximityDetector.gd)
- `player_exited` (scripts/interaction/ProximityDetector.gd)
- `protection_applied` (scripts/economy/protection/ItemProtectionService.gd)
- `pvp_protection_consumed` (scripts/economy/protection/ItemProtectionService.gd)
- `ready_toggled` (scripts/economy/trading/ui/TradeVisuals.gd)
- `remove_item_requested` (scripts/economy/trading/ui/TradeVisuals.gd)
- `report_rejected` (scripts/social/moderation/ReportService.gd)
- `server_disconnected` (scripts/networking/NetworkBridge.gd)
- `service_registered` (scripts/platform/ServiceRegistry.gd)
- `service_unregistered` (scripts/platform/ServiceRegistry.gd)
- `set_gold_requested` (scripts/economy/trading/ui/TradeVisuals.gd)
- `skip_pressed` (scripts/onboarding/ui/CharacterCreationVisuals.gd)
- `skulled` (scripts/world/pvp/PvPService.gd)
- `stamina_changed` (scripts/entities/player/PlayerStats.gd)
- `stats_depleted` (scripts/entities/player/PlayerStats.gd)
- `stats_restored` (scripts/entities/player/PlayerStats.gd)
- `thank_failed` (scripts/world/pvp/AuraService.gd)
- `toggled` (scripts/debug/SimpleTerminal.gd)
- `wiki_entry_discovered_received` (scripts/networking/NetworkBridge.gd)
- `wiki_snapshot_received` (scripts/networking/NetworkBridge.gd)
- `withdraw_gold_requested` (scripts/economy/bank/ui/BankVisuals.gd)
- `world_ready` (scripts/world/core/WorldScopeInitializer.gd)
- `world_scope_ready` (scripts/platform/scopes/CharacterScope.gd)
