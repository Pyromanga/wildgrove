extends QuestNPC
class_name VillageElderNPC

## VillageElderNPC — "Dorfältester Rasmus". Demonstriert ADR-051 Stufe 3 (echtes
## verzweigendes Dialogsystem) an einem eigenständigen, risikofreien Beispiel —
## kein Quest-Geber, gibt also keine der bestehenden Ketten (Wei/Babatunde/...)
## irgendein Regressionsrisiko.
##
## DER KERNPUNKT, DEN STUFE 1/2 NICHT KONNTEN: Rasmus reagiert im Dialog auf
## `quest_babatunde_tale` — eine Quest, die er selbst weder vergibt noch
## trackt. Zwei sich gegenseitig ausschließende Gesprächs-Zweige
## ("gossip_babatunde_done"/"gossip_babatunde_pending", siehe _build_dialogue_tree()
## unten) sind über condition-Strings an den Abschluss-Status DIESER FREMDEN
## Quest gekoppelt — genau das "Talia erkennt im Dialog, dass der Spieler
## wegen Babatundes Sache da ist"-Beispiel aus ADR-051s Kontext-Abschnitt.
##
## Baumstruktur (siehe DialogueTreeController.gd für die generische Engine):
##   start ─┬─ "Was gibt's Neues?" (quest_completed:quest_babatunde_tale)   → gossip_babatunde_done   (Blatt)
##          ├─ "Was gibt's Neues?" (quest_not_completed:quest_babatunde_tale) → gossip_babatunde_pending (Blatt)
##          ├─ "Kennst du Wei?"                                            → ask_wei → bye
##          └─ "Nichts, ich muss weiter."                                  → bye (Blatt)
## Von den beiden "Was gibt's Neues?"-Zweigen ist durch die sich gegenseitig
## ausschließenden Bedingungen IMMER genau einer sichtbar — der Spieler sieht
## nie beide gleichzeitig.
##
## _init() setzt bewusst KEINE der Slot-Felder (quest_id bleibt "" statt des
## QuestNPC-Defaults) — siehe QuestNPC._on_quest_completed()-Guard
## (is_instance_valid(_dialog)) dafür, warum ein leeres quest_id hier sicher ist.

func _init() -> void:
	quest_id         = ""  # kein Slot-System — siehe Klassenkommentar oben.
	npc_display_name = "Dorfältester Rasmus"
	npc_id            = "rasmus_elder"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	var dt := DialogueTreeController.new(tree_label, tree, tree_bus, quest_service)

	dt.add_node("start", "Rasmus nickt dir zu.") \
		.add_choice("Was gibt's Neues im Dorf?", "gossip_babatunde_done", "", "quest_completed:quest_babatunde_tale") \
		.add_choice("Was gibt's Neues im Dorf?", "gossip_babatunde_pending", "", "quest_not_completed:quest_babatunde_tale") \
		.add_choice("Kennst du Wei, die Kampfmeisterin?", "ask_wei") \
		.add_choice("Nichts, ich muss weiter.", "bye")

	dt.add_node(
		"gossip_babatunde_done",
		"Ich hab gehört, du hast die alte\nFehde mit dem Ahnengeist geklärt.\nGute Arbeit."
	)
	dt.add_node(
		"gossip_babatunde_pending",
		"Der Ahnengeist erzählt wieder\nvon einer Fehde, die längst vorbei\nist. Er hat halt... Verspätung."
	)
	dt.add_node(
		"ask_wei",
		"Wei? Kampfmeisterin, unten am\nFluss. Sie zählt keine Kills,\nhab ich gehört — nur Geduld."
	).add_choice("Danke für den Tipp.", "bye")

	dt.add_node("bye", "Rasmus winkt zum Abschied.")

	dt.set_start_node("start")
	return dt

func _get_body_color() -> Color:
	# Gedecktes Braun (Ältesten-Gewand) — unterscheidet ihn von allen anderen NPCs.
	return Color(0.45, 0.35, 0.22)
