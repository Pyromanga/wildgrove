class_name QuestReward
extends Resource

## QuestReward — beschreibt die Belohnung bei Quest-Abschluss.
## Wird von RewardDispatcher in konkrete Service-Calls übersetzt.
## QuestService ruft niemals direkt request_add_item() auf.

@export var xp_rewards: Dictionary = {}  ## skill_name → xp_amount (int)
@export var item_rewards: Dictionary = {}  ## item_id → quantity (int)
@export var unlock_quests: Array[String] = []  ## Quest-IDs die dadurch freigeschalten werden
@export var custom_signals: Array[String] = []  ## EventBus-Keys die gefeuert werden
## Permanente Stat-Boni via StatModifierService. stat_id → PERCENT_ADD-Wert
## (0.10 = +10%). RewardDispatcher baut daraus einen StatModifier.permanent()
## mit source_id="quest_<quest_id>" — bei repeatable=false kann er also nicht
## versehentlich mehrfach vergeben werden (gleicher source_id ersetzt sich selbst).
## Beispiel: {"gathering_yield_wood": 0.10} → +10% Holz-Ertrag beim Fällen.
@export var stat_modifiers: Dictionary = {}

## Convenience-Helper für den Inspector
func add_xp(skill: String, amount: int) -> void:
	xp_rewards[skill] = amount

func add_item(item_id: String, quantity: int = 1) -> void:
	item_rewards[item_id] = quantity
