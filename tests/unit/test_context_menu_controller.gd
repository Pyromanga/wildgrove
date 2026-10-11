# res://tests/unit/test_context_menu_controller.gd
extends GutTest

## Tests für ContextMenuController — IV-03 (AUDIT-03).
##
## ContextMenuController extends RefCounted (kein Node) — setup() verbindet
## request_context_menu auf _ctx.bus().ui() direkt (kein _ready() nötig).
## Tests prüfen: Verbindung auf Mock, Abwesenheit der AutoLoad-Verbindung,
## und dass show() direkt Aktionen ohne Player-Lookup anzeigen kann.

var _ctrl: ContextMenuController
var _ctx: UIContext
var _bus: MockEventBus
var _hud: CanvasLayer   # ContextMenuController braucht HUD als Node-Proxy

func before_each() -> void:
	_hud = add_child_autofree(HUD.new())
	_hud.add_to_group("hud_canvas")

	_bus = MockEventBus.new()
	_ctx = UIContext.for_test()
	_ctx._bus = _bus

	_ctrl = ContextMenuController.new()
	_ctrl.setup(_hud as HUD, _ctx)

func test_setup_connects_request_context_menu_on_injected_bus() -> void:
	assert_true(
		_bus.ui().request_context_menu.is_connected(_ctrl._on_open_requested),
		"setup() muss request_context_menu auf dem injizierten Bus verbinden"
	)

func test_show_with_empty_actions_does_not_crash() -> void:
	# Leere Aktion-Liste → kein Menü, kein Crash
	_ctrl.show([])
	assert_true(true, "show([]) darf nicht crashen")

func test_real_autoload_does_not_reach_controller() -> void:
	# Isolation: echter EventBus-AutoLoad verbindet sich nicht mit diesem Controller
	assert_false(
		EventBus.ui.request_context_menu.is_connected(_ctrl._on_open_requested),
		"Der echte AutoLoad-EventBus darf ContextMenuController nicht verbunden haben"
	)

# ── BUGFIX (2026-09-26, "Kontextmenü soll alles anzeigen was in der Nähe ist") ─────────

func test_open_requested_uses_all_nearby_context_actions() -> void:
	var mock_player := MockContextPlayer.new()
	add_child_autofree(mock_player)
	mock_player.add_to_group("player")

	_ctrl._on_open_requested()

	assert_eq(mock_player.all_nearby_call_count, 1,
		"_on_open_requested() muss get_all_nearby_context_actions() aufrufen — " +
		"nicht mehr nur das eine 'closest'-Ziel.")
	assert_eq(mock_player.single_target_call_count, 0,
		"Der alte Einzel-Ziel-Pfad get_context_actions() darf hier nicht mehr genutzt werden.")

func test_open_requested_shows_actions_from_all_nearby_targets() -> void:
	var mock_player := MockContextPlayer.new()
	add_child_autofree(mock_player)
	mock_player.add_to_group("player")

	var a1 := InteractableAction.new("chop", "Baum: Fällen")
	var a2 := InteractableAction.new("mine", "Erz: Abbauen")
	mock_player.actions_to_return = [a1, a2]

	_ctrl._on_open_requested()

	var menus := _hud.get_tree().get_nodes_in_group("context_menu")
	assert_gt(menus.size(), 0,
		"Aktionen von mehreren Zielen müssen zusammen EIN Kontextmenü öffnen.")
