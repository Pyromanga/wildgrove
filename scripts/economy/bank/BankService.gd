extends Service
class_name BankService

## BankService — ADR-034: sicherer, vom Inventar getrennter Lagerort für
## Items und Gold. Option B aus der ADR: eigenständiges Schema statt
## "zweites Inventar", damit PvP-Tod (ADR-036) und Diebstahl (ADR-039) nur
## das mitgeführte Inventar/Gold treffen können, nie eingelagerte Bestände.
##
## Muster identisch zu InventorySystem/CurrencyService (ADR-004/033):
## Absicht statt Wert — request_*() prüft/routet, on_*_confirmed() mutiert
## NUR auf der Autorität. Kein automatischer Zugriff zwischen Inventar und
## Bank — jede Bewegung ist ein expliziter, spielerausgelöster Ein-/Auszahl-
## Vorgang über eine Bank-NPC-Interaktion (ADR-020), analog ShopService
## (Round 88) für Kauf/Verkauf.
##
## Netzwerk-Routing bewusst SELBST übernommen (wie ShopService, NICHT wie
## InventorySystem/CurrencyService seit deren Root-Cause-Fix Round 45) — der
## Grund ist identisch: die UI läuft auf dem Peer des einlagernden Spielers,
## nicht zwingend der Autorität.

## ADR-050 Phase 2 (Round 112): die drei nativen Signale, die hier vorher
## standen (deposit_completed/withdraw_completed/transaction_failed), sind
## nach scripts/economy/bank/BankEvents.gd (EventBus-Namespace `bank`)
## migriert — beide externen Konsumenten (BankUIController,
## AuctionHouseUIController) holten sich diese Instanz ohnehin per DI, kein
## lokaler Node-Subtree-Connect blieb übrig, der ein natives Signal
## rechtfertigen würde (siehe ADR-050 Zielarchitektur). `transaction_failed`
## hieß dort außerdem identisch wie auf AuctionHouseService/TradeService/
## ShopService (ADR-050 Phase 1, Round 111 aufgelöst) — jetzt eindeutig
## `bank_transaction_failed`.

const LOG_CAT := "Bank"
const SAVE_KEY := "bank"
const KIND_ITEM := "item"
const KIND_GOLD := "gold"

var _inventory:   InventorySystem = null
var _currency:    CurrencyService = null
var _data:        DataService     = null
var _network:     NetworkBridge   = null
var _save_system: SaveSystem      = null
var _bus:         IEventBus       = null

## player_id -> {item_id: ItemInstance} — ADR-035 Phase 1 (Round 88): war
## vorher {item_id: quantity(int)}, siehe ItemInstance.gd Klassenkommentar
## für den Grund (Trade/Auktionshaus brauchen eine client-unfälschbare
## uuid-Referenz, analog InventorySystem). Eigene, frisch vergebene uuid-
## Identität je Bank-Bucket-Eintrag — beim Ein-/Auszahlen wird aktuell NICHT
## die uuid der Inventar-Instanz übernommen (Bank und Inventar sind zwei
## getrennte Identitätsräume in dieser Phase); Identitäts-Erhalt über die
## Container-Grenze hinweg wäre ein separater Folgeschritt, nur relevant
## sobald es tatsächlich unterscheidbare (z.B. stat-gewürfelte) Items gibt.
var _items: Dictionary = {}
## player_id -> int
var _gold: Dictionary = {}

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory   = deps.require(ServiceKeys.INVENTORY)      as InventorySystem
	_currency    = deps.require(ServiceKeys.CURRENCY)       as CurrencyService
	_data        = deps.require(ServiceKeys.DATA)            as DataService
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem
	_bus         = deps.get_optional(ServiceKeys.EVENT_BUS)       as IEventBus

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved as Dictionary)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("BankService initialisiert.", LOG_CAT)

## Phase C8 Late-Inject (siehe BootPipeline.gd).
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage
# ─────────────────────────────────────────────

func get_bank_gold(player_id: String) -> int:
	return int(_gold.get(player_id, 0))

## Gleiche Rückgabeform wie InventorySystem.get_all_items(): [{id, name, quantity, uuid}, ...]
func get_bank_items(player_id: String) -> Array:
	var items: Dictionary = _items.get(player_id, {})
	var result: Array[Dictionary] = []
	for item_id in items:
		var inst: ItemInstance = items[item_id]
		var def: ItemDefinition = _data.get_item(item_id) if is_instance_valid(_data) else null
		result.append({
			"id": item_id,
			"name": def.display_name if is_instance_valid(def) else item_id,
			"quantity": inst.quantity,
			"uuid": inst.uuid,  # ADR-035 Phase 1
		})
	return result

## ADR-035 Phase 1: Zugriff auf die rohe ItemInstance (mit uuid) — Gegenstück
## zu InventorySystem.get_item_instance(), für Services die eine autoritäts-
## vertrauenswürdige Referenz auf ein eingelagertes Item brauchen.
func get_bank_item_instance(player_id: String, item_id: String) -> ItemInstance:
	return (_items.get(player_id, {}) as Dictionary).get(item_id)

# ─────────────────────────────────────────────
# Öffentliche API — Item-Einzahlung/Abhebung
# ─────────────────────────────────────────────

func request_deposit_item(player_id: String, item_id: String, quantity: int = 1) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_bank_deposit_item(item_id, quantity, player_id)
	else:
		on_deposit_item_confirmed(item_id, quantity, player_id)

func on_deposit_item_confirmed(item_id: String, quantity: int, player_id: String) -> void:
	if not _require_authority("on_deposit_item_confirmed"):
		return
	if quantity <= 0:
		_fail(player_id, "invalid_quantity")
		return
	if not is_instance_valid(_inventory) or not _inventory.has_item(item_id, player_id, quantity):
		_fail(player_id, "item_not_owned")
		return
	# ADR-035 Phase 1: def-Lookup VOR remove_item() — sonst würde ein fehlender
	# DataService-Eintrag (sollte praktisch nie vorkommen, siehe unten) das Item
	# aus dem Inventar entfernen, ohne es der Bank gutzuschreiben (Item-Verlust).
	var bucket: Dictionary = _items.get(player_id, {})
	var existing_inst: ItemInstance = bucket.get(item_id)
	var def: ItemDefinition = _data.get_item(item_id) if is_instance_valid(_data) else null
	if not existing_inst and not def:
		# Sollte nicht passieren: Item ist laut has_item() im Inventar vorhanden,
		# war also beim Hinzufügen dort bereits gegen dieselbe Registry geprüft.
		AppLogger.log_error("on_deposit_item_confirmed: '%s' hat keine ItemDefinition in DataService." % item_id, LOG_CAT)
		_fail(player_id, "unknown_item")
		return
	if not _inventory.remove_item(item_id, player_id, quantity):
		_fail(player_id, "item_not_owned")
		return

	if existing_inst:
		existing_inst.quantity += quantity
	else:
		bucket[item_id] = ItemInstance.new(def, quantity)
	_items[player_id] = bucket

	_emit_deposit(player_id, KIND_ITEM, item_id, quantity)
	AppLogger.log_debug("Einzahlung: '%s' legt %dx '%s' in die Bank." % [player_id, quantity, item_id], LOG_CAT)

func request_withdraw_item(player_id: String, item_id: String, quantity: int = 1) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_bank_withdraw_item(item_id, quantity, player_id)
	else:
		on_withdraw_item_confirmed(item_id, quantity, player_id)

func on_withdraw_item_confirmed(item_id: String, quantity: int, player_id: String) -> void:
	if not _require_authority("on_withdraw_item_confirmed"):
		return
	if quantity <= 0:
		_fail(player_id, "invalid_quantity")
		return

	var bucket: Dictionary = _items.get(player_id, {})
	var inst: ItemInstance = bucket.get(item_id)
	var have: int = inst.quantity if inst else 0
	if have < quantity:
		_fail(player_id, "item_not_in_bank")
		return

	if not is_instance_valid(_inventory) or not _inventory.request_add_item(item_id, player_id, quantity):
		_fail(player_id, "inventory_full")
		return

	if have == quantity:
		bucket.erase(item_id)
	else:
		inst.quantity = have - quantity
	_items[player_id] = bucket

	_emit_withdraw(player_id, KIND_ITEM, item_id, quantity)
	AppLogger.log_debug("Abhebung: '%s' nimmt %dx '%s' aus der Bank." % [player_id, quantity, item_id], LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API — Gold-Einzahlung/Abhebung
# ─────────────────────────────────────────────

func request_deposit_gold(player_id: String, amount: int) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_bank_deposit_gold(amount, player_id)
	else:
		on_deposit_gold_confirmed(amount, player_id)

func on_deposit_gold_confirmed(amount: int, player_id: String) -> void:
	if not _require_authority("on_deposit_gold_confirmed"):
		return
	if amount <= 0:
		_fail(player_id, "invalid_amount")
		return
	if not is_instance_valid(_currency) or not _currency.has_gold(player_id, amount):
		_fail(player_id, "insufficient_gold")
		return
	if not _currency.request_remove_gold(player_id, amount):
		_fail(player_id, "insufficient_gold")
		return

	_gold[player_id] = int(_gold.get(player_id, 0)) + amount
	_emit_deposit(player_id, KIND_GOLD, "gold", amount)
	AppLogger.log_debug("Einzahlung: '%s' legt %d Gold in die Bank." % [player_id, amount], LOG_CAT)

func request_withdraw_gold(player_id: String, amount: int) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_bank_withdraw_gold(amount, player_id)
	else:
		on_withdraw_gold_confirmed(amount, player_id)

func on_withdraw_gold_confirmed(amount: int, player_id: String) -> void:
	if not _require_authority("on_withdraw_gold_confirmed"):
		return
	if amount <= 0:
		_fail(player_id, "invalid_amount")
		return
	var have: int = int(_gold.get(player_id, 0))
	if have < amount:
		_fail(player_id, "insufficient_bank_gold")
		return

	# Gold zuerst aus der Bank abbuchen — schlägt request_add_gold() aus
	# irgendeinem Grund fehl (z.B. MAX_GOLD-Overflow beim Spieler), sofort
	# zurückbuchen statt den Spieler zu bestehlen (gleiches Rollback-Muster
	# wie ShopService.on_buy_confirmed()).
	_gold[player_id] = have - amount
	if not is_instance_valid(_currency) or not _currency.request_add_gold(player_id, amount):
		_gold[player_id] = have  # Rollback
		_fail(player_id, "withdraw_failed")
		return

	_emit_withdraw(player_id, KIND_GOLD, "gold", amount)
	AppLogger.log_debug("Abhebung: '%s' nimmt %d Gold aus der Bank." % [player_id, amount], LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API — Auktionshaus-Escrow (ADR-035)
# ─────────────────────────────────────────────

## Entnimmt ein Item aus der Bank für ein Auktionshaus-Listing — anders als
## on_withdraw_item_confirmed() geht es NICHT zurück ins Inventar, sondern in
## AuctionHouseService._listings (Escrow). Nur für AuctionHouseService gedacht.
func remove_item_for_listing(player_id: String, item_id: String, quantity: int) -> bool:
	if not _require_authority("remove_item_for_listing"):
		return false
	var bucket: Dictionary = _items.get(player_id, {})
	var inst: ItemInstance = bucket.get(item_id)
	var have: int = inst.quantity if inst else 0
	if have < quantity:
		return false
	if have == quantity:
		bucket.erase(item_id)
	else:
		inst.quantity = have - quantity
	_items[player_id] = bucket
	return true

## Gegenstück — Rückgabe eines stornierten Auktionshaus-Listings, dessen
## Quelle laut AuctionHouseService die Bank war (siehe dortiges "source"-Feld).
func add_item_to_bank(player_id: String, item_id: String, quantity: int, def: ItemDefinition) -> void:
	if not _require_authority("add_item_to_bank"):
		return
	var bucket: Dictionary = _items.get(player_id, {})
	var inst: ItemInstance = bucket.get(item_id)
	if inst:
		inst.quantity += quantity
	else:
		bucket[item_id] = ItemInstance.new(def, quantity)
	_items[player_id] = bucket

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _fail(player_id: String, reason: String) -> void:
	if is_instance_valid(_bus):
		_bus.bank().emit_bank_transaction_failed(player_id, reason)

func _emit_deposit(player_id: String, kind: String, id: String, amount: int) -> void:
	if is_instance_valid(_bus):
		_bus.bank().emit_bank_transaction_deposit_completed(player_id, kind, id, amount)

func _emit_withdraw(player_id: String, kind: String, id: String, amount: int) -> void:
	if is_instance_valid(_bus):
		_bus.bank().emit_bank_transaction_withdrawal_completed(player_id, kind, id, amount)

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

# ─────────────────────────────────────────────
# Save-Interface (analog CurrencyService/ADR-033)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	# ADR-035 Phase 1: _items enthält jetzt ItemInstance-Objekte — analog
	# InventorySystem.get_save_data() über to_dict() serialisiert, kein
	# direktes Durchreichen von _items mehr möglich (RefCounted, kein Variant
	# das SaveSystem schreiben kann).
	var serialized_items: Dictionary = {}
	for pid in _items:
		var bucket: Dictionary = _items[pid]
		var s: Dictionary = {}
		for item_id in bucket:
			s[item_id] = (bucket[item_id] as ItemInstance).to_dict()
		serialized_items[pid] = s
	return {"items": serialized_items, "gold": _gold}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("gold") is Dictionary:
		_gold = saved["gold"]
	if saved.get("items") is Dictionary:
		var raw_items: Dictionary = saved["items"]
		for pid in raw_items:
			var raw_bucket: Dictionary = raw_items[pid] as Dictionary if raw_items[pid] is Dictionary else {}
			var bucket: Dictionary = {}
			for item_id in raw_bucket:
				var def: ItemDefinition = _data.get_item(item_id) if is_instance_valid(_data) else null
				if not def:
					continue
				var entry: Variant = raw_bucket[item_id]
				var inst: ItemInstance = ItemInstance.from_dict(entry as Dictionary, def) if entry is Dictionary else ItemInstance.new(def, int(entry))
				if inst:
					bucket[item_id] = inst
			_items[pid] = bucket
