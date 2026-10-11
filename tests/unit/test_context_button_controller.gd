# res://tests/unit/test_context_button_controller.gd
extends GutTest

## Tests für ContextButtonController — IV-03 (AUDIT-03).
##
## ContextButtonController extends Node — muss via add_child_autofree() in den Tree.
## Verbindet sich in _ready() auf _ctx.bus().world().proximity_changed.
## Positiv-Test: proximity_changed(target, true) macht Button sichtbar.
## Isolations-Beweis: echter EventBus-AutoLoad erreicht den Controller nicht.

var _ctrl: ContextButtonController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: ContextButtonVisuals

func before_each() -> void:
	_canvas = add_child_autofree(CanvasLayer.new())
	_visuals = ContextButtonVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = ContextButtonController.new()
	_ctrl.setup(_visuals, _ctx)
	add_child_autofree(_ctrl)
	# _ready() feuert nach add_child — proximity_changed ist jetzt verbunden

func test_setup_connects_proximity_changed_on_injected_bus() -> void:
	assert_true(
		_bus.world().proximity_changed.is_connected(_ctrl._on_proximity_changed),
		"_ready() muss proximity_changed auf dem injizierten Bus verbinden"
	)

func test_proximity_changed_in_range_shows_button() -> void:
	var dummy_target := Node3D.new()
	add_child_autofree(dummy_target)
	_bus.world().emit_proximity_changed(dummy_target, true)
	assert_true(_visuals.button.visible, "Button muss sichtbar sein wenn Ziel in Reichweite")

func test_real_autoload_does_not_reach_controller() -> void:
	# Isolation: echter EventBus-AutoLoad darf den Controller nicht erreichen
	_visuals.button.visible = false
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	EventBus.world.emit_proximity_changed(dummy, true)
	assert_false(
		_visuals.button.visible,
		"Der echte AutoLoad-EventBus darf ContextButtonController nicht mehr erreichen"
	)
