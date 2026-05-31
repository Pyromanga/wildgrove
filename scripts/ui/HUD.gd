extends CanvasLayer
class_name HUD

var _inventory_label: Label
var _inventory_panel: PanelContainer   # NEU
var _interact_button: Button = null
var _context_button: Button = null
var _player: Node = null

func _ready() -> void:
    add_to_group("hud")
    _build_ui()
    Logger.log_debug("HUD bereit", "HUD")
    call_deferred("_find_player")
    call_deferred("_connect_signals")   # Verbindungen herstellen, sobald Services da sind

func _build_ui() -> void:
    # --- Oberer Container (XP-Bar) ---
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_top", 50)
    add_child(margin)

    var v_box := VBoxContainer.new()
    v_box.alignment = BoxContainer.ALIGNMENT_BEGIN
    margin.add_child(v_box)
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

    # XP-Bar wird von UIFactory eingefügt – Platzhalter
    var xp_bar_placeholder = Control.new()
    xp_bar_placeholder.name = "XPBarPlaceholder"
    v_box.add_child(xp_bar_placeholder)

    # --- Inventar-Panel (versteckt) ---
    _inventory_panel = PanelContainer.new()
    _inventory_panel.visible = false
    _inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0, 0, 0, 0.8)
    panel_style.set_content_margin_all(16)
    panel_style.set_corner_radius_all(8)
    _inventory_panel.add_theme_stylebox_override("panel", panel_style)
    _inventory_panel.offset_left = -200
    _inventory_panel.offset_right = 200
    _inventory_panel.offset_top = -100
    _inventory_panel.offset_bottom = 100
    _inventory_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _inventory_label = Label.new()
    _inventory_label.name = "InventoryLabel"
    _inventory_label.add_theme_font_size_override("font_size", 20)
    _inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _inventory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _inventory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _inventory_panel.add_child(_inventory_label)
    add_child(_inventory_panel)

func setup_buttons(interact_btn: Button, context_btn: Button) -> void:
    _interact_button = interact_btn
    _context_button = context_btn

func _find_player() -> void:
    var players = get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        _player = players[0]

func _connect_signals() -> void:
    # XP-Gewinn-Event (immer verfügbar)
    if Kernel.has_service("events"):
        Kernel.events.player.xp_gained.connect(_on_xp_gained)
    # SkillSystem-Level-Up-Event (kann kurz nach Registrierung kommen)
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

# --- Inventar toggeln ---
func toggle_inventory() -> void:
    _inventory_panel.visible = not _inventory_panel.visible

# --- XP-Text anzeigen ---
func _on_xp_gained(skill: String, amount: int) -> void:
    show_floating_text("+%d %s" % [amount, skill], Color(1, 0.9, 0.2))

# --- Level-Up-Text anzeigen ---
func _on_level_up(skill: String, new_level: int) -> void:
    show_floating_text("%s Stufe %d!" % [skill, new_level], Color(0.2, 1, 0.2), 36, 3.0)

# --- Universelle Floating-Text-Methode ---
func show_floating_text(text: String, color: Color, font_size: int = 24, duration: float = 2.0) -> void:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.self_modulate = color
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    label.position = Vector2(0, -100)   # etwas oberhalb der Mitte starten
    add_child(label)

    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(label, "position", label.position + Vector2(0, -80), duration)
    tween.tween_property(label, "self_modulate:a", 0.0, duration).from(1.0)
    tween.tween_callback(label.queue_free).set_delay(duration)