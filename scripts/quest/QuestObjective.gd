class_name QuestObjective
extends Resource

## QuestObjective — ein einzelnes Ziel innerhalb einer Quest.
## Wird als Sub-Resource in QuestDefinition.objectives eingetragen.
##
## Typen:
##   collect  — item_id sammeln (InventorySystem)
##   skill    — skill_name auf target_level bringen (SkillSystem)
##   interact — interactable_id einmal benutzen (InteractionBuilder)
##   kill     — enemy_id n-mal besiegen (zukünftiger CombatService)
##   talk     — npc_id ansprechen
##   custom   — freier EventBus-Key für alles andere

enum Type { COLLECT, SKILL, INTERACT, KILL, TALK, CUSTOM }

@export var id: String = ""
@export var label: String = ""
@export var type: Type = Type.COLLECT

## Ziel-ID: item_id / skill_name / interactable_id / enemy_id / npc_id / custom_key
@export var target_id: String = ""

## Benötigte Menge (collect/kill) oder Ziellevel (skill).
@export var required: int = 1

## Ob dieses Objective optional ist (Quest abschließbar ohne es).
@export var optional: bool = false
