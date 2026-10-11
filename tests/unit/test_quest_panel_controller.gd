# res://tests/unit/test_quest_panel_controller.gd
extends GutTest

## Tests für QuestPanelController — IV-03 (AUDIT-03).
##
## QuestPanelController extends Node — setup() verbindet 3 quest-Signale
## auf _ctx.bus().quest().
## Positiv-Test: quest_started via Mock → panel wird sichtbar.
## Isolation: AutoLoad-EventBus erreicht den Controller nicht.

var _ctrl: QuestPanelController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: QuestPanelVisuals

func before_each() -> void:
	_canvas = add_child_autofree(CanvasLayer.new())
	_visuals = QuestPanelVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = QuestPanelController.new()
	_ctrl.setup(_visuals, _ctx)
	add_child_autofree(_ctrl)

func test_setup_connects_quest_started_on_injected_bus() -> void:
	assert_true(
		_bus.quest().quest_started.is_connected(_ctrl._on_quest_started),
		"setup() muss quest_started auf dem injizierten Bus verbinden"
	)

func test_quest_started_makes_panel_visible() -> void:
	# _on_quest_started() setzt panel.visible = true
	# QuestService ist null (for_test) → _show_quest bricht früh ab, aber visible wird gesetzt
	_visuals.panel.visible = false
	_bus.quest().emit_quest_started("quest_intro")
	assert_true(_visuals.panel.visible,
		"quest_started über Mock-Bus muss das Quest-Panel sichtbar machen")

func test_real_autoload_does_not_reach_controller() -> void:
	_visuals.panel.visible = false
	EventBus.quest.emit_quest_started("should_be_ignored")
	assert_false(
		_visuals.panel.visible,
		"Der echte AutoLoad-EventBus darf QuestPanelController nicht mehr erreichen"
	)

# ─────────────────────────────────────────────────────────────────────────────
# _build_obj_data() — sequentielles Verbergen zukünftiger Schritte (Issue #3)
# ─────────────────────────────────────────────────────────────────────────────
## Muss "extends DataService" sein, da QuestService.configure() per DI-Konvention
## hart auf DataService castet (deps.get_optional(...) as DataService).
class QuestPanelTestDataHelper extends DataService:
	var _quests: Dictionary = {}
	func get_all_quests() -> Dictionary:  return _quests
	func get_auto_start_quests() -> Array[String]: return []

	class NoopSaveSystem extends SaveSystem:
		func register_save_provider(_p) -> void: pass
		func get_state_for(_key: String) -> Dictionary: return {}

func test_build_obj_data_hides_locked_future_step() -> void:
	var obj_talk := QuestObjective.new()
	obj_talk.id = "obj_talk"
	obj_talk.type = QuestObjective.Type.TALK
	obj_talk.target_id = "talia"
	obj_talk.required = 1

	var obj_kill := QuestObjective.new()
	obj_kill.id = "obj_kill"
	obj_kill.type = QuestObjective.Type.KILL
	obj_kill.target_id = "skeleton"
	obj_kill.required = 5

	var def := QuestDefinition.new()
	def.id = "quest_x"
	def.title = "Quest X"
	def.objectives = [obj_talk, obj_kill]

	var ds := QuestPanelTestDataHelper.new()
	ds._quests["quest_x"] = def

	var svc := QuestService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:        ds,
		ServiceKeys.SAVE_SYSTEM: QuestPanelTestDataHelper.NoopSaveSystem.new(),
		ServiceKeys.EVENT_BUS:   _bus,
	}))
	svc.on_ready()
	svc.request_start_quest("quest_x", "p1")
	_ctx._quest = svc
	_ctx._local_player_id = "p1"

	var data_before := _ctrl._build_obj_data("quest_x", def)
	assert_eq(data_before.size(), 1,
		"Vor Erfüllung von obj_talk darf obj_kill (Index 1) noch nicht angezeigt werden")
	assert_eq(data_before[0]["label"], obj_talk.label)

	svc.update_objective("quest_x", "obj_talk", 1, "p1")
	var data_after := _ctrl._build_obj_data("quest_x", def)
	assert_eq(data_after.size(), 2,
		"Nach Erfüllung von obj_talk muss obj_kill in der UI erscheinen")

	svc.on_cleanup()
