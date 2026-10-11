extends QuestNPC
class_name SurveyorNPC

## SurveyorNPC — "Feldmesser Lucius". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).

## Römisch (Verwaltung/Grenzen): Agrimensor, römischer Feldmesser. Der Grenzgott Terminus lässt Grenzsteine unverrückbar sein, doch der Maulwurf ignoriert ihn. Rolle: Bürokratie. Gag: Nornen-Beschwerdeamt (Amtsweg dauert Jahre).

func _init() -> void:
	quest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
	npc_display_name = "Feldmesser Lucius"
	npc_id            = "lucius_surveyor"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_lucius_boundary",
		"obj_collect_molehill_soil",
		4,
		"Der Maulwurf verrückt meine\nGrenzsteine! Bring 4 Erde\nvon seinen Hügeln. Beweis!",
		"Maulwurferde: %d/%d.\nDas Amt wartet schon.",
		"Beweis eingereicht. Das\nAmt prüft: in 3 bis 5\nJahren. Vielleicht.",
		"quest_lucius_survey",
		"obj_reach_digging_3",
		3,
		"Wer Grenzen misst, kennt\nden Boden. Erreiche\nGraben-Stufe 3, Bürger!",
		"Graben-Stufe %d/%d.\nTiefer, Bürger!",
		"Vermessen und für gut\nbefunden. Der Maulwurf\nbleibt unbeeindruckt."
	)

func _get_body_color() -> Color:
	return Color(0.55, 0.15, 0.15)
