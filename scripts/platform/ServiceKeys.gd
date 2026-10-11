# res://scripts/platform/ServiceKeys.gd
class_name ServiceKeys

## ServiceKeys — Typsichere Konstanten für alle Service-Registry-Keys.
##
## Ersetzt alle magic strings wie deps.get("savesystem") oder
## registry.get_service("inventory") durch ServiceKeys.SAVE_SYSTEM etc.
##
## Tippfehler crashen zur Laufzeit → durch Konstanten werden sie zu
## Compile-Time-Fehlern (GDScript: Parser-Fehler bei undefined const).
##
## Konvention: Konstanten spiegeln den tatsächlichen Registry-Key 1:1.
## Wenn ein Key umbenannt wird, hier ändern — alle Aufrufer folgen automatisch.

# ─────────────────────────────────────────────
# Global Services (app-lifetime)
# ─────────────────────────────────────────────

const TICKER        := "ticker"
const SCENE         := "scenemanager"
const SAVE_SYSTEM   := "savesystem"
const DATA          := "data"
const GAME_MANAGER  := "gamemanager"
const SESSION_MANAGER := "session_manager"
const SETTINGS_SERVICE := "settings_service"
const PERMISSION_SERVICE := "permission_service"

# ─────────────────────────────────────────────
# Session Services (character-lifetime)
# ─────────────────────────────────────────────

const GAME_SAVE         := "gamesave"
const NETWORK_BRIDGE    := "network_bridge"
const INVENTORY         := "inventory"
const SKILL_SYSTEM      := "skill_system"
const QUEST             := "quest"
const PLAYER_STATES     := "playerstates"
const REWARD_DISPATCHER := "reward_dispatcher"
const STAT_MODIFIERS    := "stat_modifiers"
const COMBAT            := "combat"
const EQUIPMENT         := "equipment"
const WORLD             := "world"
const INTERACTION       := "interaction_executor"
const WORLD_GEN         := "world_gen"
const RESPAWN           := "respawn"
const AMBIENT_SPAWNER := "ambient_spawner"  ## Gegner-Nachspawnen an Grabsteinen/Lagerfeuern etc., siehe AmbientSpawnService.gd
const CONDITIONAL_ENCOUNTERS := "conditional_encounters"  ## Biom/Wetter/Nacht-bedingte Spezial-Gegner, siehe ConditionalEncounterService.gd
const ENEMY_CULLING := "enemy_culling"  ## Räumt verwilderte, weit entfernte Gegner auf, siehe EnemyCullingService.gd
const ZONE_SERVICE      := "zone_service"
const CURRENCY          := "currency"
const SHOP               := "shop"
const PVP                := "pvp"  ## ADR-032
const BANK                := "bank"  ## ADR-034  ## ADR-033
const TRADE               := "trade"  ## ADR-035
const AUCTION_HOUSE       := "auction_house"  ## ADR-035
const ITEM_PROTECTION     := "item_protection"  ## ADR-038
const PVP_DEATH_LOSS      := "pvp_death_loss"  ## ADR-036
const AURA                := "aura"  ## ADR-036
const DEATH_LOOT          := "death_loot"  ## ADR-037
const PICKPOCKET          := "pickpocket"  ## ADR-039
const CHAT                := "chat"  ## ADR-043
const REPORT               := "report"  ## ADR-044
const TELEMETRY            := "telemetry"  ## ADR-045
const ACHIEVEMENT          := "achievement"  ## ADR-046
const CHARACTER_CREATION   := "character_creation"  ## ADR-048
const STATS                := "stats"  ## ADR-047
const WIKI                  := "wiki"  ## ADR-049
const SMITHING              := "smithing"  ## Schmelzen & Schmieden (SmithingService)

# ─────────────────────────────────────────────
# Injectable Resources (ADR-011)
# ─────────────────────────────────────────────

const GAME_CONFIG := "gameconfig"

# ─────────────────────────────────────────────
# Infrastructure (injectable — kein AutoLoad-Zugriff in Services)
# ─────────────────────────────────────────────

## IEventBus — injizierter Event-Bus für Services.
## In Produktion: EventBusAdapter (delegiert an EventBus-AutoLoad).
## In Tests:      MockEventBus (lokale Instanz, kein globales Bleeding).
const EVENT_BUS := "event_bus"
