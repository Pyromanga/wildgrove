# scripts/ui/controllers/interaction_button_controller.gd
class_name InteractionButtonController

var _visuals: ButtonVisuals
var _player: Node

func setup(visuals: ButtonVisuals) -> void:
    _visuals = visuals
    # Suche den Spieler im Baum (oder über den Service-Locator)
    var players = Engine.get_main_loop().root.get_nodes_in_group("player")
    if not players.is_empty():
        _player = players[0]

func _process(_delta: float) -> void:
    if not is_instance_valid(_player): return
    
    var target = null
    if _player.has_method("_get_closest_interactable"):
        target = _player._get_closest_interactable()
        
    # Wir sagen den Visuals nur: "Ändere den Status"
    _visuals.set_active(target != null)