class_name InteractionButtonController

var _visuals: InteractionButtonVisuals # Korrigiert: Typ muss hier zum Visuals-Namen passen
var _player: Node

# Wir übergeben den Player bei der Initialisierung!
func setup(visuals: InteractionButtonVisuals, player: Node) -> void:
    _visuals = visuals
    _player = player

func _process(_delta: float) -> void:
    # Jetzt ist er eine "passive" Klasse, die nur noch mit dem arbeitet, was sie hat
    if not is_instance_valid(_player): return
    
    var target = null
    if _player.has_method("_get_closest_interactable"):
        target = _player._get_closest_interactable()
    _visuals.set_active(target != null)