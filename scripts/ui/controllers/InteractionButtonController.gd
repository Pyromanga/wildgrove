# scripts/ui/controllers/interaction_button_controller.gd
class_name InteractionButtonController

var _visuals: ButtonVisuals
var _player: Node

func setup(visuals: ButtonVisuals) -> void:
    _visuals = visuals
    # Spieler suchen (oder über Kernel)
    var players = Engine.get_main_loop().root.get_nodes_in_group("player")
    if not players.is_empty():
        _player = players[0]

func _process(_delta: float) -> void:
    if not is_instance_valid(_player): return
    
    var target = null
    if _player.has_method("_get_closest_interactable"):
        target = _player._get_closest_interactable()
        
    _visuals.set_active(target != null)