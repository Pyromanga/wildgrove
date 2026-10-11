extends QuestNPC
class_name WoodcutterNPC

## WoodcutterNPC — "Waldläufer Erik". Quest-Geber für quest_woodcutter_intro
## → quest_woodcutter_master.
##
## ADR-051 Stufe 3 (umgestellt 2026-09-27): nutzt DialogueTreeController.
## build_quest_giver() — siehe MinerNPC.gd Klassenkommentar für die
## allgemeine Begründung der Umstellung.
##
## quest_erik_friendship bleibt bewusst AUSSEN VOR (genau wie vor der
## Umstellung): die Baum-Engine hat zwar keine 2-Schritt-Beschränkung mehr,
## aber quest_erik_friendship.obj_explore_camp hängt weiterhin an einem
## QuestCustomTrigger, der im World-Setup nirgends instanziiert ist (siehe
## AncestorSpiritNPC.gd Klassenkommentar) — ein Dialog-System-Upgrade
## repariert diese fehlende Welt-Verdrahtung nicht. Bleibt bekannter offener
## Punkt in TODO-offene-probleme.md.

func _init() -> void:
	quest_id         = ""  # kein Slot-System mehr — siehe MinerNPC.gd.
	npc_display_name = "Waldläufer Erik"
	npc_id            = "erik_woodcutter"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_woodcutter_intro", "obj_chop_trees", 3,
		"Gut, dass du da bist!\nFälle 3 Eichen für mich.\nDas Holz wird gebraucht.",
		"Gut! Du hast schon\n%d/%d Bäume gefällt.",
		"Danke! Das Holz werde\nich gut gebrauchen können.",
		"quest_woodcutter_master", "obj_reach_woodcutting_5", 5,
		"Du hast wirklich Talent.\nErreiche Holzfäller-Stufe 5 —\ndann bist du kein Anfänger mehr.",
		"Holzfäller-Stufe %d/%d.\nWeiter so!",
		"Beeindruckend. Ich habe\nnichts mehr, was ich dir\nbeibringen könnte."
	)
