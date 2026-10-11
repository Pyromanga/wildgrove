extends Service
class_name PickpocketService

## PickpocketService — ADR-039: Pickpocketing (Diebstahl-Kristalle + Skill-Formel).
##
## Einziger Anwendungspunkt: request_pickpocket()/on_pickpocket_confirmed(),
## ausgelöst über drei feste Kontextmenü-Aktionen auf dem Ziel-Spieler-Node
## ("pickpocket_weak"/"pickpocket_normal"/"pickpocket_strong" — siehe
## PlayerPickpocket.gd) statt einer Auswahl-UI wie bei ADR-038s Scrolls: der
## Kristall-TYP steht bereits über die gewählte Aktion fest, es gibt keinen
## zusätzlichen "welches Item anwenden"-Schritt.
##
## SICHERHEITS-MUSTER (identisch zu ADR-038): der Kristall-Tier wird
## AUSSCHLIESSLICH serverseitig aus `ItemDefinition.pickpocket_crystal_tier`
## des tatsächlich im Inventar vorhandenen Items gelesen — der Client
## übergibt nur `crystal_item_id`, nie den Tier direkt. Ein Client könnte
## sonst einen schwachen Kristall mit einem selbstgewählten
## Tier="strong" einreichen und den großen Bonus/Cooldown-Tradeoff umgehen.
##
## ZONEN-KOPPLUNG (ADR-030, Option B aus diesem ADR): geprüft wird die Zone
## DES OPFERS (nicht des Täters) — der Täter kann von außerhalb einer
## Diebes-Zone auf ein Opfer INNERHALB zugreifen, wenn beide nah genug für
## die Interaktion sind (Diebes-Zonen sind üblicherweise groß genug, dass
## das in der Praxis kaum vorkommt, aber die ADR spezifiziert "Zielspieler
## befindet sich in einer Zone mit Tag 'theft'" — Opfer-Zone, nicht
## Täter-Zone).
##
## FORMEL-IMPLEMENTIERUNG: exakt der "Vorschlag, zur Bestätigung" aus der ADR
## — effektives_level = max(0, täter_level - opfer_level), drei lineare
## Rampen zwischen den Meilenstein-Leveln 100/1.000/10.000, Kristall-Bonus
## additiv auf chance_1. Alle konkreten Zahlen (Bonus-%, XP-Beträge,
## Gold-Diebstahl-Anteil) sind von der ADR selbst als Platzhalter markiert
## ("Konkrete Zahlen sind ein fairer Vorschlag") — hier 1:1 übernommen, aber
## mit denselben Konstanten-Kommentaren nochmal als Platzhalter markiert.
##
## "EIN ITEM STEHLEN" — Interpretationsentscheidung (ADR spezifiziert nicht,
## was genau eine gestohlene "Einheit" ist): jeder erfolgreiche Steal-Slot
## entfernt ENTWEDER eine kleine, feste Gold-Menge (STEAL_GOLD_FRACTION vom
## aktuellen Kontostand) ODER genau 1 Stück eines zufällig gewählten,
## nicht-diebstahlgeschützten Item-Stacks — nie einen ganzen Stack auf
## einmal. Bewusst konservativ (kein PvP-Tod-artiger Totalverlust) — Balance-
## Platzhalter wie der Rest der Formel.

signal pickpocket_attempted(
	thief_player_id: String,
	victim_player_id: String,
	success: bool,
	items_stolen: Array,
	gold_stolen: int
)
signal pickpocket_failed(thief_player_id: String, victim_player_id: String, reason: String)

const LOG_CAT := "Pickpocket"
const SAVE_KEY := "pickpocket"
const SKILL_ID := "pickpocketing"

const TIER_WEAK   := "weak"
const TIER_NORMAL := "normal"
const TIER_STRONG := "strong"
const VALID_TIERS := [TIER_WEAK, TIER_NORMAL, TIER_STRONG]

## Platzhalter, kein finaler Balance-Wert (ADR-039 selbst: "Prozentwerte
## sind Platzhalter fürs Balancing, Größenordnung ist aber festgelegt").
const TIER_COOLDOWN_SEC := {
	TIER_WEAK:   1.0,
	TIER_NORMAL: 60.0,
	TIER_STRONG: 24.0 * 60.0 * 60.0,
}
const TIER_BONUS := {
	TIER_WEAK:   0.05,
	TIER_NORMAL: 0.10,
	TIER_STRONG: 0.20,
}

const THEFT_ZONE_TAG: StringName = &"theft"

## Meilenstein-Level aus der ADR-Formel — NICHT Platzhalter, explizit als
## "festgelegtes Muster" markiert (`100 × 10^(N-1)`).
const MILESTONE_1: float = 100.0
const MILESTONE_2: float = 1000.0
const MILESTONE_3: float = 10000.0

## Platzhalter (ADR: "Genaues Verhältnis ... ist Balancing-Feintuning").
const XP_SUCCESS: int = 50
const XP_FAIL_PERCENT: float = 0.15  ## innerhalb des ADR-Rahmens "10-20%"

## Platzhalter — siehe Klassenkommentar "EIN ITEM STEHLEN".
const STEAL_GOLD_FRACTION: float = 0.10

var _inventory:  InventorySystem      = null
var _currency:   CurrencyService      = null
var _skill:      SkillSystem          = null
var _zones:      ZoneService          = null
var _network:    NetworkBridge        = null
var _bus:        IEventBus            = null
var _save_system: SaveSystem          = null

## Paar-Schlüssel (sortiert, "idA|idB") -> Cooldown-Ende (Unix-Zeit).
var _cooldowns: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_inventory  = deps.require(ServiceKeys.INVENTORY)             as InventorySystem
	_currency   = deps.require(ServiceKeys.CURRENCY)              as CurrencyService
	_skill      = deps.require(ServiceKeys.SKILL_SYSTEM)          as SkillSystem
	_zones      = deps.require(ServiceKeys.ZONE_SERVICE)          as ZoneService
	_network    = deps.get_optional(ServiceKeys.NETWORK_BRIDGE)   as NetworkBridge
	_bus        = deps.get_optional(ServiceKeys.EVENT_BUS)        as IEventBus
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)     as SaveSystem

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)

	AppLogger.log_info("PickpocketService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Öffentliche API — Versuch
# ─────────────────────────────────────────────

## Absicht: "thief_player_id versucht, victim_player_id mit crystal_item_id
## zu bestehlen." Kein Tier-Parameter — siehe Klassenkommentar
## "SICHERHEITS-MUSTER".
##
## Wird von Player._on_pickpocket_requested() aufgerufen (statt
## on_pickpocket_confirmed() direkt) — einheitlicher Einstiegspunkt,
## konsistent mit AuraService.request_thank()/ItemProtectionService.
## request_apply_protection(). Der Netzwerk-Zweig unten greift von diesem
## einen Aufrufer aus praktisch nie (Player._on_pickpocket_requested() läuft
## erst nach einem is_multiplayer_authority()-Guard, ist an dieser Stelle
## also immer schon Autorität — InteractableComponent._handle_completion()
## hat das Client→Autorität-Routing für den Kontextmenü-Trigger bereits
## generisch übernommen, bevor _on_pickpocket_requested() überhaupt läuft).
## request_pickpocket() bleibt trotzdem der EINE öffentliche API-Methode,
## damit ein künftiger zweiter Aufrufer (z.B. ein UI-Panel-Trigger ohne
## InteractableComponent) sie einfach mitbenutzen kann.
func request_pickpocket(thief_player_id: String, victim_player_id: String, crystal_item_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_pickpocket_attempt(crystal_item_id, victim_player_id, thief_player_id)
	else:
		on_pickpocket_confirmed(thief_player_id, victim_player_id, crystal_item_id)

## NPC-Erweiterung von ADR-039 (Wunsch "es fehlt ein NPC den ich beklauen
## kann"): Gegenstück zu request_pickpocket()/on_pickpocket_confirmed() für
## ein Nicht-Spieler-Ziel (z.B. VillagerNPC). Bewusst KEIN eigener
## Client→Autorität-Netzwerk-Zweig wie oben — anders als ein Spieler-Node
## ist ein VillagerNPC ein normales Welt-Entity mit
## set_multiplayer_authority(1) (wie HarvestableEntity/EnemyNPC), dessen
## InteractableComponent._handle_completion() das Routing zur Autorität
## bereits generisch übernimmt (siehe HarvestableEntity._on_interacted()-
## Kommentar "ADR-020 / R-1"). Der Aufrufer (VillagerNPC._on_interacted())
## ruft diese Methode deshalb direkt auf, genau wie EnemyNPC das mit
## CombatSystem.player_melee_damage() tut — kein request_*()-Split nötig.
##
## Opfer hat kein echtes Inventory/Currency (Villager-NPCs sind bewusst
## einfach gehalten) — der stehlbare Pool ist deshalb nur Gold in einer vom
## Aufrufer vorgegebenen Bandbreite (npc_gold_min/max) statt
## _build_stealable_pool(). Level-Formel, Meilensteine, Cooldown- und
## Bonus-Konstanten bleiben identisch zu on_pickpocket_confirmed() — bewusst
## dieselbe Service-Instanz statt eigenem Klon, damit Cooldowns und XP für
## Spieler- UND NPC-Ziele konsistent über denselben Skill gezählt werden.
##
## npc_id: eindeutiger Node-Name des Villagers (siehe VillagerNPC — Cooldown-
## Schlüssel, keine "echte" player_id).
## npc_defense_level: fester Schwierigkeitswert des NPCs, ersetzt
## SkillSystem.get_level(SKILL_ID, victim_player_id) aus der Spieler-Variante.
func on_pickpocket_npc_confirmed(
		thief_player_id: String,
		npc_id: String,
		crystal_item_id: String,
		npc_gold_min: int,
		npc_gold_max: int,
		npc_defense_level: int
) -> void:
	if not _require_authority("on_pickpocket_npc_confirmed"):
		return

	if thief_player_id.is_empty() or npc_id.is_empty():
		pickpocket_failed.emit(thief_player_id, npc_id, "invalid_target")
		return

	var crystal_def: ItemDefinition = _inventory.get_item_info(crystal_item_id)
	if not crystal_def or not VALID_TIERS.has(crystal_def.pickpocket_crystal_tier):
		pickpocket_failed.emit(thief_player_id, npc_id, "not_a_crystal")
		return
	var tier: String = crystal_def.pickpocket_crystal_tier

	if not _inventory.has_item(crystal_item_id, thief_player_id, 1):
		pickpocket_failed.emit(thief_player_id, npc_id, "crystal_not_owned")
		return

	# Kein _victim_in_theft_zone()-Check — Villager-NPCs sind bewusst überall
	# beklaubar, unabhängig von Diebes-Zonen (die ADR-030-Zonenkopplung gilt
	# laut ADR-039 nur für Spieler-Opfer).
	var key := _pair_key(thief_player_id, "npc:" + npc_id)
	var cooldown_until: float = float(_cooldowns.get(key, 0.0))
	if _now() < cooldown_until:
		pickpocket_failed.emit(thief_player_id, npc_id, "cooldown_active")
		return

	if not _inventory.remove_item(crystal_item_id, thief_player_id, 1):
		pickpocket_failed.emit(thief_player_id, npc_id, "crystal_not_owned")
		return
	_cooldowns[key] = _now() + float(TIER_COOLDOWN_SEC[tier])

	var thief_level := _skill.get_level(SKILL_ID, thief_player_id)
	var effective_level := maxi(0, thief_level - npc_defense_level)

	var chance_1: float = clampf(float(effective_level) / MILESTONE_1, 0.0, 1.0) + float(TIER_BONUS[tier])
	chance_1 = minf(chance_1, 1.0)

	var items_stolen: Array = []
	var gold_stolen := 0
	var success := false

	if randf() < chance_1:
		success = true
		gold_stolen = randi_range(mini(npc_gold_min, npc_gold_max), maxi(npc_gold_min, npc_gold_max))
		if gold_stolen > 0:
			_currency.request_add_gold(thief_player_id, gold_stolen)
			items_stolen.append({"type": "gold", "amount": gold_stolen})

	var xp := XP_SUCCESS if success else int(round(float(XP_SUCCESS) * XP_FAIL_PERCENT))
	if xp > 0:
		_skill.request_add_xp(SKILL_ID, xp, thief_player_id)

	pickpocket_attempted.emit(thief_player_id, npc_id, success, items_stolen, gold_stolen)
	AppLogger.log_info(
		"Pickpocket (NPC): '%s' → '%s' (Tier '%s', Erfolg=%s, %d Gold)."
		% [thief_player_id, npc_id, tier, success, gold_stolen],
		LOG_CAT
	)

func on_pickpocket_confirmed(thief_player_id: String, victim_player_id: String, crystal_item_id: String) -> void:
	if not _require_authority("on_pickpocket_confirmed"):
		return

	if thief_player_id.is_empty() or victim_player_id.is_empty() or thief_player_id == victim_player_id:
		pickpocket_failed.emit(thief_player_id, victim_player_id, "invalid_target")
		return

	var crystal_def: ItemDefinition = _inventory.get_item_info(crystal_item_id)
	if not crystal_def or not VALID_TIERS.has(crystal_def.pickpocket_crystal_tier):
		pickpocket_failed.emit(thief_player_id, victim_player_id, "not_a_crystal")
		return
	var tier: String = crystal_def.pickpocket_crystal_tier

	if not _inventory.has_item(crystal_item_id, thief_player_id, 1):
		pickpocket_failed.emit(thief_player_id, victim_player_id, "crystal_not_owned")
		return

	if not _victim_in_theft_zone(victim_player_id):
		pickpocket_failed.emit(thief_player_id, victim_player_id, "victim_not_in_theft_zone")
		return

	var key := _pair_key(thief_player_id, victim_player_id)
	var cooldown_until: float = float(_cooldowns.get(key, 0.0))
	if _now() < cooldown_until:
		pickpocket_failed.emit(thief_player_id, victim_player_id, "cooldown_active")
		return

	# Kristall verbrauchen VOR der Erfolgsberechnung — "unabhängig von
	# Erfolg/Fehlschlag" (ADR-039). Cooldown wird im selben Zug gesetzt,
	# unabhängig vom Ausgang.
	if not _inventory.remove_item(crystal_item_id, thief_player_id, 1):
		pickpocket_failed.emit(thief_player_id, victim_player_id, "crystal_not_owned")
		return
	_cooldowns[key] = _now() + float(TIER_COOLDOWN_SEC[tier])

	var thief_level  := _skill.get_level(SKILL_ID, thief_player_id)
	var victim_level := _skill.get_level(SKILL_ID, victim_player_id)
	var effective_level := maxi(0, thief_level - victim_level)

	var chance_1: float = clampf(float(effective_level) / MILESTONE_1, 0.0, 1.0) + float(TIER_BONUS[tier])
	chance_1 = minf(chance_1, 1.0)
	var chance_2: float = clampf((float(effective_level) - MILESTONE_1) / (MILESTONE_2 - MILESTONE_1), 0.0, 1.0)
	var chance_3: float = clampf((float(effective_level) - MILESTONE_2) / (MILESTONE_3 - MILESTONE_2), 0.0, 1.0)

	var items_stolen: Array = []
	var gold_stolen := 0
	var success := false

	if randf() < chance_1:
		success = true
		var slot1: Variant = _steal_one(victim_player_id, thief_player_id)
		if slot1 != null:
			items_stolen.append(slot1)
			if slot1.get("type") == "gold":
				gold_stolen += int(slot1.get("amount", 0))
			if randf() < chance_2:
				var slot2: Variant = _steal_one(victim_player_id, thief_player_id)
				if slot2 != null:
					items_stolen.append(slot2)
					if slot2.get("type") == "gold":
						gold_stolen += int(slot2.get("amount", 0))
					if randf() < chance_3:
						var slot3: Variant = _steal_one(victim_player_id, thief_player_id)
						if slot3 != null:
							items_stolen.append(slot3)
							if slot3.get("type") == "gold":
								gold_stolen += int(slot3.get("amount", 0))

	var xp := XP_SUCCESS if success else int(round(float(XP_SUCCESS) * XP_FAIL_PERCENT))
	if xp > 0:
		_skill.request_add_xp(SKILL_ID, xp, thief_player_id)

	_notify_victim(
		victim_player_id,
		"Jemand hat versucht, dich zu bestehlen!" if not success else "Du wurdest bestohlen!"
	)

	pickpocket_attempted.emit(thief_player_id, victim_player_id, success, items_stolen, gold_stolen)
	AppLogger.log_info(
		"Pickpocket: '%s' → '%s' (Tier '%s', Erfolg=%s, %d Slot(s) gestohlen, %d Gold)."
		% [thief_player_id, victim_player_id, tier, success, items_stolen.size(), gold_stolen],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Intern — Diebstahl-Mechanik
# ─────────────────────────────────────────────

## Ein einzelner Steal-Slot: wählt zufällig EINEN Kandidaten (Gold-Anteil
## ODER 1 Stück eines Item-Stacks, siehe Klassenkommentar "EIN ITEM
## STEHLEN") aus dem aktuell stehlbaren Pool des Opfers und überträgt ihn.
## Gibt null zurück wenn nichts (mehr) stehlbar ist — kein Fehler, einfach
## ein leerer Slot (z.B. Opfer wurde durch vorherige Slots bereits leer
## geplündert oder hatte von Anfang an nichts Stehlbares).
func _steal_one(victim_player_id: String, thief_player_id: String) -> Variant:
	var pool := _build_stealable_pool(victim_player_id)
	if pool.is_empty():
		return null
	var entry: Dictionary = pool[randi() % pool.size()]

	if entry["type"] == "gold":
		var amount: int = entry["amount"]
		if amount <= 0 or not _currency.request_remove_gold(victim_player_id, amount):
			return null
		_currency.request_add_gold(thief_player_id, amount)
		return {"type": "gold", "amount": amount}

	var item_id: String = entry["item_id"]
	if not _inventory.remove_item(item_id, victim_player_id, 1):
		return null
	_inventory.on_item_add_confirmed(item_id, 1, thief_player_id)
	return {"type": "item", "item_id": item_id, "quantity": 1}

## ADR-038-Schutzkategorie: NUR is_theft_protected zählt hier (analog
## DeathLootService, das NUR is_pve_death_protected prüft) — permanent
## geschützte Items werden nie in den Pool aufgenommen.
func _build_stealable_pool(victim_player_id: String) -> Array:
	var pool: Array = []
	var gold := _currency.get_gold(victim_player_id)
	if gold > 0:
		var steal_amount := maxi(1, int(round(float(gold) * STEAL_GOLD_FRACTION)))
		steal_amount = mini(steal_amount, gold)
		pool.append({"type": "gold", "amount": steal_amount})

	for item in _inventory.get_all_items(victim_player_id):
		var item_id: String = item.get("id", "")
		var inst := _inventory.get_item_instance(victim_player_id, item_id)
		if inst and inst.is_theft_protected:
			continue
		if int(item.get("quantity", 0)) > 0:
			pool.append({"type": "item", "item_id": item_id})
	return pool

func _victim_in_theft_zone(victim_player_id: String) -> bool:
	if not is_instance_valid(_zones) or not is_instance_valid(_network):
		return false
	var victim_peer := _network.get_peer_id_for_player(victim_player_id)
	if victim_peer == -1:
		return false
	return _zones.has_tag(victim_peer, THEFT_ZONE_TAG)

## Wird von NetworkBridge._rpc_receive_pickpocket_notification() auf dem
## Ziel-Client (dem Opfer) aufgerufen. Reicht die Nachricht nur an den
## lokalen UI-Notification-Kanal durch — kein weiterer State betroffen,
## läuft nie auf der Autorität selbst (siehe RPC-Kommentar in NetworkBridge).
func on_notification_received(text: String) -> void:
	if is_instance_valid(_bus):
		_bus.ui().emit_notification_requested(text)

func _notify_victim(victim_player_id: String, text: String) -> void:
	if not is_instance_valid(_network):
		return
	if victim_player_id == _network.get_local_player_id():
		if is_instance_valid(_bus):
			_bus.ui().emit_notification_requested(text)
	else:
		_network.send_pickpocket_notification_for_player(victim_player_id, text)

# ─────────────────────────────────────────────
# Intern — Sonstiges
# ─────────────────────────────────────────────

func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func _now() -> float:
	return Time.get_unix_time_from_system()

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

# ─────────────────────────────────────────────
# Save-Interface (Cooldowns — Neustart-Exploit-Schutz analog AuraService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	var now := _now()
	var fresh: Dictionary = {}
	for key in _cooldowns:
		if now < float(_cooldowns[key]):
			fresh[key] = _cooldowns[key]
	return {"cooldowns": fresh}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("cooldowns") is Dictionary:
		_cooldowns = saved["cooldowns"]
