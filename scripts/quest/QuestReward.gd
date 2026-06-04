class_name QuestReward
extends Resource

## QuestReward — beschreibt die Belohnung bei Quest-Abschluss.
## Wird von RewardDispatcher in konkrete Service-Calls übersetzt.
## QuestService selbst ruft NIEMALS Services.inventory.add_item() direkt auf.

@export var xp_rewards: Dictionary = {}  ## skill_name → xp_amount (int)
@export var item_rewards: Dictionary = {}  ## item_id → quantity (int)
@export var unlock_quests: Array[String] = []  ## Quest-IDs die dadurch freigeschalten werden
@export var custom_signals: Array[String] = []  ## EventBus-Keys die gefeuert werden


## Convenience-Helper für den Inspector
func add_xp(skill: String, amount: int) -> void:
	xp_rewards[skill] = amount


func add_item(item_id: String, quantity: int = 1) -> void:
	item_rewards[item_id] = quantity
