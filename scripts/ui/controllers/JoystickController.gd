extends RefCounted
class_name JoystickController

## Kapselt die komplette Verbindung zwischen Player-Input und UI-Nodes
func setup(hud: CanvasLayer, player: Node) -> void:
    var touch = player.get_node_or_null("TouchInput")
    if not touch: return

    # Wir lassen die Factory die Nodes bauen, der Controller verbindet nur
    var base := ColorRect.new()
    base.custom_minimum_size = Vector2(180, 180)
    base.color = Color(1, 1, 1, 0.2)
    base.visible = false
    hud.add_child(base)
    
    # ... hier die connect-Logik rein ...
    touch.joystick_activated.connect(func(pos): base.visible = true)