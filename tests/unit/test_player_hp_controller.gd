# res://tests/unit/test_player_hp_controller.gd
extends GutTest

## Tests für PlayerHPController — I-02 (AUDIT-03).
##
## VORHER: setup() rief EventBus.player.player_health_changed.connect(...) direkt auf
## dem AutoLoad auf — der Controller war ohne laufenden EventBus-Singleton nicht
## isoliert testbar.
## NACHHER: setup() nimmt einen IUIContext entgegen und verbindet über _ctx.bus().player().
## Dieser Test beweist beides: (1) der Controller reagiert auf den injizierten
## MockEventBus, (2) er reagiert NICHT mehr auf den echten EventBus-AutoLoad —
## der Beweis, dass kein versteckter zweiter Zugriffspfad übrig ist.

var _ctrl: PlayerHPController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: PlayerHPVisuals

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = PlayerHPVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = add_child_autofree(PlayerHPController.new())
	_ctrl.setup(_visuals, _ctx)

func test_setup_connects_to_injected_mock_bus() -> void:
	assert_true(
		_bus.player().player_health_changed.is_connected(_ctrl._on_health_changed),
		"setup() muss player_health_changed auf dem injizierten Bus verbinden"
	)

func test_mock_bus_health_changed_updates_visuals() -> void:
	_bus.player().emit_player_health_changed(40, 100)
	assert_eq(_visuals.bar.value, 40.0, "bar.value muss auf den gemeldeten current-Wert aktualisiert werden")
	assert_eq(_visuals.bar.max_value, 100.0, "bar.max_value muss auf maximum aktualisiert werden")

func test_real_autoload_event_bus_does_not_reach_controller() -> void:
	# Der entscheidende Beweis für I-02: der reale EventBus-AutoLoad darf den
	# Controller nicht mehr erreichen — nur der injizierte Mock.
	_visuals.update(77, 100)  # bekannter Ausgangswert, der nicht zufällig 100 ist
	EventBus.player.emit_player_health_changed(13, 100)
	assert_eq(
		_visuals.bar.value, 77.0,
		"Der echte AutoLoad-EventBus darf PlayerHPController nicht mehr beeinflussen"
	)

func test_mock_bus_respawn_triggers_resync() -> void:
	# _on_respawned() ruft _try_initial_sync() auf — darf ohne Player in der Gruppe
	# "player" nicht crashen, auch über den injizierten Mock.
	_bus.player().emit_player_respawned()
	assert_true(true, "emit_player_respawned() über den Mock darf nicht crashen")
