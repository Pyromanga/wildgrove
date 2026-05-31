extends RefCounted
class_name JoystickController

# Alle Visuals und Logik-Referenzen wandern hier rein
var base: ColorRect
var knob: ColorRect

func setup(hud: CanvasLayer, player: Node) -> void:
    # 1. VISUALS ERSTELLEN (Waren vorher in UIFactory)
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

    # 2. LOGIK VERBINDEN
    var touch = player.get_node_or_null("TouchInput")
    if not touch: return
    
    var js_radius = 90.0
    if "JS_RADIUS" in touch: js_radius = touch.JS_RADIUS

    touch.joystick_activated.connect(_on_activated.bind(js_radius))
    touch.joystick_moved.connect(_on_moved.bind(js_radius))
    touch.joystick_released.connect(_on_released)

# 3. INTERNE METHODEN (Die "ewig vielen" Zeilen aus der UIFactory)
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