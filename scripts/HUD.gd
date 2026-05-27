extends CanvasLayer
## HUD.gd

var _debug_label: Label
var _inventory_label: Label
var _lines: Array[String] = []

func _ready() -> void:
    add_to_group("hud")
    _build_ui()
    _connect_bus()
    Kernel.inventory.inventory_changed.connect(_refresh_inventory_ui)
    _refresh_inventory_ui()
  
func _build_ui() -> void:
    _debug_label = Label.new()
    _debug_label.add_theme_font_size_override("font_size", 20)
    _debug_label.add_theme_color_override("font_color", Color.GREEN)
    add_child(_debug_label)
    _inventory_label = Label.new()
    _inventory_label.position = Vector2(20, 250)
    add_child(_inventory_label)
    
func _refresh_inventory_ui() -> void:
    var items = Kernel.inventory.get_all_items()
    var text = "Inventar:\n"
    for item in items:
        var info = Kernel.inventory.get_item_info(item.item_id)
        text += "- " + info.name + ": " + str(item.quantity) + "\n"
    _inventory_label.text = text

func _connect_bus() -> void:
    var ge = get_node_or_null("/root/GameEvents")
    if ge:
        ge.debug_log.connect(log_msg)

func log_msg(msg: String) -> void:
    _lines.append(msg)
    if _lines.size() > 8:
        _lines.remove_at(0)
    if _debug_label:
        _debug_label.text = "\n".join(_lines)