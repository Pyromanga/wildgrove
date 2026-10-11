# res://scripts/eventbus/EventBus.gd
extends Node

## EventBus — Globale Signal-Infrastruktur.
##
## AutoLoad #2 (nach AppLogger, vor allen Services).
## Existiert für die gesamte Laufzeit des Spiels, unabhängig vom Service-Lifecycle.
##
## Verwendung:
##   EventBus.player.health_changed.emit(new_health)
##   EventBus.world.day_started.connect(_on_day_started)
##   EventBus.system.services_initialized.connect(_on_ready)
##
## Neuen Namespace hinzufügen:
##   1. NeuesEvents.gd in der jeweiligen Domain anlegen (extends BaseEvents),
##      z.B. res://scripts/progression/quests/QuestEvents.gd
##   2. Hier eine @onready-Zeile eintragen — fertig.

# ─────────────────────────────────────────────
# Namespaces
# ─────────────────────────────────────────────

## Alle player-bezogenen Signale (Health, XP, Level, Input …)
var player: PlayerEvents

## Alle world-bezogenen Signale (Tag/Nacht, Wetter, Chunk-Load …)
var world: WorldEvents

## App-Lifecycle-Signale ohne eigene Domain (State, Settings, Boot).
## ADR-018: Save/Load/Session/Networking wurden nach persistence/session/networking
## herausgelöst — siehe dort.
var system: SystemEvents

## UI-Signale (Menü öffnen/schließen, HUD-Updates …)
var ui: UIEvents

#Quests
var quest: QuestEvents

## Save/Load-Signale (ADR-018, vorher Teil von SystemEvents).
var persistence: PersistenceEvents

## Session-Lifecycle-Signale (ADR-009, ADR-018 — vorher Teil von SystemEvents).
var session: SessionEvents

## Netzwerk-Lifecycle-Signale (ADR-010, ADR-018 — vorher Teil von SystemEvents).
var networking: NetworkingEvents

## Zonen-Lifecycle-Signale (ADR-030) — autoritative Enter/Exit-Events.
var zones: ZoneEvents

## Kampf-/PvP-Lifecycle-Signale (ADR-018-Nachtrag via ADR-036/ADR-042,
## Round 98) — Kill-Feed-Broadcast (player_killed_by_player).
var combat: CombatEvents

## Bank-/Lager-Signale (ADR-034) — ADR-050 Phase 2, erster Migrations-Batch
## (Round 112). Ersetzt die vorher nativen BankService-Signale.
var bank: BankEvents

## Auktionshaus-Signale (ADR-035) — ADR-050 Phase 2, zweiter Migrations-Batch
## (Round 113). Ersetzt purchase_completed/transaction_failed, vorher native
## AuctionHouseService-Signale.
var auction: AuctionEvents

## Spieler-Handel-Signale (ADR-035) — ADR-050 Phase 2, zweiter Migrations-
## Batch (Round 113). Ersetzt transaction_failed, vorher natives
## TradeService-Signal.
var trade: TradeEvents

## Shop-NPC-Signale (Round 88) — ADR-050 Phase 2, zweiter Migrations-Batch
## (Round 113). Ersetzt purchase_completed/transaction_failed, vorher native
## ShopService-Signale.
var shop: ShopEvents

## Schmelzen-&-Schmieden-Signale (SmithingService) — von Anfang an auf dem Bus, keine
## Migration alter nativer Signale (siehe SmithingEvents.gd).
var smithing: SmithingEvents

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	player = PlayerEvents.new()
	world = WorldEvents.new()
	system = SystemEvents.new()
	ui = UIEvents.new()
	quest = QuestEvents.new()
	persistence = PersistenceEvents.new()
	session = SessionEvents.new()
	networking = NetworkingEvents.new()
	zones = ZoneEvents.new()
	combat = CombatEvents.new()
	bank = BankEvents.new()
	auction = AuctionEvents.new()
	trade = TradeEvents.new()
	shop = ShopEvents.new()
	smithing = SmithingEvents.new()
	AppLogger.log_info(
		"EventBus bereit. Namespaces: %s" % ", ".join(get_namespaces()),
		"EventBus"
	)

# ─────────────────────────────────────────────
# Debug-Hilfe
# ─────────────────────────────────────────────

## Gibt alle verfügbaren Namespace-Namen zurück.
## Nützlich für den SimpleTerminal / Laufzeit-Inspektion.
## Round 113: Log-Zeile in _ready() liest jetzt von hier statt einer
## separaten, von Hand gepflegten Liste — "bank" fehlte dort seit Round 112
## (die Liste selbst war schon vorher korrekt, siehe get_namespaces()),
## jetzt können beide nicht mehr auseinanderlaufen.
func get_namespaces() -> Array[String]:
	return ["player", "world", "system", "ui", "quest", "persistence", "session", "networking", "zones", "combat", "bank", "auction", "trade", "shop", "smithing"]
