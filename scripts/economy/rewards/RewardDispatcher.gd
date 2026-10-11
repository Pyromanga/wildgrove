extends Service
class_name RewardDispatcher

## RewardDispatcher — Übersetzt QuestReward in konkrete Service-Aufrufe.
##
## ARCHITEKTUR:
##   QuestService kennt KEINE anderen Gameplay-Services (inventory, skill_system).
##   RewardDispatcher ist das einzige System das QuestReward in Service-Calls übersetzt.
##   Das hält QuestService testbar und entkoppelt.
##
## Abhängigkeiten (deps): ["inventory", "skill_system", "stat_modifiers" (optional)]
## QuestService deklariert reward_dispatcher als deps und bekommt ihn injiziert (configure()).
## NetworkBridge kommt NICHT über configure() — network_bridge deklariert bereits
## "quest" als eigenen Dep (siehe BootstrapConfig.tres), und quest deklariert
## "reward_dispatcher": ein configure()-Dep hier wäre der Zyklus
## network_bridge → quest → reward_dispatcher → network_bridge. Kommt deshalb
## über denselben Phase-C8-Late-Inject-Mechanismus wie Inventory/Quest/
## SkillSystem/Equipment/World (siehe BootPipeline.gd, inject_network_bridge()
## unten).

const LOG_CAT := "RewardDispatcher"

var _inventory:      InventorySystem
var _skill_system:   SkillSystem
var _bus:             IEventBus
var _stat_modifiers: StatModifierService = null  ## optional -- fehlt sie, werden stat_modifiers-Rewards uebersprungen (mit Warnung)
## ADR-029 Plan-Schritt 4: Übersetzung peer_id (int) → player_id (String) an
## den Aufrufen in migrierte Services. Round 63: InventorySystem. Round 65:
## SkillSystem kommt als zweiter Aufrufer dazu (derselbe Helfer, keine neue
## Zeile) — StatModifierService bleibt der einzige noch unmigrierte Empfänger
## von dispatch()s eigenem `peer_id` (Round 67: umbenannt von `player_id`,
## siehe TODO-offene-probleme.md — war int, hieß aber wie die stabile
## String-Identität).
var _network: NetworkBridge = null

func configure(deps: ServiceDeps) -> void:
	_inventory      = deps.require(ServiceKeys.INVENTORY)    as InventorySystem
	_skill_system   = deps.require(ServiceKeys.SKILL_SYSTEM) as SkillSystem
	_bus            = deps.require(ServiceKeys.EVENT_BUS)     as IEventBus
	_stat_modifiers = deps.get_optional(ServiceKeys.STAT_MODIFIERS) as StatModifierService

	if not is_instance_valid(_inventory):
		AppLogger.log_warn("InventorySystem fehlt — Item-Rewards nicht verfügbar.", LOG_CAT)
	if not is_instance_valid(_skill_system):
		AppLogger.log_warn("SkillSystem fehlt — XP-Rewards nicht verfügbar.", LOG_CAT)
	if not is_instance_valid(_stat_modifiers):
		AppLogger.log_warn("StatModifierService fehlt — Stat-Modifier-Rewards nicht verfügbar.", LOG_CAT)

## Phase C8 Late-Inject (BootPipeline.gd) — identischer Mechanismus/Grund wie
## InventorySystem.inject_network_bridge(): siehe Kommentar oben bei configure().
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func on_ready() -> void:
	AppLogger.log_info("RewardDispatcher bereit.", LOG_CAT)

## ADR-029 Plan-Schritt 4: Übersetzt die peer_id, die dispatch() entgegennimmt
## (noch nicht migriert — QuestService, dessen einziger Aufrufer, kennt selbst
## nur peer_id bis zu seiner eigenen Migrationsrunde), in die stabile player_id
## die InventorySystem jetzt verlangt. Identisches Muster zu
## InventorySystem._resolve_player_uuid() — bewusst keine gemeinsame Utility-
## Funktion für zwei Call-Sites, siehe Round-63-Diskussion (kein neuer
## Abstraktionslayer, nur ein Aufruf des bereits kanonischen Getters).
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

## Zahlt eine QuestReward aus. Gibt true zurück wenn alle Teile erfolgreich waren.
## quest_id: wird als source_id für permanente StatModifier genutzt (siehe stat_modifiers) —
## Pflichtparameter, kein Default, damit kein Aufrufer ihn vergessen aus Bequemlichkeit weglässt.
func dispatch(reward: QuestReward, quest_id: String, peer_id: int = 1) -> bool:
	if not reward:
		AppLogger.log_warn("dispatch() mit null-Reward aufgerufen.", LOG_CAT)
		return false

	var all_ok := true
	var t := AppLogger.log_begin("RewardDispatcher.dispatch()", LOG_CAT)

	# ADR-029 Round 69: EINMAL aufgelöst und für alle drei Empfänger unten
	# wiederverwendet (Skill-/Item-Rewards UND jetzt auch StatModifierService,
	# der letzte noch unmigrierte Aufrufer — siehe TODO-offene-probleme.md,
	# § Wichtig). Vorher wurde dieselbe Übersetzung pro Reward-Block einzeln
	# wiederholt; StatModifier-Rewards liefen bis hierhin komplett unübersetzt
	# mit der rohen peer_id direkt an StatModifierService.
	var player_id := _resolve_player_uuid(peer_id)

	# XP-Rewards
	# ADR-029 Round 65: SkillSystem ist migriert (player_id: String) —
	# Übersetzung an dieser Aufrufgrenze, identisches Muster zum
	# Item-Rewards-Block unten (InventorySystem, Round 63).
	for skill_name in reward.xp_rewards:
		var amount: int = reward.xp_rewards[skill_name]
		if is_instance_valid(_skill_system):
			if player_id.is_empty():
				AppLogger.log_error(
					"XP-Reward '%s' x%d: peer_id %d konnte nicht in eine player_uuid übersetzt werden — übersprungen." % [skill_name, amount, peer_id],
					LOG_CAT
				)
				all_ok = false
			else:
				_skill_system.request_add_xp(skill_name, amount, player_id)
				AppLogger.log_debug("+%d XP in '%s'." % [amount, skill_name], LOG_CAT)
		else:
			AppLogger.log_warn("SkillSystem fehlt — XP-Reward '%s' x%d nicht ausgezahlt!" % [skill_name, amount], LOG_CAT)
			all_ok = false

	# Item-Rewards
	for item_id in reward.item_rewards:
		var quantity: int = reward.item_rewards[item_id]
		if is_instance_valid(_inventory):
			if player_id.is_empty():
				AppLogger.log_error(
					"Item-Reward '%s' x%d: peer_id %d konnte nicht in eine player_uuid übersetzt werden — übersprungen." % [item_id, quantity, peer_id],
					LOG_CAT
				)
				all_ok = false
			else:
				_inventory.request_add_item(item_id, player_id, quantity)
				AppLogger.log_debug("+%dx '%s' ins Inventar." % [quantity, item_id], LOG_CAT)
		else:
			AppLogger.log_warn("InventorySystem fehlt — Item-Reward '%s' x%d nicht ausgezahlt!" % [item_id, quantity], LOG_CAT)
			all_ok = false

	# Quest-Unlocks — via EventBus.
	# QuestService lauscht auf EventBus.quest.quest_unlock_requested und ruft unlock_quest() selbst auf.
	for quest_to_unlock in reward.unlock_quests:
		_bus.quest().emit_quest_unlock_requested(quest_to_unlock)
		AppLogger.log_debug("Quest-Unlock angefordert: '%s'." % quest_to_unlock, LOG_CAT)

	# Stat-Modifier-Rewards — permanent, source_id="quest_<quest_id>" macht sie
	# idempotent (erneutes dispatch() für dieselbe Quest ersetzt statt zu stapeln).
	# ADR-029 Round 69: StatModifierService verlangt jetzt ebenfalls player_id —
	# dieselbe oben aufgelöste Variable, keine zweite Übersetzungsstelle.
	for stat_id in reward.stat_modifiers:
		var pct: float = reward.stat_modifiers[stat_id]
		if is_instance_valid(_stat_modifiers):
			if player_id.is_empty():
				AppLogger.log_error(
					"Stat-Modifier-Reward '%s' %+.0f%% (Quest '%s'): peer_id %d konnte nicht in eine player_uuid übersetzt werden — übersprungen." % [
						stat_id, pct * 100.0, quest_id, peer_id
					],
					LOG_CAT
				)
				all_ok = false
			else:
				var modifier := StatModifier.permanent(
					"quest_%s" % quest_id, stat_id, StatModifier.Operation.PERCENT_ADD, pct
				)
				_stat_modifiers.add_modifier(modifier, player_id)
				AppLogger.log_debug(
					"Stat-Modifier '%s' %+.0f%% durch Quest '%s'." % [stat_id, pct * 100.0, quest_id], LOG_CAT
				)
		else:
			AppLogger.log_warn(
				"StatModifierService fehlt — Stat-Reward '%s' %+.0f%% (Quest '%s') nicht ausgezahlt!" % [
					stat_id, pct * 100.0, quest_id
				],
				LOG_CAT
			)
			all_ok = false

	# Custom-Signals
	for signal_key in reward.custom_signals:
		AppLogger.log_debug("Custom-Signal emittiert: '%s'." % signal_key, LOG_CAT)
		_bus.quest().emit_reward_custom_signal(signal_key)

	AppLogger.log_end("RewardDispatcher.dispatch()", t, LOG_CAT)
	return all_ok
