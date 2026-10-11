# res://tests/unit/test_pause_menu_controller.gd
extends GutTest

## Tests für PauseMenuController — IV-03 (AUDIT-03).
##
## PauseMenuController extends Node — setup() verbindet menu_button.pressed,
## _ready() verbindet interaction_started auf _ctx.bus().world().
## Positiv-Test: _on_save() emittiert save_requested auf dem Mock-Bus.
## Isolation: AutoLoad-EventBus erreicht den Controller nicht.

var _ctrl: PauseMenuController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: PauseMenuVisuals

func before_each() -> void:
	_canvas = add_child_autofree(CanvasLayer.new())
	_visuals = PauseMenuVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = PauseMenuController.new()
	_ctrl.setup(_visuals, _ctx)
	add_child_autofree(_ctrl)
	# _ready() feuert → interaction_started verbunden

func test_ready_connects_interaction_started_on_injected_bus() -> void:
	assert_true(
		_bus.world().interaction_started.is_connected(_ctrl._on_interaction_started),
		"_ready() muss interaction_started auf dem injizierten Bus verbinden"
	)

func test_on_save_emits_save_requested_on_mock_bus() -> void:
	watch_signals(_bus.persistence())
	_ctrl._on_save()
	assert_signal_emitted(_bus.persistence(), "save_requested",
		"_on_save() muss save_requested auf dem injizierten Mock-Bus emittieren")

func test_real_autoload_interaction_started_does_not_reach_controller() -> void:
	# PauseMenuController schließt das Menü bei interaction_started
	# Wenn AutoLoad den Controller erreichbar wäre, würde close() aufgerufen werden.
	# Wir prüfen, dass der AutoLoad NICHT verbunden ist.
	assert_false(
		EventBus.world.interaction_started.is_connected(_ctrl._on_interaction_started),
		"Der echte AutoLoad-EventBus darf PauseMenuController nicht erreichen"
	)
