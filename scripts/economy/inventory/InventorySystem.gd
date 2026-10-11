extends Service
class_name InventorySystem
## implements ISaveProvider

## InventorySystem — Verwaltet das Spieler-Inventar.
## Abhängigkeiten (deps): ["data", "savesystem", "network_bridge"]
##
## ADR-029 Plan-Schritt 4 (Round 63): State ist per player_id (String,
## stabile Save-Identität / player_uuid) verschachtelt — vorher per_id (int,
## ENet-peer_id). player_id ist jetzt ein PFLICHTPARAMETER ohne Default auf
## jeder öffentlichen Methode: es gibt keinen sinnvollen String-Default (anders
## als der frühere "player_id: int = 1"), und ein vergessener Aufrufer soll
## laut fehlschlagen statt still einen falschen Bucket (Key "") zu befüllen.
## Aufrufer holen sich die player_id über ctx.get_local_player_id() (UI) bzw.
## NetworkBridge.get_player_id_for_peer()/get_local_player_id() (Services).
##
## Auf drei öffentlichen Methoden hat sich dabei auch die Parameter-REIHENFOLGE
## geändert (request_add_item/remove_item/has_item): player_id steht jetzt
## direkt nach item_id, vor dem optionalen quantity — GDScript erlaubt keinen
## Pflichtparameter nach einem Parameter mit Default. get_all_items()/
## get_weight_status()/get_free_slots()/on_item_add_confirmed() hatten player_id
## bereits als einzigen bzw. letzten (nicht-defaulteten) Parameter, dort blieb
## die Reihenfolge unverändert.
##
## Save-Format: { "<player_uuid>": {item_id: qty} } — keine Migration von
## bestehenden "1"/"2"-peer_id-Saves (auf Bestätigung: keine nennenswerten
## Bestandsdaten, siehe ADR-029 "Kein Migrationscode").
##
## ADR-035 Phase 1 (Round 88): bucket["items"] speichert jetzt { item_id:
## ItemInstance } statt { item_id: quantity(int) } — siehe ItemInstance.gd
## Klassenkommentar für den Grund (client-unfälschbare uuid-Referenz für
## TradeService/AuctionHouseService). Der Save-Format-Kommentar oben ist
## dadurch nicht mehr wörtlich exakt: quantity ist jetzt ein Feld INNERHALB
## des serialisierten Item-Dicts (ItemInstance.to_dict()), nicht mehr der
## Wert direkt — SaveMigrationService._migrate_v3_to_v4() konvertiert
## bestehende Saves. Netzwerk-Sync (_on_inventory_state_changed/
## _on_economy_state_received) serialisiert/deserialisiert dieselbe Form,
## da RPC-Payloads keine RefCounted-Objekte tragen können.

signal inventory_changed(player_id: String, items: Array[Dictionary])

const LOG_CAT := "Inventory"
const SAVE_KEY := "inventory"

## Massiv erhöht (Building-Fix): 28 Slots reichten nicht zum vernünftigen Bauen
## (viele Bauteil-Typen + Stapel gleichzeitig im Inventar nötig). Gewichtslimit
## ebenfalls stark angehoben, sonst wird das jetzt zum neuen Flaschenhals.
const DEFAULT_MAX_SLOTS: int = 999
const DEFAULT_MAX_WEIGHT: float = 999999.0

## Multi-Tenant State: { player_id (String): { "items": {item_id: qty}, "weight": float,
##                                             "max_slots": int, "max_weight": float } }
var _players: Dictionary = {}

var _item_registry: Dictionary = {}   # { "item_id": ItemDefinition } — von DataService

var _save_system: SaveSystem
var _network:     NetworkBridge = null
var _bus:         IEventBus     = null

# ─────────────────────────────────────────────
# Interner Helpers: Player-Bucket erstellen / abrufen
# ─────────────────────────────────────────────

func _ensure_player(player_id: String) -> Dictionary:
	if not _players.has(player_id):
		_players[player_id] = {
			"items":      {},  # { item_id: ItemInstance } — ADR-035 Phase 1
			"weight":     0.0,
			"max_slots":  DEFAULT_MAX_SLOTS,
			"max_weight": DEFAULT_MAX_WEIGHT,
		}
	return _players[player_id]

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	var t := AppLogger.log_begin("InventorySystem.configure()", LOG_CAT)

	var data_service := deps.get_optional(ServiceKeys.DATA) as DataService
	if is_instance_valid(data_service):
		_item_registry = data_service.get_all_items()
		AppLogger.log_debug("Item-Registry von DataService: %d Items." % _item_registry.size(), LOG_CAT)
	else:
		AppLogger.log_error("DataService fehlt — Item-Registry leer!" , LOG_CAT)

	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus          = deps.require(ServiceKeys.EVENT_BUS)            as IEventBus
	## R-7 (ADR-022): Test-Harnesses injizieren `network_bridge` häufig direkt
	## über configure() (Tier-1-Testmuster, siehe test_network_bridge.gd), statt
	## über den Late-Inject-Pfad (inject_network_bridge(), Phase C8, siehe dort).
	## _connect_economy_sync() deckt beide Wege ab — idempotent, falls beide je
	## für dieselbe Instanz aufgerufen werden.
	_connect_economy_sync()
	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_end("InventorySystem.configure()", t, LOG_CAT)
	AppLogger.log_info(
		"Initialisiert. %d Items in DB." % _item_registry.size(),
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────

## Phase S8.6 Late-Inject — NetworkBridge wird nach vollem Session-Boot injiziert
## um den zirkulären Dep (NetworkBridge ↔ Services) aufzulösen.
## R-7 (ADR-022): economy_state_received-Verbindung MUSS spätestens hier passieren
## (nicht nur in configure()) — Phase C6 (on_ready) läuft VOR Phase C8 (dieser
## Late-Inject, siehe BootPipeline.boot_character()); im Produktions-Bootpfad ist
## `_network` in configure() (Phase 4) noch null, der Dep ist zirkulär (siehe
## Kommentar oben bei `var _network`). Eine Verbindung nur in on_ready() wäre
## ein stiller No-Op gewesen.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_economy_sync()

## R-7 (ADR-022): gemeinsamer, idempotenter Connect-Helfer für configure() und
## inject_network_bridge() — siehe Kommentare an beiden Aufrufstellen.
func _connect_economy_sync() -> void:
	if is_instance_valid(_network) and not _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.connect(_on_economy_state_received)


func on_ready() -> void:
	# ADR-029 Round 63: kein initialer inventory_changed.emit(1, ...) mehr hier.
	# player_id ist jetzt Pflichtparameter ohne Default, und zum Zeitpunkt von
	# on_ready() (Phase C6) ist _network laut Kommentar oben ohnehin noch immer
	# null (Late-Inject erst Phase C8) — der frühere Emit lief also so oder so
	# IMMER mit dem hartcodierten Platzhalter 1, unabhängig vom tatsächlichen
	# lokalen Spieler. UI-Controller lesen ihren Initialzustand ohnehin selbst
	# über get_all_items(ctx.get_local_player_id()) in ihrem eigenen setup()
	# (siehe InventoryUIController.setup()) — kein Verlust an Funktionalität.
	# Benannte Methode statt Lambda — symmetrisches disconnect() in on_cleanup().
	_bus.world().loot_collected.connect(_on_loot_collected)
	# R-7 (ADR-022): auf JEDER Mutation prüfen ob ein Rücksync an einen entfernten
	# Client nötig ist (Autoritäts-Seite) — zentral hier statt in jeder Mutations-
	# Methode dupliziert (request_add_item/remove_item laufen beide über
	# inventory_changed).
	inventory_changed.connect(_on_inventory_state_changed)

func on_cleanup() -> void:
	if _bus.world().loot_collected.is_connected(_on_loot_collected):
		_bus.world().loot_collected.disconnect(_on_loot_collected)
	if inventory_changed.is_connected(_on_inventory_state_changed):
		inventory_changed.disconnect(_on_inventory_state_changed)
	if is_instance_valid(_network) and _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.disconnect(_on_economy_state_received)
	AppLogger.log_info("InventorySystem cleanup.", LOG_CAT)

## ADR-029 Round 63: Handler für die geteilte EventBus.world().loot_collected-
## Signal — deren Signatur bleibt peer_id: int, weil QuestService
## (noch nicht migriert) denselben Signal-Handler ebenfalls braucht und dessen
## eigener State weiterhin peer_id-verschachtelt ist. Diese Methode ist die
## Grenze, an der die rohe peer_id in die stabile player_id übersetzt wird,
## bevor sie in einen migrierten Service (diesen hier) einfließt — analog zu
## NetworkBridge, das genau das für RPC-Absender tut (siehe
## NetworkBridge._sender_as_player_uuid()-Kommentar).
func _on_loot_collected(item_id: String, qty: int, peer_id: int = 1) -> void:
	var player_uuid := _resolve_player_uuid(peer_id)
	if player_uuid.is_empty():
		return
	request_add_item(item_id, player_uuid, qty)

## Übersetzt eine peer_id in die stabile player_id über NetworkBridge (die
## selbst nur an SessionManager delegiert, siehe dortiger Kommentar). Loggt
## und gibt "" zurück statt zu raten, wenn keine Übersetzung möglich ist
## (kein _network injiziert, oder die peer_id hat noch keinen Slot) — ein
## stiller Fallback würde sonst Items im falschen (oder einem "1"-Legacy-)
## Bucket landen lassen.
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	var player_uuid := _network.get_player_id_for_peer(peer_id)
	if player_uuid.is_empty():
		AppLogger.log_error(
			"_resolve_player_uuid(%d): kein Slot für diese peer_id registriert." % peer_id,
			LOG_CAT
		)
	return player_uuid

## R-7 (ADR-022), Autoritäts-Seite: für jede State-Änderung eines Spielers, der
## nicht dieser Prozess selbst ist, den rohen Bucket (item_id→qty + Gewicht,
## nicht die UI-formatierte `items`-Liste) an dessen Client schicken.
## `send_economy_update_for_player()` verwirft den Aufruf selbst still, wenn
## dieser Prozess keine Autorität ist oder `player_id` der lokale Spieler
## selbst ist — kein zusätzlicher Guard hier nötig.
func _on_inventory_state_changed(player_id: String, _items: Array[Dictionary]) -> void:
	if not is_instance_valid(_network):
		return
	_network.send_economy_update_for_player(player_id, "inventory", _serialize_bucket_for_network(player_id))

## ADR-035 Phase 1: bucket["items"] enthält ItemInstance-Objekte (RefCounted) —
## RPC-Payloads können nur Dictionary/Array/Primitive tragen, .duplicate(true)
## reicht seit dieser Migration nicht mehr (kopiert die Objekt-Referenzen nicht
## in ein übertragbares Format). Nutzt dieselbe ItemInstance.to_dict()-Form wie
## get_save_data() — ein Wire-Format, ein Serialisierungspfad.
func _serialize_bucket_for_network(player_id: String) -> Dictionary:
	var bucket := _ensure_player(player_id)
	var items: Dictionary = bucket["items"]
	var serialized_items: Dictionary = {}
	for item_id in items:
		serialized_items[item_id] = (items[item_id] as ItemInstance).to_dict()
	return {
		"items":      serialized_items,
		"weight":     bucket["weight"],
		"max_slots":  bucket["max_slots"],
		"max_weight": bucket["max_weight"],
	}

## R-7 (ADR-022), Client-Seite: wendet einen von der Autorität gesendeten
## Inventory-Bucket auf den EIGENEN lokalen Player-Bucket an. `payload` ist
## exakt das Format aus `_ensure_player()` (items/weight/max_slots/max_weight) —
## kein separates Wire-Format nötig, da dieselbe Struktur bereits serialisierbar
## ist (String/int/float-Keys und -Werte, keine Node-Referenzen).
func _on_economy_state_received(kind: String, payload: Dictionary) -> void:
	if kind != "inventory":
		return
	if not is_instance_valid(_network):
		return
	var local_id := _network.get_local_player_id()
	if local_id.is_empty():
		return
	# ADR-035 Phase 1: payload["items"] kommt im ItemInstance.to_dict()-Wire-
	# Format an (siehe _serialize_bucket_for_network()) — muss vor dem
	# Übernehmen zurück in ItemInstance-Objekte rekonstruiert werden, kein
	# reines payload.duplicate(true) mehr wie vor der Migration.
	var bucket := _ensure_player(local_id)
	var raw_items: Dictionary = payload.get("items", {})
	var items: Dictionary = {}
	for item_id in raw_items:
		var def: ItemDefinition = _item_registry.get(item_id)
		if not def:
			continue
		var inst := ItemInstance.from_dict(raw_items[item_id] as Dictionary, def)
		if inst:
			items[item_id] = inst
	bucket["items"]      = items
	bucket["weight"]     = payload.get("weight", 0.0)
	bucket["max_slots"]  = payload.get("max_slots", bucket["max_slots"])
	bucket["max_weight"] = payload.get("max_weight", bucket["max_weight"])
	inventory_changed.emit(local_id, get_all_items(local_id))

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	# ADR-035 Phase 1: { player_id: {item_id: ItemInstance.to_dict()} } —
	# ItemInstance ist RefCounted, kein Variant, das SaveSystem direkt
	# schreiben kann, daher explizit über to_dict() serialisiert statt
	# .duplicate() (das würde nur die Dictionary-Hülle kopieren, nicht die
	# Objekt-Inhalte in ein speicherbares Format bringen).
	var out: Dictionary = {}
	for pid in _players:
		var items: Dictionary = (_players[pid] as Dictionary)["items"]
		var serialized: Dictionary = {}
		for item_id in items:
			serialized[item_id] = (items[item_id] as ItemInstance).to_dict()
		out[pid] = serialized
	return out

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Fügt ein Item für player_id hinzu. player_id ist Pflichtparameter (kein
## Default mehr, siehe Klassenkommentar) — steht deshalb vor dem optionalen
## quantity (GDScript erlaubt keinen Pflichtparameter nach einem Default-Param).
## Kein RPC-Zweig mehr (Root-Cause-Fund, siehe TODO-offene-probleme.md "Server
## validiert RPC-Werte nicht", Option A): request_add_item() wird ausschließlich
## authority-seitig aufgerufen (InteractionResolver → _on_loot_collected(),
## RewardDispatcher, EnemyNPC._die() — alle bereits hinter is_multiplayer_authority()-
## Guards), nie von einem Client, der selbst eine quantity über das Netz senden will.
func request_add_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
	var def := get_item_info(item_id)
	if not def:
		AppLogger.log_error("Item-ID '%s' unbekannt." % item_id, LOG_CAT)
		return false

	var bucket := _ensure_player(player_id)
	var items: Dictionary = bucket["items"]
	var max_slots: int    = bucket["max_slots"]
	var max_weight: float = bucket["max_weight"]
	var cur_weight: float = bucket["weight"]

	if not items.has(item_id) and items.size() >= max_slots:
		AppLogger.log_warn(
			"Inventar voll (%d/%d Slots, Spieler '%s') — '%s' abgelehnt." % [items.size(), max_slots, player_id, item_id],
			LOG_CAT
		)
		return false

	if max_weight > 0.0:
		var item_weight: float = def.get("weight") if def.get("weight") != null else 0.0
		if cur_weight + item_weight * quantity > max_weight:
			AppLogger.log_warn(
				"Gewichtslimit (%.1f/%.1f kg, Spieler '%s') — '%s' abgelehnt." % [cur_weight, max_weight, player_id, item_id],
				LOG_CAT
			)
			return false

	on_item_add_confirmed(item_id, quantity, player_id)
	return true

## Authority-Mutation: schreibt State für player_id. Wird von request_add_item() aufgerufen
## (kein NetworkBridge._rpc_add_item() mehr — entfernt, siehe request_add_item()-Kommentar).
## C-02: Guard stellt sicher dass nur die Autorität State mutiert — auch bei Direktaufruf
## ohne NetworkBridge (z.B. serverseitiger Code, Cheats, Admin-Tools). Bleibt als
## Verteidigung in der Tiefe bestehen, falls künftiger Code diese Methode je aus
## Nicht-Autoritäts-Kontext aufruft.
##
## ADR-010 Round 55 (Tier 3 — "Server vertraut niemandem"): Slot-/Gewichtslimit
## werden HIER erneut geprüft, nicht nur in request_add_item(). Stand heute gibt
## es keinen bekannten Aufrufer, der diese Methode mit einer Menge erreicht, die
## request_add_item() nicht bereits geprüft hat (verifiziert: einziger Aufrufer
## ist request_add_item() selbst, siehe dessen Kommentar — kein `_rpc_add_item`
## mehr seit Round 45). Der frühere MIGRATION-010-Eintrag "fehlende serverseitige
## Re-Validierung" beschrieb exakt diesen jetzt nicht mehr existierenden RPC-Pfad
## und war seit Round 45 stale (siehe MIGRATION-010.md "Korrektur Round 55").
## Die Prüfung hier ist trotzdem kein Leerlauf, sondern dasselbe
## Verteidigung-in-der-Tiefe-Prinzip wie der C-02-Guard direkt darüber: Tier 3
## validiert an der Mutationsstelle selbst, nicht nur an einer Caller-Konvention,
## die künftiger Code brechen könnte, ohne dass es hier auffiele.
func on_item_add_confirmed(item_id: String, quantity: int, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_item_add_confirmed: Aufruf auf Nicht-Autorität (peer %d) — verweigert." % _network.get_local_peer_id(),
			LOG_CAT
		)
		return
	var def := get_item_info(item_id)
	if not def:
		return

	var bucket := _ensure_player(player_id)
	var items: Dictionary = bucket["items"]

	if not items.has(item_id) and items.size() >= (bucket["max_slots"] as int):
		AppLogger.log_error(
			"on_item_add_confirmed: Slotlimit (%d/%d, Spieler '%s') — '%s' verweigert. Aufrufer hat request_add_item()s Vorprüfung umgangen." % [
				items.size(), bucket["max_slots"], player_id, item_id
			],
			LOG_CAT
		)
		return

	var item_weight_check: float = def.get("weight") if def.get("weight") != null else 0.0
	var max_weight: float = bucket["max_weight"]
	if max_weight > 0.0 and (bucket["weight"] as float) + item_weight_check * quantity > max_weight:
		AppLogger.log_error(
			"on_item_add_confirmed: Gewichtslimit (%.1f/%.1f kg, Spieler '%s') — '%s' verweigert. Aufrufer hat request_add_item()s Vorprüfung umgangen." % [
				bucket["weight"], max_weight, player_id, item_id
			],
			LOG_CAT
		)
		return

	var inst: ItemInstance = items.get(item_id)
	var current: int = inst.quantity if inst else 0
	var new_qty: int = min(current + quantity, def.max_stack)
	var actual_added: int = new_qty - current

	if inst:
		inst.quantity = new_qty
	else:
		# ADR-035 Phase 1: neue ItemInstance mit frisch vergebener uuid — dieser
		# Pfad läuft ausschließlich autoritätsseitig (Guard oben in dieser
		# Methode), die uuid ist damit netzwerkweit vertrauenswürdig vergeben.
		items[item_id] = ItemInstance.new(def, new_qty)

	var item_weight: float = def.get("weight") if def.get("weight") != null else 0.0
	bucket["weight"] = (bucket["weight"] as float) + item_weight * actual_added

	inventory_changed.emit(player_id, get_all_items(player_id))
	AppLogger.log_debug(
		"Item hinzugefügt: '%s' x%d für Spieler '%s'. Gewicht: %.1f/%.1f kg, Slots: %d/%d."
		% [item_id, actual_added, player_id,
		   bucket["weight"], bucket["max_weight"],
		   items.size(),     bucket["max_slots"]],
		LOG_CAT
	)

## player_id ist Pflichtparameter (kein Default mehr) — steht deshalb vor dem
## optionalen quantity, siehe Klassenkommentar.
func remove_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
	var bucket := _ensure_player(player_id)
	var items: Dictionary = bucket["items"]
	var inst: ItemInstance = items.get(item_id)
	var current: int = inst.quantity if inst else 0
	if current < quantity:
		AppLogger.log_warn("Zu wenig '%s' (Spieler '%s', Besitz: %d)." % [item_id, player_id, current], LOG_CAT)
		return false

	# inst kann hier nur null sein, wenn quantity <= 0 auf ein nie besessenes
	# Item aufgerufen wird (current=0, 0 < quantity ist dann false) — kein
	# Zustand zu mutieren, aber auch kein Crash (vorher: dict-Autovivify+erase,
	# gleiches No-Op-Verhalten nach außen).
	if inst:
		inst.quantity = current - quantity
		if inst.quantity <= 0:
			items.erase(item_id)

	var def: ItemDefinition = _item_registry.get(item_id)
	var item_weight: float = def.get("weight") if def and def.get("weight") != null else 0.0
	bucket["weight"] = max(0.0, (bucket["weight"] as float) - item_weight * quantity)

	inventory_changed.emit(player_id, get_all_items(player_id))
	return true

## player_id ist Pflichtparameter (kein Default mehr) — steht deshalb vor dem
## optionalen quantity, siehe Klassenkommentar.
func has_item(item_id: String, player_id: String, quantity: int = 1) -> bool:
	var inst: ItemInstance = (_players.get(player_id, {}) as Dictionary).get("items", {}).get(item_id)
	return inst != null and inst.quantity >= quantity

## BUGFIX (2026-09-25, "PvE-Schutz-Scroll überlebt Equip/Unequip nicht"): das
## Gegenstück zu remove_item() für den Equip/Unequip-Rückbau in
## EquipmentService — fügt eine bereits VORHANDENE ItemInstance unverändert
## wieder ein, statt wie request_add_item()/on_item_add_confirmed() bei Bedarf
## eine neue zu erzeugen. Eine neue Instanz hätte is_pve_death_protected/
## is_theft_protected/is_pvp_protected/durability/uuid wieder auf Default —
## ein per Scroll geschütztes Item würde seinen Schutz beim ersten
## Anlegen+Ablegen stillschweigend verlieren (genau das gemeldete Symptom:
## Scroll angewendet, Waffe trotzdem beim PvE-Tod verloren). Kein
## Slot-/Gewichtslimit-Check nötig — das Item war bis unmittelbar vor dem
## Equip exakt in diesem Bestand, die Kapazität war also bereits belegt und
## wird durch die Rückgabe nur wiederhergestellt, nicht neu beansprucht.
func restore_item_instance(player_id: String, inst: ItemInstance) -> void:
	if not is_instance_valid(inst):
		return
	var bucket := _ensure_player(player_id)
	var items: Dictionary = bucket["items"]
	var item_id := inst.get_id()
	if item_id.is_empty():
		return
	var def: ItemDefinition = _item_registry.get(item_id)
	var existing: ItemInstance = items.get(item_id)
	if is_instance_valid(existing) and existing != inst:
		# Inzwischen wieder ein (anderes) Exemplar desselben Item-Typs im
		# Inventar (z.B. während des Equips neu aufgesammelt) — Menge
		# zusammenführen statt die eine der beiden Instanzen stillschweigend
		# zu verwerfen. `existing` bleibt maßgeblich (bereits im Bestand),
		# `inst`s Schutz/Zustand geht in diesem Rand-Fall unter — dieselbe
		# bekannte Einschränkung wie "eine ItemInstance pro item_id pro
		# Spieler" generell (siehe ItemInstance-Klassenkommentar).
		var cap: int = def.max_stack if def else (existing.quantity + inst.quantity)
		existing.quantity = min(existing.quantity + inst.quantity, cap)
	else:
		items[item_id] = inst

	var item_weight: float = def.get("weight") if def and def.get("weight") != null else 0.0
	bucket["weight"] = (bucket["weight"] as float) + item_weight * inst.quantity

	inventory_changed.emit(player_id, get_all_items(player_id))
	AppLogger.log_debug(
		"Instanz zurückgegeben: '%s' (uuid=%s, geschützt=pve:%s/theft:%s/pvp:%s) für Spieler '%s'."
		% [item_id, inst.uuid, inst.is_pve_death_protected, inst.is_theft_protected, inst.is_pvp_protected, player_id],
		LOG_CAT
	)

func get_all_items(player_id: String) -> Array:
	var bucket: Dictionary = _players.get(player_id, {})
	var items: Dictionary  = (bucket.get("items", {}) as Dictionary)
	var result: Array[Dictionary] = []
	for item_id in items:
		var inst: ItemInstance = items[item_id]
		var def: ItemDefinition = _item_registry.get(item_id)
		result.append(
			{
				"id":       item_id,
				"name":     def.display_name if def else item_id,
				"quantity": inst.quantity,
				"icon":     def.icon if def else null,
				"weight":   def.get("weight") if def and def.get("weight") != null else 0.0,
				"uuid":     inst.uuid,  # ADR-035 Phase 1: für Trade/Auktionshaus-Referenzen
			}
		)
	return result

## ADR-035 Phase 1: Zugriff auf die rohe ItemInstance (mit uuid) für Services,
## die eine autoritäts-vertrauenswürdige Item-Referenz brauchen (Trade,
## Auktionshaus). null wenn player_id/item_id keinen Bestand hat.
func get_item_instance(player_id: String, item_id: String) -> ItemInstance:
	return (_players.get(player_id, {}) as Dictionary).get("items", {}).get(item_id)

func get_weight_status(player_id: String) -> Dictionary:
	var bucket: Dictionary = _players.get(player_id, {"weight": 0.0, "max_weight": DEFAULT_MAX_WEIGHT})
	return {"current": bucket.get("weight", 0.0), "max": bucket.get("max_weight", DEFAULT_MAX_WEIGHT)}

func get_free_slots(player_id: String) -> int:
	var bucket: Dictionary = _players.get(player_id, {"items": {}, "max_slots": DEFAULT_MAX_SLOTS})
	var items: Dictionary  = bucket.get("items", {})
	return max(0, (bucket.get("max_slots", DEFAULT_MAX_SLOTS) as int) - items.size())

func get_item_info(item_id: String) -> ItemDefinition:
	return _item_registry.get(item_id)

## Für Debug-/Admin-Tooling (siehe AdminPanelUI._build_item_row()): das
## komplette Item-Katalog ({ item_id: ItemDefinition }), damit ein Dropdown
## alle bekannten Items anzeigen kann, statt dass admins sich item_ids
## merken müssen. Kopie — Aufrufer dürfen die Registry nicht mutieren.
func get_all_item_definitions() -> Dictionary:
	return _item_registry.duplicate()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _restore_from_save(saved: Dictionary) -> void:
	# Format: { "<player_uuid>": {item_id: {item_id, quantity, uuid, durability}}, ... }
	# — keine int()-Konvertierung mehr für player_id (Keys sind bereits die
	# player_id-Strings selbst, siehe ADR-029). ADR-035 Phase 1: item_id-Werte
	# sind jetzt ItemInstance.to_dict()-Form statt roher int — SaveMigrationService
	# ._migrate_v3_to_v4() konvertiert ältere Saves vor Ankunft hier. Ein rohes
	# int trifft hier defensiv trotzdem noch ab (z.B. direkte Testaufrufe ohne
	# Migrationspfad, siehe test_inventory_system.gd Round-Trip-Tests).
	for pid in saved:
		var raw: Dictionary = saved[pid] as Dictionary if saved[pid] is Dictionary else {}
		var bucket := _ensure_player(pid)
		for item_id in raw:
			var def: ItemDefinition = _item_registry.get(item_id)
			if not def:
				continue
			var entry: Variant = raw[item_id]
			var inst: ItemInstance
			if entry is Dictionary:
				inst = ItemInstance.from_dict(entry as Dictionary, def)
			else:
				inst = ItemInstance.new(def, int(entry))
			if inst:
				bucket["items"][item_id] = inst
