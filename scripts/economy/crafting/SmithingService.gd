extends Service
class_name SmithingService

## SmithingService — Schmelzen & Schmieden an Hochofen und Amboss.
##
## Führt datengetriebene SmithingRecipe-Rezepte aus (data/smithing_recipes/): Zutaten aus dem
## Inventar verbrauchen, Ergebnis ins Inventar legen, Skill-XP im Skill "smithing" vergeben.
## Dasselbe request_/on_*_confirmed-Muster wie ShopService (ADR-004): request_craft() ist BEWUSST
## client-aufrufbar (das Panel läuft auf dem Peer des handelnden Spielers) und routet auf einem
## entfernten Client per RPC (NetworkBridge.send_smithing_craft()) an die Autorität; die
## Mutation selbst (on_craft_confirmed()) läuft ausschließlich dort und prüft ALLES erneut.
##
## STATIONS-ZUGANG (die eigentliche Verzahnung mit dem Bausystem):
## Ein Rezept gehört zu einer Station (SmithingRecipe.station). Damit ein Client den Craft-RPC
## nicht ohne Ofen/Amboss "aus der Ferne" auslösen kann, verlangt on_craft_confirmed() einen
## frischen Zugang: BuildPiece meldet auf der Autorität jede Benutzung einer Station
## (SmithingEvents.smithing_station_used), der Service merkt sich den Zeitpunkt pro Spieler und
## Station und lässt Rezepte nur STATION_ACCESS_SEC danach zu. Die Station kommt dabei aus dem
## REZEPT, nie aus der Anfrage — ein Amboss-Rezept lässt sich nicht "am Hochofen" auslösen.
## Zeitquelle ist Time.get_ticks_msec() (monoton), austauschbar über `clock` für Tests.
##
## Werkzeuge (SmithingRecipe.required_tools) werden NICHT verbraucht; sie müssen im Inventar
## ODER im Werkzeug-Slot ausgerüstet sein.

const LOG_CAT := "Smithing"
const SKILL_ID := "smithing"

## Wie lange nach dem Benutzen einer Station deren Rezepte ausführbar bleiben (Sekunden). Großzügig
## genug fürs Durchklicken mehrerer Rezepte, kurz genug, dass "einmal Ofen berühren, dann überall
## schmieden" nicht funktioniert.
const STATION_ACCESS_SEC := 180.0

## Obergrenze für eine Sammel-Herstellung (ein Request = bis zu N Durchläufe desselben Rezepts).
const MAX_BATCH := 20

# Fehlgrund-Codes — gleiche Strings wie in SmithingEvents.smithing_craft_failed dokumentiert.
const FAIL_UNKNOWN_RECIPE := "unknown_recipe"
const FAIL_INVALID_PLAYER := "invalid_player"
const FAIL_LEVEL_TOO_LOW := "level_too_low"
const FAIL_MISSING_TOOL := "missing_tool"
const FAIL_MISSING_INGREDIENTS := "missing_ingredients"
const FAIL_INVENTORY_FULL := "inventory_full"
const FAIL_INVALID_QUANTITY := "invalid_quantity"
const FAIL_NO_STATION := "no_station"

var _inventory: InventorySystem = null
var _skills: SkillSystem = null
var _equipment: EquipmentService = null
var _data: DataService = null
var _network: NetworkBridge = null
var _bus: IEventBus = null

## { player_id: { station_kind: ticks_msec der letzten Benutzung } }
var _station_access: Dictionary = {}

## Zeitquelle in Millisekunden. Tests ersetzen sie, statt echte Zeit verstreichen zu lassen.
var clock: Callable = Callable()

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory = deps.require(ServiceKeys.INVENTORY) as InventorySystem
	_skills = deps.require(ServiceKeys.SKILL_SYSTEM) as SkillSystem
	_data = deps.require(ServiceKeys.DATA) as DataService
	_equipment = deps.get_optional(ServiceKeys.EQUIPMENT) as EquipmentService
	_network = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_bus = deps.get_optional(ServiceKeys.EVENT_BUS) as IEventBus
	AppLogger.log_info("SmithingService initialisiert (%d Rezepte)." % _data.get_all_smithing_recipes().size(), LOG_CAT)

func on_ready() -> void:
	if is_instance_valid(_bus):
		var events := _bus.smithing()
		if is_instance_valid(events) and not events.smithing_station_used.is_connected(grant_station_access):
			events.smithing_station_used.connect(grant_station_access)

func on_cleanup() -> void:
	if is_instance_valid(_bus):
		var events := _bus.smithing()
		if is_instance_valid(events) and events.smithing_station_used.is_connected(grant_station_access):
			events.smithing_station_used.disconnect(grant_station_access)
	_station_access.clear()

## Phase C8 Late-Inject (siehe BootPipeline.gd).
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Stations-Zugang
# ─────────────────────────────────────────────

## Merkt sich, dass player_id gerade station_kind benutzt hat. Läuft über das EventBus-Signal
## smithing_station_used (nur Autorität emittiert es), ist aber auch direkt aufrufbar.
func grant_station_access(player_id: String, station_kind: String) -> void:
	if player_id.is_empty() or not SmithingRecipe.STATIONS.has(station_kind):
		return
	var per_player: Dictionary = _station_access.get(player_id, {})
	per_player[station_kind] = _now_msec()
	_station_access[player_id] = per_player

## Hat player_id station_kind innerhalb von STATION_ACCESS_SEC benutzt?
func has_station_access(player_id: String, station_kind: String) -> bool:
	var per_player: Dictionary = _station_access.get(player_id, {})
	if not per_player.has(station_kind):
		return false
	var age_sec: float = float(_now_msec() - int(per_player[station_kind])) / 1000.0
	return age_sec <= STATION_ACCESS_SEC

## Entzieht den Zugang (z.B. wenn der Spieler das Panel schließt/die Session verlässt).
func revoke_station_access(player_id: String) -> void:
	_station_access.erase(player_id)

func _now_msec() -> int:
	if clock.is_valid():
		return int(clock.call())
	return Time.get_ticks_msec()

# ─────────────────────────────────────────────
# Abfragen (reine Lesezugriffe — von UI und Tests genutzt)
# ─────────────────────────────────────────────

func get_recipes_for_station(station_kind: String) -> Array[SmithingRecipe]:
	return _data.get_smithing_recipes_for_station(station_kind)

## Warum ist das Rezept für diesen Spieler JETZT nicht ausführbar? "" = ausführbar.
## Prüft Rezept, Level, Werkzeuge und Zutaten (für `quantity` Durchläufe) — NICHT den Stations-
## zugang und NICHT den Inventarplatz: Ersterer ist Sache der Autorität (on_craft_confirmed()),
## Letzterer zeigt sich erst beim tatsächlichen Einlagern. Die UI nutzt das für ausgegraute Zeilen.
func get_block_reason(player_id: String, recipe_id: String, quantity: int = 1) -> String:
	if player_id.is_empty():
		return FAIL_INVALID_PLAYER
	var recipe: SmithingRecipe = _data.get_smithing_recipe(recipe_id)
	if recipe == null:
		return FAIL_UNKNOWN_RECIPE
	if quantity <= 0 or quantity > MAX_BATCH:
		return FAIL_INVALID_QUANTITY
	if _skills.get_level(recipe.skill_id, player_id) < recipe.min_level:
		return FAIL_LEVEL_TOO_LOW
	for tool_id in recipe.required_tools:
		if not _has_tool(player_id, tool_id):
			return FAIL_MISSING_TOOL
	for item_id in recipe.inputs:
		if not _inventory.has_item(String(item_id), player_id, int(recipe.inputs[item_id]) * quantity):
			return FAIL_MISSING_INGREDIENTS
	return ""

func can_craft(player_id: String, recipe_id: String, quantity: int = 1) -> bool:
	return get_block_reason(player_id, recipe_id, quantity).is_empty()

func _has_tool(player_id: String, tool_id: String) -> bool:
	if _inventory.has_item(tool_id, player_id, 1):
		return true
	if is_instance_valid(_equipment):
		var equipped: ItemDefinition = _equipment.get_equipped(EquipmentService.SLOT_TOOL, player_id)
		if is_instance_valid(equipped) and equipped.id == tool_id:
			return true
	return false

# ─────────────────────────────────────────────
# Herstellen
# ─────────────────────────────────────────────

## Absicht: Rezept ausführen. Auf einem entfernten Client (Tier 2/3) per RPC an die Autorität,
## in Solo/auf der Autorität direkt synchron.
func request_craft(player_id: String, recipe_id: String, quantity: int = 1) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_smithing_craft(recipe_id, quantity, player_id)
	else:
		on_craft_confirmed(recipe_id, quantity, player_id)

## Autoritäts-Mutation. Prüft erneut alles (ADR-010 Tier-3-Prinzip) und rollt bei einem Fehler
## beim Einlagern des Ergebnisses die bereits verbrauchten Zutaten zurück.
func on_craft_confirmed(recipe_id: String, quantity: int, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("on_craft_confirmed: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT)
		return

	var reason := get_block_reason(player_id, recipe_id, quantity)
	if not reason.is_empty():
		_fail(player_id, recipe_id, reason)
		return

	var recipe: SmithingRecipe = _data.get_smithing_recipe(recipe_id)
	if not has_station_access(player_id, recipe.station):
		_fail(player_id, recipe_id, FAIL_NO_STATION)
		return

	# Zutaten verbrauchen — bei einem Fehlschlag mittendrin alles bisher Entnommene zurückgeben.
	var consumed: Dictionary = {}
	for item_id in recipe.inputs:
		var amount: int = int(recipe.inputs[item_id]) * quantity
		if not _inventory.remove_item(String(item_id), player_id, amount):
			_refund(player_id, consumed)
			_fail(player_id, recipe_id, FAIL_MISSING_INGREDIENTS)
			return
		consumed[String(item_id)] = amount

	var out_qty: int = recipe.output_quantity * quantity
	if not _inventory.request_add_item(recipe.output_item_id, player_id, out_qty):
		_refund(player_id, consumed)
		_fail(player_id, recipe_id, FAIL_INVENTORY_FULL)
		return

	var xp: int = recipe.xp * quantity
	xp = _skills.add_action_xp(recipe.skill_id, xp, player_id)

	if is_instance_valid(_bus):
		_bus.smithing().emit_smithing_craft_completed(player_id, recipe_id, recipe.output_item_id, out_qty, xp)
	AppLogger.log_debug("Schmiede: '%s' stellt %dx '%s' her (Rezept '%s')." % [player_id, out_qty, recipe.output_item_id, recipe_id], LOG_CAT)

func _refund(player_id: String, consumed: Dictionary) -> void:
	for item_id in consumed:
		_inventory.request_add_item(String(item_id), player_id, int(consumed[item_id]))

func _fail(player_id: String, recipe_id: String, reason: String) -> void:
	AppLogger.log_info("Schmiede abgelehnt: '%s' / '%s' (%s)." % [player_id, recipe_id, reason], LOG_CAT)
	if is_instance_valid(_bus):
		_bus.smithing().emit_smithing_craft_failed(player_id, recipe_id, reason)
