# res://tests/unit/test_notification_controller.gd
extends GutTest

## Tests für NotificationController — I-02 (AUDIT-03).
##
## VORHER: setup() verband EventBus.ui.notification_requested direkt mit dem AutoLoad.
## NACHHER: setup() nimmt einen IUIContext entgegen, verbindet über _ctx.bus().ui().
## NotificationController ist ein reines RefCounted-Objekt (kein extends Node) —
## der einfachste Fall der I-02-Fixliste.

var _ctrl: NotificationController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: NotificationVisuals

func before_each() -> void:
	# show_popup() braucht _parent.get_tree() → CanvasLayer muss im echten Tree sein.
	_canvas = add_child_autofree(CanvasLayer.new())
	_visuals = NotificationVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = NotificationController.new()
	_ctrl.setup(_visuals, _ctx)

func test_setup_connects_to_injected_mock_bus() -> void:
	assert_true(
		_bus.ui().notification_requested.is_connected(_ctrl.show),
		"setup() muss notification_requested auf dem injizierten Bus verbinden"
	)

func test_mock_bus_notification_shows_popup() -> void:
	_bus.ui().notification_requested.emit("Gespeichert!")
	var popups := _canvas.get_tree().get_nodes_in_group("popup_message")
	assert_eq(popups.size(), 1, "Popup muss über den injizierten Mock-Bus erscheinen")

func test_real_autoload_event_bus_does_not_reach_controller() -> void:
	# Der entscheidende Beweis für I-02: der reale EventBus-AutoLoad darf den
	# Controller nicht mehr erreichen.
	EventBus.ui.emit_notification_requested("Sollte ignoriert werden")
	var popups := _canvas.get_tree().get_nodes_in_group("popup_message")
	assert_eq(popups.size(), 0, "Der echte AutoLoad-EventBus darf NotificationController nicht mehr erreichen")
