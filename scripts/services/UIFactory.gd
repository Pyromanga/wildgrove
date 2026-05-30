extends ServiceBase
class_name UIFactory

const COLOR_BG = Color(0, 0, 0, 0.6)
const COLOR_ACCENT = Color(0.2, 0.8, 0.3)

func create_hud() -> HUD:
    Logger.log_debug("[UIFactory] create_hud() START", "UIFactory")

    var HUDClass = load("res://scripts/ui/HUD.gd")
    if not HUDClass:
        Logger.log_error("[UIFactory] HUD.gd konnte nicht geladen werden!", "UIFactory")
        return null

    var canvas: HUD = HUDClass.new()
    if not canvas:
        Logger.log_error("[UIFactory] HUD.new() schlug fehl!", "UIFactory")
        return null

    canvas.name = "HUD"
    canvas.add_to_group("hud")
    Logger.log_debug("[UIFactory] HUD erstellt", "UIFactory")

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_top", 50)
    canvas.add_child(margin)

    var v_box := VBoxContainer.new()
    v_box.alignment = BoxContainer.ALIGNMENT_BEGIN
    margin.add_child(v_box)

    var xp_bar = create_progress_bar()
    v_box.add_child(xp_bar)
    Logger.log_debug("[UIFactory] XP-Bar hinzugefügt", "UIFactory")

    # Echte Fenstergröße für Skalierung
    var screen_size = DisplayServer.window_get_size()
    var btn_size = clamp(screen_size.x * 0.15, 120.0, 200.0)  # 15% der Breite
    var gap = 20.0                        # Abstand zwischen den Buttons
    var margin_right = 30.0               # Abstand vom rechten Rand
    var margin_bottom = 40.0              # Abstand vom unteren Rand

    Logger.log_debug("[UIFactory] Screen-Size: %s, btn_size: %.1f" % [screen_size, btn_size], "UIFactory")

    # Interact-Button (!) – direkt über dem unteren Rand, rechts
    var interact_data = _create_action_button(
        "!",
        Color(0.2, 0.8, 0.3, 0.85),
        -btn_size - margin_right,                  # offset_left
        -btn_size - margin_bottom,                 # offset_top
        -margin_right,                             # offset_right
        -margin_bottom,                            # offset_bottom
        btn_size,
        func():
            Logger.log_debug("[UIFactory] Interact-Button gedrückt!", "UIFactory")
            var players = canvas.get_tree().get_nodes_in_group("player")
            if players.size() > 0:
                players[0].try_default_interact()
            else:
                Logger.log_error("[UIFactory] Kein Player gefunden!", "UIFactory")
    )
    var interact_btn: Button = interact_data["button"]
    canvas.add_child(interact_data["container"])
    Logger.log_debug("[UIFactory] Interact-Button erstellt", "UIFactory")

    # Kontext-Button (☰) – links daneben
    var context_data = _create_action_button(
        "☰",
        Color(0.2, 0.5, 0.9, 0.85),
        -2 * btn_size - gap - margin_right,        # offset_left
        -btn_size - margin_bottom,                 # offset_top
        -btn_size - gap - margin_right,            # offset_right
        -margin_bottom,                            # offset_bottom
        btn_size,
        func():
            Logger.log_debug("[UIFactory] Kontext-Button gedrückt!", "UIFactory")
            var players = canvas.get_tree().get_nodes_in_group("player")
            if players.size() > 0:
                players[0].try_open_context_menu()
            else:
                Logger.log_error("[UIFactory] Kein Player gefunden!", "UIFactory")
    )
    var context_btn: Button = context_data["button"]
    canvas.add_child(context_data["container"])
    Logger.log_debug("[UIFactory] Kontext-Button erstellt", "UIFactory")

    canvas.setup_buttons(interact_btn, context_btn)
    Logger.log_debug("[UIFactory] setup_buttons aufgerufen, create_hud() ENDE", "UIFactory")

    return canvas

func _create_action_button(
    text: String,
    color: Color,
    offset_left: float,
    offset_top: float,
    offset_right: float,
    offset_bottom: float,
    size: float,
    callback: Callable
) -> Dictionary:
    var container := Control.new()
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var btn := Button.new()
    btn.text = text
    btn.custom_minimum_size = Vector2(size, size)
    btn.anchor_left   = 1.0
    btn.anchor_top    = 1.0
    btn.anchor_right  = 1.0
    btn.anchor_bottom = 1.0
    btn.offset_left   = offset_left
    btn.offset_top    = offset_top
    btn.offset_right  = offset_right
    btn.offset_bottom = offset_bottom

    var sb := StyleBoxFlat.new()
    sb.bg_color = color
    sb.set_corner_radius_all(size / 2)
    btn.add_theme_stylebox_override("normal", sb)

    var sb_pressed := StyleBoxFlat.new()
    sb_pressed.bg_color = color.darkened(0.3)
    sb_pressed.set_corner_radius_all(size / 2)
    btn.add_theme_stylebox_override("pressed", sb_pressed)

    btn.add_theme_font_size_override("font_size", int(size * 0.4))
    btn.pressed.connect(callback)
    container.add_child(btn)

    return {"container": container, "button": btn}

func show_context_menu(actions: Array) -> void:
    Logger.log_debug("[UIFactory] show_context_menu aufgerufen mit %d Aktionen" % actions.size(), "UIFactory")
    var existing = get_tree().get_nodes_in_group("context_menu")
    for n in existing:
        n.queue_free()

    var hud_nodes = get_tree().get_nodes_in_group("hud")
    if hud_nodes.is_empty():
        Logger.log_error("[UIFactory] Kein HUD für Kontextmenü gefunden!", "UIFactory")
        return
    var hud_root = hud_nodes[0]

    if actions.is_empty():
        Logger.log_debug("[UIFactory] Keine Aktionen vorhanden, kein Menü", "UIFactory")
        return

    var container := Control.new()
    container.add_to_group("context_menu")
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel := PanelContainer.new()
    panel.anchor_left   = 1.0
    panel.anchor_top    = 1.0
    panel.anchor_right  = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left   = -220.0
    panel.offset_top    = -60.0 - (actions.size() * 55.0)
    panel.offset_right  = -30.0
    panel.offset_bottom = -120.0

    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.85)
    sb.set_corner_radius_all(8)
    panel.add_theme_stylebox_override("panel", sb)

    var vbox := VBoxContainer.new()
    panel.add_child(vbox)

    for action in actions:
        var btn := Button.new()
        btn.text = action.label
        btn.custom_minimum_size = Vector2(180, 48)
        var action_ref = action
        btn.pressed.connect(func():
            Logger.log_debug("[UIFactory] Kontext-Aktion gewählt: " + action_ref.label, "UIFactory")
            container.queue_free()
            Kernel.builder.execute_action(action_ref)
        )
        vbox.add_child(btn)

    container.add_child(panel)
    hud_root.add_child(container)

    get_tree().create_timer(4.0).timeout.connect(func():
        if is_instance_valid(container):
            container.queue_free()
    )
    Logger.log_debug("[UIFactory] Kontextmenü erstellt und angezeigt", "UIFactory")

# --- unveränderte Hilfsmethoden ---
func show_popup(text: String) -> void:
    var hud_nodes = get_tree().get_nodes_in_group("hud")
    if hud_nodes.is_empty():
        return
    var hud_root = hud_nodes[0]
    var existing = get_tree().get_nodes_in_group("popup_message")
    for n in existing:
        n.queue_free()
    var container := Control.new()
    container.add_to_group("popup_message")
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var panel := PanelContainer.new()
    panel.anchor_left   = 0.5
    panel.anchor_right  = 0.5
    panel.anchor_top    = 0.5
    panel.anchor_bottom = 0.5
    panel.offset_left   = -200.0
    panel.offset_right  = 200.0
    panel.offset_top    = -40.0
    panel.offset_bottom = 40.0
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.8)
    sb.set_content_margin_all(12)
    sb.set_corner_radius_all(8)
    panel.add_theme_stylebox_override("panel", sb)
    var lbl := Label.new()
    lbl.text = text
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    lbl.add_theme_font_size_override("font_size", 18)
    panel.add_child(lbl)
    container.add_child(panel)
    hud_root.add_child(container)
    get_tree().create_timer(3.0).timeout.connect(func():
        if is_instance_valid(container):
            container.queue_free()
    )

func create_progress_bar(width: float = 250.0) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.custom_minimum_size = Vector2(width, 24)
    bar.show_percentage = false
    var sb_bg := StyleBoxFlat.new()
    sb_bg.bg_color = COLOR_BG
    sb_bg.set_corner_radius_all(4)
    var sb_fg := StyleBoxFlat.new()
    sb_fg.bg_color = COLOR_ACCENT
    sb_fg.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", sb_bg)
    bar.add_theme_stylebox_override("fill", sb_fg)
    return bar

func create_label_box(text: String) -> PanelContainer:
    var pc := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = COLOR_BG
    sb.set_content_margin_all(10)
    sb.set_corner_radius_all(6)
    pc.add_theme_stylebox_override("panel", sb)
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 18)
    pc.add_child(lbl)
    return pc

func create_button(text: String, callback: Callable) -> Button:
    var btn := Button.new()
    btn.text = text
    btn.custom_minimum_size = Vector2(150, 40)
    btn.pressed.connect(callback)
    return btn

func create_joystick_visuals() -> Array:
    var base := ColorRect.new()
    base.custom_minimum_size = Vector2(180, 180)
    base.color = Color(1, 1, 1, 0.2)
    base.set_deferred("visible", false)
    var knob := ColorRect.new()
    knob.custom_minimum_size = Vector2(60, 60)
    knob.color = Color(1, 1, 1, 0.8)
    return [base, knob]