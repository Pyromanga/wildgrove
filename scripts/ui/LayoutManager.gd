# scripts/ui/layout_manager.gd
class_name LayoutManager

# Definition der Zonen als Konstanten oder Helper
const ACTION_BAR_ZONE := Rect2(0.7, 0.85, 0.25, 0.1) # Rechts unten
const INVENTORY_ZONE  := Rect2(0.3, 0.3, 0.4, 0.4)    # Zentriert

static func get_zone_rect(zone: Rect2) -> Rect2:
    var vp = DisplayServer.window_get_size()
    return Rect2(
        vp.x * zone.position.x, 
        vp.y * zone.position.y, 
        vp.x * zone.size.x, 
        vp.y * zone.size.y
    )

static func get_action_button_position(index: int) -> Vector2:
    var zone = get_zone_rect(ACTION_BAR_ZONE)
    var padding = 20.0
    var btn_size = 150.0
    # Berechnet Position innerhalb der Zone
    var x = zone.position.x + (index * (btn_size + padding))
    var y = zone.position.y
    return Vector2(x, y)