# res://tests/unit/test_dialogue_tree_controller.gd
extends GutTest

## Unit-Tests für DialogueTreeController (ADR-051 Stufe 3).
##
## Abgedeckt:
##   - Knoten-Navigation über Choices (auch mehrstufig in einer Interaktion)
##   - Blattknoten (leere choices) zeigen Text und springen zum Start zurück
##   - Auswahl-UI wird über dieselbe Factory wie Stufe 2 injiziert
##   - Ohne Factory: automatisch erster sichtbarer Zweig (nie hängen bleiben)
##   - condition-Auswertung über eine ECHTE QuestService-Instanz (nicht nur
##     Mock) — genau der Fall, den Stufe 1/2 nicht konnten: ein Zweig reagiert
##     auf eine Quest, die dieser Dialog-Baum selbst gar nicht vergibt.
##   - action "start_quest:<id>" emittiert quest_start_requested über den Bus

var _bus:   MockEventBus
var _label: Label3D
var _tree:  SceneTree

func before_each() -> void:
	_bus   = MockEventBus.new()
	_label = add_child_autofree(Label3D.new())
	_tree  = Engine.get_main_loop() as SceneTree

func _make_controller(quest_service: QuestService = null) -> DialogueTreeController:
	return DialogueTreeController.new(_label, _tree, _bus, quest_service)

class FakeChoiceUI extends RefCounted:
	var presented_options: Array[String] = []
	var presented_title: String = ""
	var _on_chosen: Callable
	func present(options: Array[String], on_chosen: Callable, title: String = "") -> void:
		presented_options = options
		presented_title   = title
		_on_chosen        = on_chosen
	func choose(idx: int) -> void:
		_on_chosen.call(idx)

# ─────────────────────────────────────────────────────────────────────────────
# Grundnavigation
# ─────────────────────────────────────────────────────────────────────────────

func test_leaf_node_shows_text_without_ui() -> void:
	var dt := _make_controller()
	dt.add_node("start", "Hallo Fremder.")
	dt.set_start_node("start")
	dt.on_interact()
	assert_eq(_label.text, "Hallo Fremder.")

func test_leaf_node_resets_to_start_for_next_interaction() -> void:
	var dt := _make_controller()
	dt.add_node("start", "Erster Text").add_choice("Weiter", "leaf")
	dt.add_node("leaf", "Blatt-Text")
	dt.set_start_node("start")
	var fake := FakeChoiceUI.new()
	dt.set_choice_ui_factory(func() -> Variant: return fake)
	dt.on_interact()
	fake.choose(0)
	assert_eq(_label.text, "Blatt-Text")
	# Nächste Interaktion muss wieder von vorn beginnen.
	dt.on_interact()
	assert_eq(fake.presented_options.size(), 0, "Kein Menü mehr nötig")
	assert_eq(_label.text, "Erster Text")

func test_multi_step_navigation_within_one_interaction() -> void:
	# "mehrstufige Verzweigung innerhalb EINER Interaktion" (ADR-051 Stufe 3).
	var dt := _make_controller()
	dt.add_node("start", "A").add_choice("weiter", "mid")
	dt.add_node("mid", "B").add_choice("weiter", "leaf")
	dt.add_node("leaf", "C — Ende")
	dt.set_start_node("start")
	var fake := FakeChoiceUI.new()
	dt.set_choice_ui_factory(func() -> Variant: return fake)
	dt.on_interact()
	fake.choose(0)  # start -> mid, zeigt sofort die nächste Auswahl (kein 2. on_interact() nötig)
	assert_eq(fake.presented_title, "B", "Nach der 1. Wahl muss der NÄCHSTE Knoten schon präsentiert sein")
	fake.choose(0)  # mid -> leaf
	assert_eq(_label.text, "C — Ende")

func test_choice_ui_title_is_node_text() -> void:
	var dt := _make_controller()
	dt.add_node("start", "Was willst du wissen?").add_choice("Nichts.", "bye")
	dt.add_node("bye", "Tschüss.")
	dt.set_start_node("start")
	var fake := FakeChoiceUI.new()
	dt.set_choice_ui_factory(func() -> Variant: return fake)
	dt.on_interact()
	assert_eq(fake.presented_title, "Was willst du wissen?")

func test_without_factory_auto_picks_first_visible_choice() -> void:
	var dt := _make_controller()
	dt.add_node("start", "A").add_choice("erste", "leaf1").add_choice("zweite", "leaf2")
	dt.add_node("leaf1", "Erstes Blatt")
	dt.add_node("leaf2", "Zweites Blatt")
	dt.set_start_node("start")
	dt.on_interact()
	assert_eq(_label.text, "Erstes Blatt", "Ohne Factory nie hängen bleiben — erster sichtbarer Zweig gewinnt")

func test_start_quest_action_emits_quest_start_requested() -> void:
	var dt := _make_controller()
	dt.add_node("start", "A").add_choice("Klar, gib mir die Aufgabe.", "bye", "start_quest:quest_demo")
	dt.add_node("bye", "Viel Glück.")
	dt.set_start_node("start")
	var fake := FakeChoiceUI.new()
	dt.set_choice_ui_factory(func() -> Variant: return fake)
	watch_signals(_bus.quest())
	dt.on_interact()
	fake.choose(0)
	assert_signal_emitted_with_parameters(_bus.quest(), "quest_start_requested", ["quest_demo"])

# ─────────────────────────────────────────────────────────────────────────────
# condition-Auswertung — DER Kernpunkt von Stufe 3: Reaktion auf FREMDE Quests
# ─────────────────────────────────────────────────────────────────────────────

## Baut eine echte, minimal konfigurierte QuestService-Instanz mit genau einer
## Quest-Definition — gleiches Muster wie test_quest_custom_trigger.gd
## (dortiger Kommentar: "Muss extends DataService sein, da QuestService.
## configure() per DI-Konvention hart auf DataService castet").
func _make_quest_service(quest_id: String) -> QuestService:
	var obj := QuestObjective.new()
	obj.id        = "obj_x"
	obj.type      = QuestObjective.Type.TALK
	obj.target_id = "irgendwer"
	obj.required  = 1
	var def := QuestDefinition.new()
	def.id         = quest_id
	def.objectives = [obj]

	var ds := DialogueTestQuestDataHelper.new()
	ds._quests[quest_id] = def

	var svc := QuestService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:        ds,
		ServiceKeys.SAVE_SYSTEM: DialogueTestQuestDataHelper.NoopSaveSystem.new(),
		ServiceKeys.EVENT_BUS:   _bus,
	}))
	svc.on_ready()
	return svc

func test_condition_quest_not_completed_visible_by_default() -> void:
	var svc := _make_quest_service("quest_x")
	var dt := _make_controller(svc)
	dt.set_player_id("p1")
	dt.add_node("start", "A") \
		.add_choice("nur wenn noch offen", "leaf_open", "", "quest_not_completed:quest_x") \
		.add_choice("nur wenn erledigt", "leaf_done", "", "quest_completed:quest_x")
	dt.add_node("leaf_open", "Noch offen")
	dt.add_node("leaf_done", "Schon erledigt")
	dt.set_start_node("start")
	dt.on_interact()  # ohne Factory -> automatisch der erste SICHTBARE Zweig
	assert_eq(_label.text, "Noch offen", "quest_x ist frisch, also weder aktiv noch abgeschlossen")

func test_condition_reacts_to_foreign_quest_completion() -> void:
	# DER Beweis für Stufe 3: dieser Dialog-Baum vergibt quest_x selbst NICHT
	# (kein einziges add_choice() mit start_quest:quest_x) — trotzdem
	# reagiert sein Text auf deren Abschluss-Status.
	var svc := _make_quest_service("quest_x")
	svc.request_start_quest("quest_x", "p1")
	svc.request_complete_quest("quest_x", "p1")
	var dt := _make_controller(svc)
	dt.set_player_id("p1")
	dt.add_node("start", "A") \
		.add_choice("Neuigkeiten?", "leaf_done", "", "quest_completed:quest_x") \
		.add_choice("Neuigkeiten?", "leaf_open", "", "quest_not_completed:quest_x")
	dt.add_node("leaf_done", "Ich hab gehört, du hast es geschafft!")
	dt.add_node("leaf_open", "Noch nichts Neues.")
	dt.set_start_node("start")
	dt.on_interact()
	assert_eq(_label.text, "Ich hab gehört, du hast es geschafft!",
		"Muss auf den Abschluss einer fremden, selbst nicht vergebenen Quest reagieren")

func test_condition_reacts_to_foreign_quest_active() -> void:
	var svc := _make_quest_service("quest_x")
	svc.request_start_quest("quest_x", "p1")
	var dt := _make_controller(svc)
	dt.set_player_id("p1")
	dt.add_node("start", "A") \
		.add_choice("hi", "leaf_active", "", "quest_active:quest_x") \
		.add_choice("hi", "leaf_inactive", "", "quest_not_active:quest_x")
	dt.add_node("leaf_active", "Bist du deswegen hier?")
	dt.add_node("leaf_inactive", "Kenn ich nicht.")
	dt.set_start_node("start")
	dt.on_interact()
	assert_eq(_label.text, "Bist du deswegen hier?")

func test_condition_without_quest_service_hides_conditional_choice() -> void:
	# Sicherer Default (siehe DialogueTreeController._eval_condition()
	# Klassenkommentar): ohne QuestService gilt jede NICHT-leere Bedingung
	# als nicht erfüllt — lieber einen Zweig verstecken als einen falschen zeigen.
	var dt := _make_controller(null)
	dt.set_player_id("p1")
	dt.add_node("start", "A") \
		.add_choice("bedingt", "leaf_conditional", "", "quest_completed:irgendwas") \
		.add_choice("immer da", "leaf_always")
	dt.add_node("leaf_conditional", "Sollte nie erscheinen")
	dt.add_node("leaf_always", "Immer sichtbar")
	dt.set_start_node("start")
	dt.on_interact()
	assert_eq(_label.text, "Immer sichtbar")

func test_empty_condition_always_visible() -> void:
	var dt := _make_controller(null)
	dt.add_node("start", "A").add_choice("hallo", "leaf")
	dt.add_node("leaf", "B")
	dt.set_start_node("start")
	dt.on_interact()
	assert_eq(_label.text, "B")

# ─────────────────────────────────────────────────────────────────────────────
# build_quest_giver() — generische Factory, die ab 2026-09-27 von allen 6
# konvertierten NPC-Subklassen genutzt wird (siehe MinerNPC.gd etc.)
# ─────────────────────────────────────────────────────────────────────────────

func test_build_quest_giver_not_started_shows_offer_and_starts_on_accept() -> void:
	var svc := _make_quest_service("quest_x")
	var dt := DialogueTreeController.build_quest_giver(
		_label, _tree, _bus, svc, "quest_x", "obj_x", 3,
		"Offen-Text", "Aktiv %d/%d", "Fertig-Text"
	)
	dt.set_player_id("p1")
	watch_signals(_bus.quest())
	dt.on_interact()
	# Kein Menü (einziger sichtbarer Router-Zweig) — direkt der Angebotstext,
	# UND das Annehmen (einziger Choice im offer-Knoten) läuft im selben
	# on_interact()-Aufruf gleich mit durch (mehrstufige Navigation).
	assert_signal_emitted_with_parameters(_bus.quest(), "quest_start_requested", ["quest_x"])

func test_build_quest_giver_active_shows_live_progress() -> void:
	var svc := _make_quest_service("quest_x")
	svc.request_start_quest("quest_x", "p1")
	# Kein öffentlicher "request_objective_progress"-Pfad ohne volle
	# Domain-Event/NetworkBridge-Pipeline — Fortschritt direkt am
	# QuestProgressRecord gesetzt, analog zu anderen Tests, die QuestService
	# ohne Netzwerk-Unterbau betreiben.
	svc.get_quest_record("quest_x", "p1").objectives["obj_x"] = 2
	var dt := DialogueTreeController.build_quest_giver(
		_label, _tree, _bus, svc, "quest_x", "obj_x", 3,
		"Offen-Text", "Aktiv %d/%d", "Fertig-Text"
	)
	dt.set_player_id("p1")
	dt.on_interact()
	assert_eq(_label.text, "Aktiv 2/3")

func test_build_quest_giver_completed_shows_done_text() -> void:
	var svc := _make_quest_service("quest_x")
	svc.request_start_quest("quest_x", "p1")
	svc.request_complete_quest("quest_x", "p1")
	var dt := DialogueTreeController.build_quest_giver(
		_label, _tree, _bus, svc, "quest_x", "obj_x", 3,
		"Offen-Text", "Aktiv %d/%d", "Fertig-Text"
	)
	dt.set_player_id("p1")
	dt.on_interact()
	assert_eq(_label.text, "Fertig-Text")

func test_build_quest_giver_chains_to_second_stage_after_completion() -> void:
	var svc := _make_quest_service("quest_x")
	svc.request_start_quest("quest_x", "p1")
	svc.request_complete_quest("quest_x", "p1")
	var dt := DialogueTreeController.build_quest_giver(
		_label, _tree, _bus, svc, "quest_x", "obj_x", 3,
		"Offen-Text", "Aktiv %d/%d", "Fertig-Text",
		"quest_y", "obj_y", 2, "Offen2-Text", "Aktiv2 %d/%d", "Fertig2-Text"
	)
	dt.set_player_id("p1")
	watch_signals(_bus.quest())
	dt.on_interact()
	assert_signal_emitted_with_parameters(_bus.quest(), "quest_start_requested", ["quest_y"])

func test_build_quest_giver_never_shows_a_menu_for_the_standard_path() -> void:
	# Kernanspruch: der Router hat immer GENAU einen sichtbaren Zweig, also
	# nie ein Auswahlmenü für den Normalfall — auch mit gesetzter Factory.
	var svc := _make_quest_service("quest_x")
	var dt := DialogueTreeController.build_quest_giver(
		_label, _tree, _bus, svc, "quest_x", "obj_x", 3,
		"Offen-Text", "Aktiv %d/%d", "Fertig-Text"
	)
	dt.set_player_id("p1")
	var fake := FakeChoiceUI.new()
	dt.set_choice_ui_factory(func() -> Variant: return fake)
	dt.on_interact()
	assert_eq(fake.presented_options.size(), 0, "Standard-Questgeber-Pfad darf nie ein Menü zeigen")

## Analog zu QuestServiceTestHelper in test_quest_custom_trigger.gd — eigene,
## unabhängige Kopie statt Cross-Test-Import (GUT-Testdateien sind bewusst
## eigenständig, kein gemeinsamer Test-Support-Ordner in diesem Projekt).
class DialogueTestQuestDataHelper extends DataService:
	func get_all_quests() -> Dictionary: return _quests
	func get_auto_start_quests() -> Array[String]: return []

	class NoopSaveSystem extends SaveSystem:
		func register_save_provider(_p) -> void: pass
		func get_state_for(_key: String) -> Dictionary: return {}

# ── Regression (Quest-Bug): Dialog ohne QuestService startet keine Quest ──

func test_quest_giver_without_service_starts_nothing() -> void:
	var dt := DialogueTreeController.build_quest_giver(
		_label, _tree, _bus, null, "quest_x", "obj_x", 3, "Offen-Text", "Aktiv %d/%d", "Fertig-Text")
	watch_signals(_bus.quest())
	dt.on_interact()
	assert_signal_not_emitted(_bus.quest(), "quest_start_requested")
