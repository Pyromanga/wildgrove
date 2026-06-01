class_name ContextMenuController

var _hud: HUD
var _event_bus: Object

func setup(hud: HUD, event_bus: Object) -> void:
    _hud = hud
    _event_bus = event_bus
    _event_bus.request_context_menu.connect(_on_open_requested)

func _on_open_requested() -> void:
    # Jetzt holt sich der Controller den Spieler erst, wenn er wirklich gebraucht wird
    var player = Engine.get_main_loop().root.get_first_node_in_group("player")
    if player and player.has_method("get_context_actions"):
        _show_menu(player.get_context_actions())

func _show_menu(actions: Array) -> void:
    # Hier kommt deine existierende Logik zum Menü-Aufbau hin...