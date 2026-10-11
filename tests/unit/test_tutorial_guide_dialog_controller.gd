# res://tests/unit/test_tutorial_guide_dialog_controller.gd
extends GutTest

## Unit-Tests für TutorialGuideDialogController (ADR-048 Round 106,
## Tutorial-Teil 2).
##
## Identisches Test-Setup wie test_quest_npc_dialog_controller.gd —
## MockEventBus + echtes Label3D + der Haupt-SceneTree für create_timer().
##
## Abgedeckt:
##   - on_interact(): zeigt Tipps der Reihe nach, einen pro Aufruf
##   - nach dem letzten Tipp: Abschlusszeile, danach Reset auf Tipp 1
##   - _show_dialog(): setzt Label-Text/Sichtbarkeit, emittiert
##     interaction_reward_text über den injizierten Bus, ohne Zeilenumbrüche

var _bus:   MockEventBus
var _label: Label3D
var _tree:  SceneTree

func before_each() -> void:
	_bus   = MockEventBus.new()
	_label = add_child_autofree(Label3D.new())
	_tree  = Engine.get_main_loop() as SceneTree

func _make_controller() -> TutorialGuideDialogController:
	return TutorialGuideDialogController.new(_label, _tree, _bus)

# ─────────────────────────────────────────────────────────────────────────────
# on_interact() — Tipp-Reihe
# ─────────────────────────────────────────────────────────────────────────────

func test_init_starts_at_first_tip() -> void:
	var c := _make_controller()
	c.on_interact()
	assert_eq(_label.text, TutorialGuideDialogController.TIPS[0])

func test_second_interact_shows_second_tip() -> void:
	var c := _make_controller()
	c.on_interact()
	c.on_interact()
	assert_eq(_label.text, TutorialGuideDialogController.TIPS[1])

func test_walks_through_all_tips_in_order() -> void:
	var c := _make_controller()
	for i in TutorialGuideDialogController.TIPS.size():
		c.on_interact()
		assert_eq(_label.text, TutorialGuideDialogController.TIPS[i], "Tipp %d muss der Reihe nach kommen." % i)

func test_after_last_tip_shows_closing_line() -> void:
	var c := _make_controller()
	for i in TutorialGuideDialogController.TIPS.size():
		c.on_interact()
	c.on_interact()
	assert_true("sprich einfach nochmal" in _label.text, "Nach dem letzten Tipp muss eine Abschlusszeile kommen.")

func test_after_closing_line_starts_over_from_first_tip() -> void:
	var c := _make_controller()
	for i in TutorialGuideDialogController.TIPS.size():
		c.on_interact()
	c.on_interact()  # Abschlusszeile
	c.on_interact()  # muss wieder bei Tipp 1 beginnen
	assert_eq(_label.text, TutorialGuideDialogController.TIPS[0])

func test_tips_are_never_empty() -> void:
	for tip in TutorialGuideDialogController.TIPS:
		assert_true((tip as String).length() > 0)

# ─────────────────────────────────────────────────────────────────────────────
# _show_dialog() — Bus-Integration (identisch DialogueTreeController)
# ─────────────────────────────────────────────────────────────────────────────

func test_show_dialog_makes_label_visible() -> void:
	var c := _make_controller()
	c.on_interact()
	assert_true(_label.visible)

func test_on_interact_emits_reward_text_via_bus() -> void:
	var c := _make_controller()
	watch_signals(_bus.world())
	c.on_interact()
	assert_signal_emitted(_bus.world(), "interaction_reward_text",
		"_show_dialog() muss interaction_reward_text über injizierten Bus emittieren")

func test_show_dialog_strips_newlines_for_reward_text() -> void:
	var c := _make_controller()
	watch_signals(_bus.world())
	c.on_interact()
	var params = get_signal_parameters(_bus.world(), "interaction_reward_text")
	if params != null:
		assert_false("\n" in params[0], "interaction_reward_text darf keine Zeilenumbrüche enthalten")
