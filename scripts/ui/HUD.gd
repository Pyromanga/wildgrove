extends CanvasLayer
class_name HUD

# Refs werden von UIFactory gesetzt
var _inventory_label: Label
var _inventory_panel: PanelContainer
var _interact_button: Button = null
var _context_button: Button = null
var _player: Node = null

func _ready() -> void:
    add_to_group("hud")
    Logger.log_debug("HUD bereit", "HUD")
    call_deferred("_find_player")
    call_deferred("_connect_signals")

# Wird von UIFactory nach dem Bauen aufgerufen
func setup_inventory_refs(panel: PanelContainer, label: Label) -> void:
    _inventory_panel = panel
    _inventory_label = label

func setup_buttons(interact_btn: Button, context_btn: Button) -> void:
    _interact_button = interact_btn
    _context_button = context_btn

func _find_player() -> void:
    var players = get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        _player = players[0]

func _connect_signals() -> void:
    if Kernel.has_service("events"):
        Kernel.events.player.xp_gained.connect(_on_xp_gained)
    var skill_service = Kernel.get_service("skill_system")
    if skill_service and skill_service.has_signal("level_up"):
        skill_service.level_up.connect(_on_level_up)

func _process(_delta: float) -> void:
    if not _interact_button or not _context_button:
        return
    if not _player:
        _find_player()
        if not _player:
            return
    var target: Node = null
    if _player.has_method("_get_closest_interactable"):
        target = _player._get_closest_interactable()
    var has_target = target != null
    _interact_button.self_modulate = Color.WHITE if has_target else Color(0.4, 0.4, 0.4)
    _context_button.self_modulate = Color.WHITE if has_target else Color(0.4, 0.4, 0.4)

func toggle_inventory() -> void:
    if _inventory_panel:
        _inventory_panel.visible = not _inventory_panel.visible

# Wird von InventoryUIController aufgerufen
func update_inventory_display(items: Array) -> void:
    if not is_instance_valid(_inventory_label):
        return
    if items.is_empty():
        _inventory_label.text = "(Leer)"
        return
    var lines: Array[String] = []
    for item in items:
        lines.append("%s ×%d" % [item["name"], item["quantity"]])
    _inventory_label.text = "\n".join(lines)

func _on_xp_gained(skill: String, amount: int) -> void:
    show_floating_text("+%d %s" % [amount, skill], Color(1, 0.9, 0.2))

func _on_level_up(skill: String, new_level: int) -> void:
    show_floating_text("%s Stufe %d!" % [skill, new_level], Color(0.2, 1, 0.2), 36, 3.0)

func show_floating_text(text: String, color: Color, font_size: int = 24, duration: float = 2.0) -> void:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.self_modulate = color
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    label.position = Vector2(0, -100)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # floating labels blocken nie
    add_child(label)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(label, "position", label.position + Vector2(0, -80), duration)
    tween.tween_property(label, "self_modulate:a", 0.0, duration).from(1.0)
    tween.tween_callback(label.queue_free).set_delay(duration)