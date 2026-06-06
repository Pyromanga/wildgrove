extends ServiceNode
class_name RewardDispatcher

## RewardDispatcher — Übersetzt QuestReward in konkrete Service-Aufrufe.
##
## NEU (Session 4): QuestService.complete_quest() hatte reward = null als Stub.
##   Quests konnten keine Belohnungen auszahlen.
##
## ARCHITEKTUR:
##   QuestService kennt KEINE anderen Gameplay-Services (inventory, skill_system).
##   RewardDispatcher ist das einzige System das QuestReward in Service-Calls übersetzt.
##   Das hält QuestService testbar und entkoppelt.
##
## Abhängigkeiten (deps): ["inventory", "skill_system"]
## (QuestService selbst hat keine dep auf RewardDispatcher — greift via Services.reward_dispatcher)

const LOG_CAT := "RewardDispatcher"

var _inventory:    InventorySystem
var _skill_system: SkillSystem


func configure(deps: Dictionary) -> void:
	_inventory    = deps.get("inventory")    as InventorySystem
	_skill_system = deps.get("skill_system") as SkillSystem

	if not is_instance_valid(_inventory):
		Logger.log_warn("InventorySystem fehlt — Item-Rewards nicht verfügbar.", LOG_CAT)
	if not is_instance_valid(_skill_system):
		Logger.log_warn("SkillSystem fehlt — XP-Rewards nicht verfügbar.", LOG_CAT)


func on_ready() -> void:
	Logger.log_info("RewardDispatcher bereit.", LOG_CAT)


## Zahlt eine QuestReward aus. Gibt true zurück wenn alle Teile erfolgreich waren.
func dispatch(reward: QuestReward) -> bool:
	if not reward:
		Logger.log_warn("dispatch() mit null-Reward aufgerufen.", LOG_CAT)
		return false

	var all_ok := true
	var t := Logger.log_begin("RewardDispatcher.dispatch()", LOG_CAT)

	# XP-Rewards
	for skill_name in reward.xp_rewards:
		var amount: int = reward.xp_rewards[skill_name]
		if is_instance_valid(_skill_system):
			_skill_system.add_xp(skill_name, amount)
			Logger.log_debug("+%d XP in '%s'." % [amount, skill_name], LOG_CAT)
		else:
			Logger.log_warn("SkillSystem fehlt — XP-Reward '%s' x%d nicht ausgezahlt!" % [skill_name, amount], LOG_CAT)
			all_ok = false

	# Item-Rewards
	for item_id in reward.item_rewards:
		var quantity: int = reward.item_rewards[item_id]
		if is_instance_valid(_inventory):
			_inventory.add_item(item_id, quantity)
			Logger.log_debug("+%dx '%s' ins Inventar." % [quantity, item_id], LOG_CAT)
		else:
			Logger.log_warn("InventorySystem fehlt — Item-Reward '%s' x%d nicht ausgezahlt!" % [item_id, quantity], LOG_CAT)
			all_ok = false

	# Quest-Unlocks
	for quest_id in reward.unlock_quests:
		if is_instance_valid(Services.quest):
			Services.quest.unlock_quest(quest_id)
			Logger.log_debug("Quest freigeschaltet: '%s'." % quest_id, LOG_CAT)
		else:
			Logger.log_warn("QuestService fehlt — Quest-Unlock '%s' nicht ausgeführt!" % quest_id, LOG_CAT)
			all_ok = false

	# Custom-Signals
	for signal_key in reward.custom_signals:
		Logger.log_debug("Custom-Signal emittiert: '%s'." % signal_key, LOG_CAT)
		EventBus.quest.emit_reward_signal(signal_key)

	Logger.log_end("RewardDispatcher.dispatch()", t, LOG_CAT)
	return all_ok
