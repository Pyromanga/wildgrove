# res://tests/unit/test_interaction_button_controller.gd
extends GutTest

## Tests für InteractionButtonController — IV-03 (AUDIT-03).
##
## InteractionButtonController extends Node — verbindet sich in _ready() auf 4 Signale
## via _ctx.bus().world() und _ctx.bus().ui().
## Positiv-Test: proximity_changed(target, true) → button aktiv.
## Isolation: AutoLoad-EventBus erreicht Controller nicht.

var _ctrl: InteractionButtonController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: InteractionButtonVisuals

func before_each() -> void:
	_canvas = add_child_autofree(CanvasLayer.new())
	_visuals = InteractionButtonVisuals.new(_canvas, Vector2.ZERO)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = InteractionButtonController.new()
	_ctrl.setup(_visuals, _ctx)
	add_child_autofree(_ctrl)
	# _ready() feuert → Signale verbunden

func test_ready_connects_proximity_changed_on_injected_bus() -> void:
	assert_true(
		_bus.world().proximity_changed.is_connected(_ctrl._on_proximity_changed),
		"_ready() muss proximity_changed auf dem injizierten Bus verbinden"
	)

func test_proximity_in_range_activates_button() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	_bus.world().emit_proximity_changed(target, true)
	assert_true(_visuals.button.visible, "Button muss sichtbar sein wenn Ziel in Reichweite")

func test_real_autoload_does_not_reach_controller() -> void:
	_visuals.button.visible = false
	var target := Node3D.new()
	add_child_autofree(target)
	EventBus.world.emit_proximity_changed(target, true)
	assert_false(
		_visuals.button.visible,
		"Der echte AutoLoad-EventBus darf InteractionButtonController nicht mehr erreichen"
	)
