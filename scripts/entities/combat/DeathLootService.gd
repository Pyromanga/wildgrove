extends Service
class_name DeathLootService

## DeathLootService — ADR-037: PvE-Tod-Loot (Grab-Hybrid-Timer).
##
## Einziger Einstiegspunkt: handle_pve_death(player_id, death_position),
## aufgerufen von Player._on_player_died() sobald erkannt wird, dass der
## Tod NICHT PvP war (record.attacker_peer_id löst auf keinen anderen
## Spieler auf — siehe dortiger Kommentar). Reine Anwendungslogik — die
## Entscheidung "war das PvP oder PvE?" trifft bereits Player.gd, dieser
## Service bekommt nur den PvE-Fall zu sehen.
##
## SCHUTZKATEGORIE (ADR-038): NUR `is_pve_death_protected` wird hier geprüft
## — `is_theft_protected`/`is_pvp_protected` sind für einen PvE-Tod irrelevant
## (die schützen vor Diebstahl bzw. PvP-Tod, nicht PvE-Tod; ADR-038 selbst:
## drei unabhängige Kategorien). Permanent geschützte Items bleiben einfach
## im Inventar des Spielers — werden nie entfernt, landen nie im Grab.
##
## KEIN VERLUST OHNE GRAB: Gold+Items werden dem Spieler erst entfernt,
## NACHDEM das Gravestone-Spawnen bestätigt ist (WorldService muss verfügbar
## sein) — kein Fenster, in dem Besitz verloren geht, ohne dass irgendwo ein
## Grab dafür existiert.
##
## ZYKLUS-VERMEIDUNG (Boot-Reihenfolge): DeathLootService deklariert
## bewusst KEINE Abhängigkeit auf "world" in required_deps/optional_deps
## (BootstrapConfig.tres) — WorldService selbst hängt optional von
## "death_loot" ab (für EntityContext.get_death_loot(), analog
## get_pvp_death_loss()), ein Rück-Dep hier würde einen Bootstrap-Zyklus
## erzeugen. Stattdessen injiziert WorldService sich selbst per
## inject_world() DIREKT nach dem eigenen configure() (siehe dortiger
## Kommentar) — derselbe Late-Injection-Grundgedanke wie
## inject_network_bridge()/Phase C8, nur punktuell statt über die generische
## Schleife, weil WorldService der einzige denkbare Aufrufer ist.
##
## NICHT PERSISTIERT: aktive Gräber überleben einen Server-Neustart NICHT
## (kein eigener Save-Key, kein ISaveProvider). Bewusste Vereinfachung für
## diese Runde — ein Neustart während der 30-Minuten-Despawn-Frist eines
## Grabes ist ein seltener Grenzfall, kein Kernszenario. Wird bei Bedarf in
## einer Folge-Runde nachgezogen (Gravestone.gd ist bereits so gebaut, dass
## personal_loot_until/despawn_at reine Unix-Timestamps sind — ein
## Save-Format dafür wäre eine additive Erweiterung, kein Umbau).

signal gravestone_spawned(player_id: String, gravestone_uuid: String, gold: int, item_count: int)
signal death_loot_skipped(player_id: String, reason: String)

const LOG_CAT := "DeathLoot"

## Platzhalter, kein finaler Balance-Wert (ADR-037 selbst: "zur
## Balance-Anpassung in der Umsetzung").
const PERSONAL_LOOT_DURATION_SEC: float = 10.0 * 60.0  ## X = 10 Minuten
const TOTAL_DESPAWN_DURATION_SEC: float = 30.0 * 60.0  ## Y = 30 Minuten ab Todeszeitpunkt

var _currency:   CurrencyService      = null
var _inventory:  InventorySystem      = null
var _world:      WorldService         = null  ## per inject_world(), NICHT über deps — siehe Klassenkommentar
var _network:    NetworkBridge        = null

func configure(deps: ServiceDeps) -> void:
	_currency  = deps.require(ServiceKeys.CURRENCY)              as CurrencyService
	_inventory = deps.require(ServiceKeys.INVENTORY)             as InventorySystem
	_network   = deps.get_optional(ServiceKeys.NETWORK_BRIDGE)   as NetworkBridge
	AppLogger.log_info("DeathLootService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

## Von WorldService direkt nach dessen eigenem configure() aufgerufen — siehe
## Klassenkommentar "ZYKLUS-VERMEIDUNG".
func inject_world(world: WorldService) -> void:
	_world = world

## Autoritäts-only wie PvPDeathLossService.apply_death_loss() — ein PvE-Tod
## ist ausschließlich eine Server-Entscheidung (HealthComponent.died feuert
## nur auf der Autorität, siehe ADR-025), kein request_*/on_*_confirmed()-
## Split nötig.
func handle_pve_death(player_id: String, death_position: Vector3) -> void:
	if not _require_authority("handle_pve_death"):
		return
	if player_id.is_empty():
		return
	if not is_instance_valid(_currency) or not is_instance_valid(_inventory):
		AppLogger.log_error("handle_pve_death: CurrencyService/InventorySystem fehlt.", LOG_CAT)
		return
	if not is_instance_valid(_world):
		# Siehe Klassenkommentar "KEIN VERLUST OHNE GRAB" — ohne WorldService
		# gäbe es keinen Ort, an dem die verlorenen Sachen landen könnten.
		AppLogger.log_error("handle_pve_death: WorldService nicht injiziert — kein Verlust angewendet.", LOG_CAT)
		death_loot_skipped.emit(player_id, "no_world_service")
		return

	var gold_amount := _currency.get_gold(player_id)
	var items_for_grave: Array = []
	for item in _inventory.get_all_items(player_id):
		var item_id: String = item.get("id", "")
		var qty: int         = item.get("quantity", 0)
		var inst := _inventory.get_item_instance(player_id, item_id)
		if inst and inst.is_pve_death_protected:
			continue
		if qty > 0:
			items_for_grave.append({"item_id": item_id, "quantity": qty})

	if gold_amount <= 0 and items_for_grave.is_empty():
		# Nichts zu verlieren (alles geschützt oder Spieler war bereits leer)
		# — kein leeres Grab spawnen.
		death_loot_skipped.emit(player_id, "nothing_to_lose")
		return

	if gold_amount > 0:
		_currency.request_remove_gold(player_id, gold_amount)
	for entry in items_for_grave:
		_inventory.remove_item(entry["item_id"], player_id, entry["quantity"])

	var now := Time.get_unix_time_from_system()
	var config := {
		"owner_player_id":      player_id,
		"gold":                 gold_amount,
		"items":                items_for_grave,
		"personal_loot_until":  now + PERSONAL_LOOT_DURATION_SEC,
		"despawn_at":           now + TOTAL_DESPAWN_DURATION_SEC,
	}
	var grave := _world.spawn_entity("gravestone", death_position, config, 1)
	if not is_instance_valid(grave):
		AppLogger.log_error(
			"handle_pve_death: Gravestone-Spawn fehlgeschlagen — %d Gold/%d Item-Stacks von '%s' sind verloren, ohne Grab."
			% [gold_amount, items_for_grave.size(), player_id],
			LOG_CAT
		)
		return

	var uuid: String = grave.get_meta("entity_uuid", "")
	gravestone_spawned.emit(player_id, uuid, gold_amount, items_for_grave.size())
	AppLogger.log_info(
		"Gravestone gespawnt für '%s' @ %s: %d Gold, %d Item-Stacks."
		% [player_id, str(death_position), gold_amount, items_for_grave.size()],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true
