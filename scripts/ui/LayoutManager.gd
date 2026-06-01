extends Node
class_name LayoutManager

func get_button_position(index: int) -> Vector2:
    # Berechnet dynamisch die Position der Buttons
    var margin = 30.0
    var size = 150.0
    return Vector2(...) # Hier die Mathematik

func get_inventory_rect() -> Rect2:
    # Berechnet, wo das Inventar liegen soll
    return Rect2(...)
    
static func apply_context_menu_layout(panel: Control) -> void:
    # Hier kannst du später Auflösungen, Tablet vs Desktop etc. abfragen
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

static func get_joystick_position(origin: Vector2, radius: float) -> Vector2:
    return origin - Vector2(radius, radius)