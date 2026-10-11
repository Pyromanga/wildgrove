class_name DialogueTreeController
extends RefCounted

## DialogueTreeController — das EINE Dialogsystem der Quest-NPCs ("echtes verzweigendes
## Dialogsystem, beliebig viele Optionen pro NPC", ADR-051 Stufe 3).
##
## Das frühere Slot-System (QuestNPCDialogController, ADR-051 Stufe 1/2) ist entfernt; jeder
## QuestNPC baut genau einen Baum (QuestNPC._build_dialogue_tree(), Default =
## build_quest_giver() aus den Export-Feldern). Der Quest-Zustand wird live aus dem
## QuestService gelesen — kein eigener Zustand im Controller.
##
## GENERISCHE STRUKTUR (wie in ADR-051 Stufe 3 beschrieben):
##   DialogueNode   — id, text (was der NPC sagt), choices (Array[DialogueChoice])
##   DialogueChoice — label (was der Spieler sagt), next_node_id (Pflicht —
##                    auch ein Gesprächsende ist ein echter Knoten mit leerer
##                    choices-Liste, siehe unten), action (optionaler
##                    Seiteneffekt), condition (optionale Sichtbarkeits-Regel)
##
## Ein Knoten OHNE (sichtbare) choices ist ein Blatt: sein Text wird gezeigt,
## danach springt das Gespräch zurück zum Startknoten (nächste Interaktion
## beginnt wieder von vorn) — bewusst KEIN separates "end"-Konzept, ein
## Gesprächsende ist einfach ein Knoten mit leeren choices.
##
## MEHRSTUFIGE VERZWEIGUNG INNERHALB EINER INTERAKTION: _show_node() ruft nach
## einer Auswahl direkt wieder sich selbst für den next_node_id auf — mehrere
## Fragen/Antworten-Runden laufen dadurch in einem einzigen Interaktions-Aufruf
## ab, nicht nur "eine Sprechblase pro Klick" wie bei Stufe 1/2.
##
## FREMDE QUESTS: condition-Strings ("quest_completed:<id>" etc.) werden gegen
## _quest_service ausgewertet (IEntityContext.get_quest_service(), ADR-051
## Stufe 3) — NICHT beschränkt auf Quests, die dieser NPC selbst vergibt. Das
## ist der eigentliche Kernunterschied zu Stufe 1/2 (siehe ADR-051 Kontext:
## "Talia erkennt im Dialog, dass der Spieler wegen Babatundes Sache da ist").
##
## WIEDERVERWENDUNG STATT NEUBAU: die Auswahl-UI ist exakt NPCDialogueChoiceUI
## aus Stufe 2 (dieselbe Factory/Callable-Injection, siehe set_choice_ui_factory()) —
## kein zweites Auswahl-Widget für diesen Controller.

class DialogueChoice:
	var label: String
	## Pflicht — auch ein Gesprächsende zeigt auf einen echten (Blatt-)Knoten.
	var next_node_id: String
	## Optionaler Seiteneffekt, ausgelöst wenn diese Wahl getroffen wird.
	## Aktuell unterstützt: "" (keiner), "start_quest:<quest_id>".
	var action: String = ""
	## Optionale Sichtbarkeits-Bedingung — leer heißt immer sichtbar.
	## Unterstützt: "quest_completed:<id>", "quest_active:<id>",
	## "quest_not_completed:<id>", "quest_not_active:<id>".
	var condition: String = ""

	func _init(p_label: String, p_next_node_id: String, p_action: String = "", p_condition: String = "") -> void:
		label         = p_label
		next_node_id  = p_next_node_id
		action        = p_action
		condition     = p_condition

class DialogueNode:
	var id: String
	var text: String
	var choices: Array[DialogueChoice] = []
	## Live-Fortschritt im Text anzeigen (Pendant zu
	## QuestNPC.dialog_encourage_format, "Kampf-Stufe %d/%d"):
	## wenn gesetzt, wird text als Format-String mit [aktueller_fortschritt,
	## progress_required] gerendert — siehe DialogueTreeController._render_text().
	var progress_quest_id: String = ""
	var progress_obj_id: String = ""
	var progress_required: int = 0

	func _init(p_id: String, p_text: String) -> void:
		id   = p_id
		text = p_text

	func add_choice(label: String, next_node_id: String, action: String = "", condition: String = "") -> DialogueNode:
		choices.append(DialogueChoice.new(label, next_node_id, action, condition))
		return self  # Chaining, siehe NPC-Subklassen für den Aufbau eines Baums.

	## Macht aus diesem Knoten einen Live-Fortschritts-Knoten — siehe
	## progress_quest_id-Feldkommentar oben. Gibt self zurück (Chaining).
	func with_progress(quest_id: String, obj_id: String, required: int) -> DialogueNode:
		progress_quest_id  = quest_id
		progress_obj_id    = obj_id
		progress_required  = required
		return self

var _nodes: Dictionary = {}  ## id (String) → DialogueNode
var _start_node_id: String
var _current_node_id: String = ""

var _dialog_label: Label3D
var _scene_tree: SceneTree
var _bus: IEventBus
## ADR-051 Stufe 3: optional — ohne QuestService werden alle Bedingungen als
## "nicht erfüllt" gewertet (sicherer Default: lieber einen Zweig verstecken
## als einen falschen zeigen), siehe _eval_condition().
var _quest_service: QuestService = null
## Für "quest_..."-Bedingungen, die einen konkreten Spieler betreffen — siehe
## QuestNPC._on_interacted(), das dies aus network.get_player_id_for_peer()
## auflöst und hier durchreicht.
var _player_id: String = ""

var _choice_ui_factory: Callable = Callable()

func _init(dialog_label: Label3D, scene_tree: SceneTree, bus: IEventBus, quest_service: QuestService = null) -> void:
	_dialog_label  = dialog_label
	_scene_tree    = scene_tree
	_bus           = bus
	_quest_service = quest_service

func set_choice_ui_factory(factory: Callable) -> void:
	_choice_ui_factory = factory

func set_player_id(player_id: String) -> void:
	_player_id = player_id

## Fügt einen Knoten hinzu und gibt ihn zurück, damit Aufrufer direkt
## .add_choice(...) verketten können — siehe NPC-Subklassen für den vollen
## Baum-Aufbau in _init().
func add_node(id: String, text: String) -> DialogueNode:
	var node := DialogueNode.new(id, text)
	_nodes[id] = node
	return node

func set_start_node(id: String) -> void:
	_start_node_id = id

func on_interact() -> void:
	if _current_node_id.is_empty():
		_current_node_id = _start_node_id
	AppLogger.log_debug(
		"Dialog-Start: Knoten '%s', player_id='%s', QuestService=%s" % [
			_current_node_id, _player_id, "ja" if _quest_service != null else "NEIN"],
		"DialogueTree"
	)
	_show_node(_current_node_id)

func _show_node(node_id: String) -> void:
	var node: DialogueNode = _nodes.get(node_id)
	if node == null:
		AppLogger.log_error("DialogueTreeController: unbekannter Knoten '%s'." % node_id, "DialogueTree")
		return
	var visible: Array[DialogueChoice] = []
	for choice in node.choices:
		if _eval_condition(choice.condition):
			visible.append(choice)

	if visible.is_empty():
		if not node.choices.is_empty():
			AppLogger.log_warn(
				"Knoten '%s': %d Zweige, aber KEINER passt (player_id='%s') — zeige Fallback-Text." % [
					node_id, node.choices.size(), _player_id],
				"DialogueTree"
			)
		# Blattknoten — Gespräch endet hier, zeigt seinen Text, zurück zum Start
		# für die nächste Interaktion (siehe Klassenkommentar oben).
		_current_node_id = _start_node_id
		_show_dialog(_render_text(node))
		return

	# Genau EIN sichtbarer Zweig: automatisch nehmen, kein Menü (gleiches
	# "kein Klick-Umweg für den Normalfall"-Prinzip wie Stufe 1/2 — wichtig
	# für build_quest_giver()-Bäume, deren Router-Knoten IMMER genau einen
	# sichtbaren Zweig hat und dadurch für den Spieler unsichtbar bleibt).
	if visible.size() == 1:
		_apply_choice(node, visible[0])
		return

	var labels: Array[String] = []
	for c in visible:
		labels.append(c.label)

	if not _choice_ui_factory.is_valid():
		# Kein UI verdrahtet (z.B. reiner Unit-Test ohne Szenenbaum) — nie
		# hängen bleiben, automatisch den ersten sichtbaren Zweig nehmen
		# (gleicher "nie blockieren"-Grundsatz wie Stufe 2 ohne Factory).
		_apply_choice(node, visible[0])
		return

	var ui = _choice_ui_factory.call()
	if ui is Node:
		_scene_tree.root.add_child(ui)
	ui.present(labels, func(idx: int) -> void:
		_apply_choice(node, visible[idx])
	, _render_text(node))

func _apply_choice(node: DialogueNode, choice: DialogueChoice) -> void:
	AppLogger.log_debug("Zweig '%s' → '%s' (Aktion '%s')" % [node.id, choice.next_node_id, choice.action], "DialogueTree")
	if choice.action.begins_with("start_quest:"):
		var quest_id := choice.action.substr("start_quest:".length())
		_bus.quest().emit_quest_start_requested(quest_id)
	_current_node_id = choice.next_node_id
	_show_node(_current_node_id)

## Bedingungsprüfung für choice.condition — siehe Klassenkommentar für die
## unterstützte Mini-Syntax. Mehrere durch "," getrennte Teilbedingungen
## werden als UND verknüpft (z.B. "quest_not_active:Q,quest_not_completed:Q"
## für "wurde noch nie gestartet") — siehe build_quest_giver() für den
## Hauptanwendungsfall. Ohne QuestService (_quest_service == null) oder ohne
## _player_id gilt jede NICHT-leere Bedingung als "nicht erfüllt" (sicherer
## Default: siehe Feldkommentar oben).
func _eval_condition(condition: String) -> bool:
	if condition.is_empty():
		return true
	for part in condition.split(","):
		if not _eval_single_condition(part.strip_edges()):
			return false
	return true

func _eval_single_condition(condition: String) -> bool:
	if _quest_service == null or _player_id.is_empty():
		# Nie still: eine Bedingung, die nicht ausgewertet werden kann, ist ein
		# Konfigurations-/Identitätsfehler (früher: stiller Fallback-Text, Quest-Bug).
		AppLogger.log_error(
			"Bedingung '%s' nicht auswertbar: QuestService=%s, player_id='%s'." % [
				condition, "ja" if _quest_service != null else "NEIN", _player_id],
			"DialogueTree"
		)
		return false
	var parts := condition.split(":", true, 1)
	if parts.size() != 2:
		AppLogger.log_warn("DialogueTreeController: ungültige condition '%s'." % condition, "DialogueTree")
		return false
	var op := parts[0]
	var quest_id := parts[1]
	match op:
		"quest_completed":
			return _quest_service.is_quest_completed(quest_id, _player_id)
		"quest_not_completed":
			return not _quest_service.is_quest_completed(quest_id, _player_id)
		"quest_active":
			return _quest_service.is_quest_active(quest_id, _player_id)
		"quest_not_active":
			return not _quest_service.is_quest_active(quest_id, _player_id)
		_:
			AppLogger.log_warn("DialogueTreeController: unbekannter condition-Operator '%s'." % op, "DialogueTree")
			return false

## Rendert node.text — reiner Durchreich-Fall für normale Knoten, bei
## with_progress()-Knoten wird text als Format-String mit dem aktuellen
## Live-Fortschritt gefüllt (siehe DialogueNode.progress_quest_id-Kommentar).
func _render_text(node: DialogueNode) -> String:
	if node.progress_quest_id.is_empty():
		return node.text
	var current := 0
	if _quest_service != null and not _player_id.is_empty():
		current = _quest_service.get_objective_progress(node.progress_quest_id, node.progress_obj_id, _player_id)
	return node.text % [current, node.progress_required]

func _show_dialog(text: String) -> void:
	_dialog_label.text    = text
	_dialog_label.visible = true
	_scene_tree.create_timer(5.0).timeout.connect(func():
		if is_instance_valid(_dialog_label):
			_dialog_label.visible = false
	)
	_bus.world().emit_interaction_reward_text(text.replace("\n", " "))

## Baut einen fertigen "Standard-Questgeber"-Baum aus denselben kompakten
## Parametern, die früher das Slot-System (set_next_quest()) genutzt
## hat — die Stufe-3-Entsprechung für NPCs, die trotzdem die volle
## Baum-Engine wollen (z.B. um später eigene Zweige reinzuhängen, siehe
## VillageElderNPC.gd für ein Beispiel ohne diese Factory). Reproduziert das
## Slot-System-Verhalten 1:1: offen → (annehmen, startet die Quest sofort) →
## aktiv (Live-Fortschritt) → erledigt, optional eine zweite Kettenstufe.
## Niemals ein Auswahlmenü für den Normalfall (siehe _show_node()
## Single-Choice-Autoskip) — der Router-Knoten "entry" hat durch die sich
## gegenseitig ausschließenden UND-Bedingungen immer GENAU einen sichtbaren
## Zweig.
##
## Siehe auch scripts/agent/build/quest_npc_scaffold.py, das genau dieses
## Muster aus einer kompakten JSON-Spec als fertige .gd-Datei generiert.
static func build_quest_giver(
	label: Label3D, tree: SceneTree, bus: IEventBus, quest_service: QuestService,
	quest_id: String, obj_id: String, required: int,
	offer_text: String, encourage_format: String, completed_text: String,
	next_quest_id: String = "", next_obj_id: String = "", next_required: int = 1,
	next_offer_text: String = "", next_encourage_format: String = "", next_completed_text: String = ""
) -> DialogueTreeController:
	var dt := DialogueTreeController.new(label, tree, bus, quest_service)

	dt.add_node("offer1", offer_text).add_choice("(annehmen)", "active1", "start_quest:%s" % quest_id)
	dt.add_node("active1", encourage_format).with_progress(quest_id, obj_id, required)

	if next_quest_id.is_empty():
		dt.add_node("done1", completed_text)
		# Fallback-Text (offer_text) nur relevant wenn _quest_service fehlt
		# oder _player_id leer ist — dann ist laut _eval_condition() JEDE
		# Bedingung "nicht erfüllt" und KEINER der drei Zweige sichtbar.
		dt.add_node("entry", offer_text) \
			.add_choice("", "active1", "", "quest_active:%s" % quest_id) \
			.add_choice("", "offer1", "", "quest_not_active:%s,quest_not_completed:%s" % [quest_id, quest_id]) \
			.add_choice("", "done1", "", "quest_completed:%s" % quest_id)
	else:
		dt.add_node("offer2", next_offer_text).add_choice("(annehmen)", "active2", "start_quest:%s" % next_quest_id)
		dt.add_node("active2", next_encourage_format).with_progress(next_quest_id, next_obj_id, next_required)
		dt.add_node("done2", next_completed_text)
		dt.add_node("entry", offer_text) \
			.add_choice("", "active1", "", "quest_active:%s" % quest_id) \
			.add_choice("", "offer1", "", "quest_not_active:%s,quest_not_completed:%s" % [quest_id, quest_id]) \
			.add_choice("", "active2", "", "quest_active:%s" % next_quest_id) \
			.add_choice("", "offer2", "", "quest_completed:%s,quest_not_active:%s,quest_not_completed:%s" % [quest_id, next_quest_id, next_quest_id]) \
			.add_choice("", "done2", "", "quest_completed:%s" % next_quest_id)

	dt.set_start_node("entry")
	return dt
