extends RefCounted
class_name JoystickController

const LOG_CAT := "UI/Joystick"

var base: ColorRect
var knob: ColorRect

func setup(hud: CanvasLayer, player: Node) -> void:
    Logger.log_debug("Initialisiere Joystick-Controller...", LOG_CAT)
    
    var touch = player.get_node_or_null("TouchInput")
    if not touch:
        Logger.log_error("TouchInput-Node fehlt auf dem Player!", LOG_CAT)
        return

    # Visuals bauen
    base = ColorRect.new()
    base.custom_minimum_size = Vector2(180, 180)
    base.color = Color(1, 1, 1, 0.2)
    base.visible = false
    base.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    knob = ColorRect.new()
    knob.custom_minimum_size = Vector2(60, 60)
    knob.color = Color(1, 1, 1, 0.8)
    knob.visible = false
    knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    hud.add_child(base)
    hud.add_child(knob)

    # Verbindung mit Logging
    var js_radius = 90.0
    if "JS_RADIUS" in touch: js_radius = touch.JS_RADIUS

    touch.joystick_activated.connect(func(origin): 
        Logger.log_debug("Joystick aktiviert bei %s" % str(origin), LOG_CAT)
        _on_activated(origin, js_radius)
    )
    
    touch.joystick_moved.connect(func(origin, offset): 
        # Achtung: Moved-Log nur bei Bedarf loggen, sonst flutet es das Log!
        _on_moved(origin, offset, js_radius)
    )
    
    touch.joystick_released.connect(func():
        Logger.log_debug("Joystick losgelassen", LOG_CAT)
        _on_released()
    )
    
    Logger.log_debug("Joystick-Controller vollständig verbunden.", LOG_CAT)

func _on_activated(origin: Vector2, radius: float) -> void:
    base.visible = true
    knob.visible = true
    base.global_position = origin - Vector2(radius, radius)
    knob.global_position = origin - knob.size * 0.5

func _on_moved(origin: Vector2, offset: Vector2, radius: float) -> void:
    base.global_position = origin - Vector2(radius, radius)
    knob.global_position = origin + offset - knob.size * 0.5

func _on_released() -> void:
    base.visible = false
    knob.visible = false