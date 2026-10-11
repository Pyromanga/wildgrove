extends Service
class_name PvPDeathLossService

## PvPDeathLossService — ADR-036: Item-/Gold-Verlust bei PvP-Tod (Skull-Loot).
##
## Zentraler Einstiegspunkt: apply_death_loss(victim_player_id, killer_player_id),
## aufgerufen von Player._on_player_died() sobald erkannt wird, dass der
## todesursächliche Treffer von einem ANDEREN Spieler kam (siehe dort). Reine
## Anwendungslogik — die Entscheidung "war das überhaupt ein PvP-Treffer?" traf
## bereits CombatSystem.resolve_pvp_hit() (ADR-032), bevor der Tod eintrat.
##
## KERNPRINZIP (ADR-036 "Entscheidung", Korrektur ggü. Ursprungsfassung): die
## Verlust-Regel hängt am EIGENEN Skull-Status des STERBENDEN Spielers, nicht
## am Skull-Status des Killers.
##   - Opfer war geskullt  → 100% Verlust (abzüglich Schutzkategorien unten)
##   - Opfer war nicht geskullt → 5–70% Verlust, gestaffelt nach dem
##     mitgeführten Wert (Gold + Item-sell_price × Menge) des KILLERS zum
##     Zeitpunkt des Kills — je mehr der Killer riskiert, desto mehr verliert
##     das Opfer (Risiko-Belohnung).
##
## SCHUTZKATEGORIEN (ADR-038): PvE-Todesschutz und Diebstahlschutz sind
## PERMANENT und in BEIDEN Fällen oben vollständig ausgenommen — die
## Prozent-Rechnung greift nur auf den nach Abzug dieser Items verbleibenden
## Rest. Ein aktiver PvP-Schutz-Charge rettet, wenn vorhanden, GENAU DAS eine
## Item, auf dem er sitzt (wird dabei verbraucht — ItemProtectionService ist
## instanzbasiert, kein globaler "ganzer Tod ist ausgesetzt"-Schalter).
##
## LOOT-EMPFÄNGER: an den Killer (mit dem Auftraggeber dieser Runde
## abgestimmt — die ADR selbst legt das nicht explizit fest, "Skull-Loot" im
## Titel deutet aber klar in diese Richtung).
##
## KILL-FEED-BROADCAST (Round 98, ADR-042): jeder PvP-Tod broadcastet
## zusätzlich zur autoritätsseitigen `death_loss_applied`-Emission ein
## schmaleres `EventBus.combat.player_killed_by_player`-Signal an ALLE
## verbundenen Spieler (nicht nur Opfer/Killer) — siehe `_notify_kill()`
## und `CombatEvents.gd` für die Abgrenzung der beiden Signale.
##
## AUSSERHALB DES SCOPES DIESER RUNDE (bewusste Abgrenzung, keine Lücke):
##   - Ausgerüstete Items (EquipmentService-Slots) sind NICHT Teil des
##     Verlust-Pools — nur was in InventorySystem.get_all_items() liegt. Die
##     ADR unterscheidet nicht explizit zwischen Bag und Equipment; ein
##     bewusster, dokumentierter Schnitt statt stillschweigender Lücke.
##   - Rundungsverhalten bei kleinen Stacks (insbes. max_stack=1-Items wie
##     Waffen/Werkzeuge): `round(quantity * pct)` kann bei 5–40% auf 0
##     runden — ein einzelnes Werkzeug geht bei diesen Prozentsätzen NICHT
##     verloren. Entspricht der ADR wörtlich ("Stack-Mengen"), ist aber ein
##     bekannter rauer Rand, kein verstecktes Verhalten (ADR selbst: "Konkrete
##     Zahlen sind ein Vorschlag, kein finaler Balance-Wert").

signal death_loss_applied(
	victim_player_id: String,
	killer_player_id: String,
	gold_lost: int,
	items_lost: Array,
	loss_percent: float,
	victim_was_skulled: bool
)

const LOG_CAT := "PvPDeathLoss"

## Gegner-Risiko (Gold + Item-sell_price × Menge des KILLERS) → Verlust des
## Sterbenden. Absteigend sortiert — erste zutreffende Schwelle gewinnt.
const RISK_TIERS: Array[Array] = [
	[1_000_000_000.0, 0.70],
	[100_000_000.0,   0.60],
	[10_000_000.0,    0.50],
	[1_000_000.0,     0.40],
	[100_000.0,       0.30],
	[50_000.0,        0.20],
]
## Unterhalb der niedrigsten Stufe: fester Sockel statt 0% (ADR-036
## "Billig-Ganking soll sich klar weniger lohnen als ein fairer 50k-Kampf").
const BELOW_TIER_LOSS_PERCENT: float = 0.05

var _pvp:        PvPService           = null
var _currency:   CurrencyService      = null
var _inventory:  InventorySystem      = null
var _protection: ItemProtectionService = null
var _aura:       AuraService          = null
var _network:    NetworkBridge        = null
var _bus:        IEventBus            = null

func configure(deps: ServiceDeps) -> void:
	_pvp        = deps.require(ServiceKeys.PVP)              as PvPService
	_currency   = deps.require(ServiceKeys.CURRENCY)         as CurrencyService
	_inventory  = deps.require(ServiceKeys.INVENTORY)        as InventorySystem
	_protection = deps.get_optional(ServiceKeys.ITEM_PROTECTION) as ItemProtectionService
	_aura       = deps.get_optional(ServiceKeys.AURA)            as AuraService
	_network    = deps.get_optional(ServiceKeys.NETWORK_BRIDGE)  as NetworkBridge
	_bus        = deps.get_optional(ServiceKeys.EVENT_BUS)       as IEventBus
	_connect_broadcast()
	AppLogger.log_info("PvPDeathLossService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_broadcast()

## Round 98 (ADR-042): Kill-Feed-Broadcast-Empfang. Auf der Autorität selbst
## nie relevant (broadcast_to_all_peers() überspringt den lokalen Peer, siehe
## ADR-042) — die Autorität emittiert ihr eigenes Kill-Feed-Signal direkt in
## _notify_kill(), ohne Rundweg über dieses RPC.
func _connect_broadcast() -> void:
	if is_instance_valid(_network) and not _network.broadcast_event_received.is_connected(_on_broadcast_event_received):
		_network.broadcast_event_received.connect(_on_broadcast_event_received)

func on_cleanup() -> void:
	if is_instance_valid(_network) and _network.broadcast_event_received.is_connected(_on_broadcast_event_received):
		_network.broadcast_event_received.disconnect(_on_broadcast_event_received)

func _on_broadcast_event_received(kind: String, payload: Dictionary) -> void:
	if kind != "pvp_kill":
		return
	if is_instance_valid(_bus):
		_bus.combat().emit_player_killed_by_player(
			String(payload.get("victim_player_id", "")),
			String(payload.get("killer_player_id", "")),
			bool(payload.get("victim_was_skulled", false)),
			int(payload.get("gold_lost", 0)),
			int(payload.get("items_lost_count", 0))
		)

## Wendet den Tod-Verlust an. IMMER autoritätsseitig — es gibt hier bewusst
## KEINEN request_*()/on_*_confirmed()-Split wie bei den übrigen Services:
## ein PvP-Tod ist ausschließlich eine Server-Entscheidung (HealthComponent.died
## feuert nur auf der Autorität, siehe ADR-025), es gibt keinen Client-
## Auslöser, der geroutet werden müsste.
func apply_death_loss(victim_player_id: String, killer_player_id: String) -> void:
	if not _require_authority("apply_death_loss"):
		return
	if victim_player_id.is_empty() or killer_player_id.is_empty() or victim_player_id == killer_player_id:
		return
	if not is_instance_valid(_currency) or not is_instance_valid(_inventory):
		AppLogger.log_error("apply_death_loss: CurrencyService/InventorySystem fehlt.", LOG_CAT)
		return

	var victim_was_skulled := is_instance_valid(_pvp) and _pvp.is_skulled(victim_player_id)
	var loss_percent: float = 1.0 if victim_was_skulled else _compute_tiered_loss_percent(killer_player_id)

	# ADR-036 "Aura/Gesinnung": Kill-Strafe für den KILLER, ausschließlich wenn
	# ER SELBST zum Zeitpunkt des Kills geskullt war (siehe AuraService-
	# Klassenkommentar "SKULL-AUSLÖSENDER (UNPROVOZIERTER) KILL" für die
	# Interpretationsentscheidung) — unabhängig vom Skull-Status des Opfers,
	# der oben nur die Verlust-Prozente bestimmt.
	if is_instance_valid(_aura) and is_instance_valid(_pvp) and _pvp.is_skulled(killer_player_id):
		_aura.apply_kill_penalty(killer_player_id)

	var gold_lost := _apply_gold_loss(victim_player_id, killer_player_id, loss_percent)
	var items_lost := _apply_item_loss(victim_player_id, killer_player_id, loss_percent)

	death_loss_applied.emit(victim_player_id, killer_player_id, gold_lost, items_lost, loss_percent, victim_was_skulled)
	_notify_kill(victim_player_id, killer_player_id, victim_was_skulled, gold_lost, items_lost.size())
	AppLogger.log_info(
		"PvP-Tod-Verlust: '%s' → '%s' (geskullt=%s, %.0f%%): %d Gold, %d Item-Stacks."
		% [victim_player_id, killer_player_id, victim_was_skulled, loss_percent * 100.0, gold_lost, items_lost.size()],
		LOG_CAT
	)

## Round 98 (ADR-042): Kill-Feed für ALLE Spieler, nicht nur Opfer/Killer —
## death_loss_applied (oben) bleibt die autoritätsseitige Quelle der Wahrheit
## mit den vollen items_lost-Details; dieses Signal ist bewusst schmaler
## (nur eine Stack-ANZAHL, siehe CombatEvents-Klassenkommentar) und für
## JEDEN verbundenen Spieler gedacht.
## Lokal auf der Autorität DIREKT emittiert (kein Rundweg über das eigene
## Broadcast-RPC — broadcast_to_all_peers() überspringt den lokalen Peer
## ohnehin, siehe ADR-042), auf Clients über _on_broadcast_event_received().
func _notify_kill(victim_player_id: String, killer_player_id: String, victim_was_skulled: bool, gold_lost: int, items_lost_count: int) -> void:
	if is_instance_valid(_bus):
		_bus.combat().emit_player_killed_by_player(victim_player_id, killer_player_id, victim_was_skulled, gold_lost, items_lost_count)
	if is_instance_valid(_network):
		_network.broadcast_to_all_peers("pvp_kill", {
			"event": "player_killed",
			"victim_player_id": victim_player_id,
			"killer_player_id": killer_player_id,
			"victim_was_skulled": victim_was_skulled,
			"gold_lost": gold_lost,
			"items_lost_count": items_lost_count,
		})

# ─────────────────────────────────────────────
# Risiko-Berechnung
# ─────────────────────────────────────────────

## Mitgeführter Wert = Gold + Summe(sell_price × Menge) über das Inventar.
## sell_price=0-Items (z.B. die ADR-038-Scrolls, oder unverkäufliche Items)
## tragen bewusst nichts zum Risiko bei — dieselbe Wert-Quelle wie ShopService.
func _compute_risked_value(player_id: String) -> float:
	var total := float(_currency.get_gold(player_id))
	for item in _inventory.get_all_items(player_id):
		var item_id: String = item.get("id", "")
		var qty: int = item.get("quantity", 0)
		var def: ItemDefinition = _inventory.get_item_info(item_id)
		if def:
			total += float(def.sell_price) * qty
	return total

func _compute_tiered_loss_percent(killer_player_id: String) -> float:
	var risk := _compute_risked_value(killer_player_id)
	for tier in RISK_TIERS:
		if risk >= float(tier[0]):
			return float(tier[1])
	return BELOW_TIER_LOSS_PERCENT

# ─────────────────────────────────────────────
# Anwendung
# ─────────────────────────────────────────────

func _apply_gold_loss(victim_player_id: String, killer_player_id: String, loss_percent: float) -> int:
	var current := _currency.get_gold(victim_player_id)
	var lost := int(round(float(current) * loss_percent))
	if lost <= 0:
		return 0
	if not _currency.request_remove_gold(victim_player_id, lost):
		return 0
	_currency.request_add_gold(killer_player_id, lost)
	return lost

## Iteriert eine SNAPSHOT-Kopie von get_all_items() (Array von Dictionaries,
## nicht die lebenden ItemInstance-Referenzen) — sicher gegen Mutation
## während der eigenen Iteration, da remove_item() weiter unten dieselbe
## darunterliegende Dictionary verändert.
func _apply_item_loss(victim_player_id: String, killer_player_id: String, loss_percent: float) -> Array:
	var lost: Array = []
	for item in _inventory.get_all_items(victim_player_id):
		var item_id: String = item.get("id", "")
		var inst := _inventory.get_item_instance(victim_player_id, item_id)
		if not inst:
			continue

		# Permanente Schutzkategorien (ADR-038): vollständig ausgenommen,
		# in BEIDEN Fällen (geskullt/nicht-geskullt) — siehe Klassenkommentar.
		if inst.is_pve_death_protected or inst.is_theft_protected:
			continue

		# Einmaliger PvP-Schutz: rettet GENAU DIESES Item, wird dabei verbraucht.
		if inst.is_pvp_protected:
			if is_instance_valid(_protection):
				_protection.consume_pvp_protection(victim_player_id, item_id)
			continue

		var qty_lost := int(round(float(inst.quantity) * loss_percent))
		if qty_lost <= 0:
			continue
		if not _inventory.remove_item(item_id, victim_player_id, qty_lost):
			continue
		_inventory.on_item_add_confirmed(item_id, qty_lost, killer_player_id)
		lost.append({"item_id": item_id, "quantity": qty_lost})
	return lost

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true
