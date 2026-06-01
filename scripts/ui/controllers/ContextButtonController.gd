# scripts/ui/controllers/context_button_controller.gd
class_name ContextButtonController

var _visuals: ButtonVisuals
var _context_menu_ctrl: ContextMenuController
var _hud: HUD

func setup(visuals: ButtonVisuals, context_ctrl: ContextMenuController, hud: HUD) -> void:
    _visuals = visuals
    _context_menu_ctrl = context_ctrl
    _hud = hud
    
    # Hier verbinden wir den Button aus den Visuals direkt mit unserem Befehl
    _visuals.context_btn.pressed.connect(_on_context_button_pressed)

func _on_context_button_pressed() -> void:
    # 1. Spieler finden, der die Aktionen liefern kann
    var player = Engine.get_main_loop().root.get_first_node_in_group("player")
    if player and player.has_method("get_context_actions"):
        var actions = player.get_context_actions()
        # 2. Kontextmenü-Controller aufrufen
        _context_menu_ctrl.show(_hud, actions)