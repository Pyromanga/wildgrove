extends Service
class_name CurrencyService
## implements ISaveProvider

## CurrencyService — ADR-033: Spieler-Währung (Gold), eigenständiger Service
## statt Item-im-Inventar (siehe ADR-033 "Option B: eigenständiger
## CurrencyService (gewählt)").
##
## Dasselbe request_/on_*_confirmed-Muster wie InventorySystem (ADR-004/
## Round-45-Cheat-Audit-Lehre): Client meldet nur Absicht
## (request_add_gold()/request_remove_gold()), Server berechnet und bestätigt
## (on_gold_changed_confirmed()). player_id ist überall die stabile
## player_uuid (ADR-029-Konvention), nie peer_id.
##
## Persistenz über ISaveProvider (ADR-005/006), eigener Save-Key ("currency"),
## bewusst getrennt vom Inventar-Bucket — ADR-033 selbst nennt das "Detailfrage
## für Umsetzung, keine ADR-relevante Entscheidung"; hier für saubere Trennung
## von den Item-/Slot-Daten so entschieden.
##
## KORREKTUR ggü. ADR-033-Text: das ADR erwähnt "EventBus.economy (bestehender
## Namespace, siehe ADR-022)" — dieser Namespace existiert tatsächlich NICHT
## in IEventBus.gd (geprüft: nur player()/world()/system()/ui()/quest()/
## persistence()/session()/networking()/zones()). InventorySystem verwendet
## ebenfalls KEINEN EventBus-Namespace für seinen analogen
## `inventory_changed`-Sync, sondern ein eigenes Signal direkt am Service, das
## UI-Controller/andere Services direkt abonnieren. Dieselbe Konvention wird
## hier übernommen (`gold_changed`-Signal direkt an diesem Service) statt einen
## neuen EventBus-Namespace zu erfinden, den kein anderer Konsument braucht.
##
## OVERFLOW-SCHUTZ: GDScript-`int` ist 64-Bit. MAX_GOLD ist der tatsächliche
## Maximalwert (2^63-1, ~9,2 Trillionen) — kein künstlich niedrigeres Cap,
## siehe ADR-033 "Wichtig"-Absatz. Ein Add, das MAX_GOLD überschreiten würde,
## wird abgelehnt statt still zu über-/unterlaufen.
##
## Save-Format: { "<player_uuid>": <gold: int> }.

signal gold_changed(player_id: String, new_amount: int, delta: int)

const LOG_CAT := "Currency"
const SAVE_KEY := "currency"
const MAX_GOLD := 9_223_372_036_854_775_807  # 2^63 - 1 — echtes GDScript-int-Maximum, keine künstliche Deckelung

## Multi-Tenant State: { player_id (String): gold (int) }
var _players: Dictionary = {}

var _save_system: SaveSystem
var _network:     NetworkBridge = null
var _bus:         IEventBus     = null

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	var t := AppLogger.log_begin("CurrencyService.configure()", LOG_CAT)

	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus          = deps.require(ServiceKeys.EVENT_BUS)            as IEventBus
	## Siehe InventorySystem.configure()-Kommentar: Test-Harnesses injizieren
	## network_bridge oft direkt über configure() statt über den
	## Late-Inject-Pfad (inject_network_bridge(), Phase C8) — beide Wege
	## decken _connect_economy_sync() idempotent ab.
	_connect_economy_sync()
	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_end("CurrencyService.configure()", t, LOG_CAT)
	AppLogger.log_info("Initialisiert.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate / Late-Inject
# ─────────────────────────────────────────────

## Phase C8 Late-Inject (siehe BootPipeline.gd) — NetworkBridge wird nach
## vollem Session-Boot injiziert, analog InventorySystem.inject_network_bridge().
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_economy_sync()

func _connect_economy_sync() -> void:
	if is_instance_valid(_network) and not _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.connect(_on_economy_state_received)

func on_ready() -> void:
	# Analog InventorySystem: auf JEDER Mutation prüfen, ob ein Rücksync an
	# einen entfernten Client nötig ist (Autoritäts-Seite).
	gold_changed.connect(_on_gold_state_changed)

func on_cleanup() -> void:
	if gold_changed.is_connected(_on_gold_state_changed):
		gold_changed.disconnect(_on_gold_state_changed)
	if is_instance_valid(_network) and _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.disconnect(_on_economy_state_received)
	AppLogger.log_info("CurrencyService cleanup.", LOG_CAT)

## R-7 (ADR-022)-Muster, Autoritäts-Seite: für jede State-Änderung eines
## Spielers, der nicht dieser Prozess selbst ist, den neuen Kontostand an
## dessen Client schicken.
func _on_gold_state_changed(player_id: String, new_amount: int, _delta: int) -> void:
	if not is_instance_valid(_network):
		return
	_network.send_economy_update_for_player(player_id, "currency", {"gold": new_amount})

## R-7 (ADR-022)-Muster, Client-Seite: wendet einen von der Autorität
## gesendeten Gold-Stand auf den EIGENEN lokalen Player an.
func _on_economy_state_received(kind: String, payload: Dictionary) -> void:
	if kind != "currency":
		return
	if not is_instance_valid(_network):
		return
	var local_id := _network.get_local_player_id()
	if local_id.is_empty():
		return
	var new_amount: int = int(payload.get("gold", 0))
	var old_amount: int = _players.get(local_id, 0)
	_players[local_id] = new_amount
	gold_changed.emit(local_id, new_amount, new_amount - old_amount)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for pid in _players:
		out[pid] = _players[pid]
	return out

func _restore_from_save(saved: Dictionary) -> void:
	for pid in saved:
		_players[pid] = int(saved[pid])

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Absicht: Gold hinzufügen. Server validiert (amount > 0, Overflow), ruft
## dann on_gold_changed_confirmed() auf. Analog
## InventorySystem.request_add_item().
func request_add_gold(player_id: String, amount: int) -> bool:
	if amount <= 0:
		AppLogger.log_warn("request_add_gold: amount muss > 0 sein (war %d, Spieler '%s')." % [amount, player_id], LOG_CAT)
		return false
	var current: int = _players.get(player_id, 0)
	if current > MAX_GOLD - amount:
		AppLogger.log_warn(
			"request_add_gold: MAX_GOLD-Overflow verhindert (Spieler '%s', aktuell %d, +%d)." % [player_id, current, amount],
			LOG_CAT
		)
		return false
	on_gold_changed_confirmed(player_id, amount)
	return true

## Absicht: Gold abziehen. Server validiert (amount > 0, kein negativer
## Kontostand).
func request_remove_gold(player_id: String, amount: int) -> bool:
	if amount <= 0:
		AppLogger.log_warn("request_remove_gold: amount muss > 0 sein (war %d, Spieler '%s')." % [amount, player_id], LOG_CAT)
		return false
	var current: int = _players.get(player_id, 0)
	if current < amount:
		AppLogger.log_warn(
			"request_remove_gold: unzureichender Kontostand (Spieler '%s', hat %d, will -%d)." % [player_id, current, amount],
			LOG_CAT
		)
		return false
	on_gold_changed_confirmed(player_id, -amount)
	return true

## Authority-Mutation: schreibt State für player_id. delta kann positiv (Add)
## oder negativ (Remove) sein — ein zentraler Mutationspunkt statt zwei
## separater (Gold hat anders als Items keine Slot-/Gewichts-Sonderfälle).
##
## C-02-Guard (wie InventorySystem.on_item_add_confirmed()): stellt sicher,
## dass nur die Autorität State mutiert — Verteidigung in der Tiefe, falls
## künftiger Code diese Methode je aus Nicht-Autoritäts-Kontext aufruft.
##
## ADR-010 Round 55-Prinzip ("Server vertraut niemandem"): Overflow-/
## Negativ-Kontostand-Prüfung wird HIER ERNEUT durchgeführt, nicht nur in
## request_add_gold()/request_remove_gold() — Tier 3 validiert an der
## Mutationsstelle selbst, nicht nur an einer Caller-Konvention.
func on_gold_changed_confirmed(player_id: String, delta: int) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_gold_changed_confirmed: Aufruf auf Nicht-Autorität (peer %d) — verweigert." % _network.get_local_peer_id(),
			LOG_CAT
		)
		return

	var current: int = _players.get(player_id, 0)
	if delta > 0 and current > MAX_GOLD - delta:
		AppLogger.log_error(
			"on_gold_changed_confirmed: MAX_GOLD-Overflow (Spieler '%s', %d + %d) — verweigert. Aufrufer hat request_add_gold()s Vorprüfung umgangen." % [player_id, current, delta],
			LOG_CAT
		)
		return
	if delta < 0 and current < -delta:
		AppLogger.log_error(
			"on_gold_changed_confirmed: negativer Kontostand verhindert (Spieler '%s', %d, delta %d) — verweigert. Aufrufer hat request_remove_gold()s Vorprüfung umgangen." % [player_id, current, delta],
			LOG_CAT
		)
		return

	var new_amount := current + delta
	_players[player_id] = new_amount
	gold_changed.emit(player_id, new_amount, delta)
	AppLogger.log_debug(
		"Gold geändert: Spieler '%s' %+d → %d." % [player_id, delta, new_amount],
		LOG_CAT
	)

func get_gold(player_id: String) -> int:
	return _players.get(player_id, 0)

func has_gold(player_id: String, amount: int) -> bool:
	return get_gold(player_id) >= amount
