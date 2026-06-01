extends RefCounted
class_name JoystickController

func setup(player: Node) -> void:
    var touch = player.get_node_or_null("TouchInput")
    if not touch: return

    # Input -> Signal (Übersetzung)
    touch.joystick_activated.connect(func(origin): 
        Kernel.events.ui.emit_joystick_toggled(true, origin)
    )
    
    touch.joystick_moved.connect(func(origin, offset): 
        # Wir geben die rohen Daten weiter. 
        # Die Regie (HUDManager) berechnet daraus das Aussehen.
        Kernel.events.ui.emit_joystick_moved(origin, offset)
    )
    
    touch.joystick_released.connect(func():
        Kernel.events.ui.emit_joystick_toggled(false)
    )