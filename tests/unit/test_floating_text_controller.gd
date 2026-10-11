# res://tests/unit/test_floating_text_controller.gd
extends GutTest

## Tests für FloatingTextController — IV-03 (AUDIT-03).
##
## FloatingTextController extends RefCounted — setup() verbindet drei Signale
## auf _ctx.bus().player() und _ctx.bus().ui().
## Positiv-Test: xp_gained via Mock → spawn_text aufgerufen (Text erscheint im Canvas).
## Isolations-Beweis: AutoLoad-EventBus erreicht den Controller nicht.

var _ctrl: FloatingTextController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: FloatingTextVisuals

func before_each() -> void:
	_canvas = add_child_autofree(CanvasLayer.new())
	_visuals = FloatingTextVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = FloatingTextController.new()
	_ctrl.setup(_visuals, _ctx)

func test_setup_connects_xp_gained_on_injected_bus() -> void:
	assert_true(
		_bus.player().xp_gained.is_connected(_ctrl._on_xp_gained),
		"setup() muss xp_gained auf dem injizierten Bus verbinden"
	)

func test_xp_gained_spawns_label_in_canvas() -> void:
	_bus.player().emit_xp_gained("combat", 50)
	var labels := _canvas.get_children()
	assert_true(labels.size() > 0, "xp_gained über Mock-Bus muss einen Label-Node spawnen")

func test_real_autoload_does_not_reach_controller() -> void:
	var count_before := _canvas.get_child_count()
	EventBus.player.emit_xp_gained("combat", 99)
	assert_eq(
		_canvas.get_child_count(), count_before,
		"Der echte AutoLoad-EventBus darf FloatingTextController nicht mehr erreichen"
	)
