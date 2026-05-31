extends ServiceBase
class_name UIFactory

const COLOR_BG = Color(0, 0, 0, 0.6)
const COLOR_ACCENT = Color(0.2, 0.8, 0.3)

func create_hud() -> HUD:
    Logger.log_debug("create_hud() START", "UIFactory")

    var HUDClass = load("res://scripts/ui/HUD.gd")
    if not HUDClass:
        Logger.log_error("HUD.gd konnte nicht geladen werden!", "UIFactory")
        return null

    var canvas: HUD = HUDClass.new()
    canvas.name = "HUD"
    canvas.add_to_group("hud")

    # --- XP-Bar oben ---
    # Dieser Container IGNORIERT Mouse-Events, er ist nur visuell
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_top", 50)
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(margin)

    var v_box := VBoxContainer.new()
    v_box.alignment = BoxContainer.ALIGNMENT_BEGIN
    v_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(v_box)

    var xp_bar = create_progress_bar()
    xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v_box.add_child(xp_bar)

    # --- Inventar-Panel (versteckt, zentriert) ---
    var inv_panel := PanelContainer.new()
    inv_panel.visible = false
    inv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0, 0, 0, 0.8)
    panel_style.set_content_margin_all(16)
    panel_style.set_corner_radius_all(8)
    inv_panel.add_theme_stylebox_override("panel", panel_style)
    inv_panel.offset_left = -200
    inv_panel.offset_right = 200
    inv_panel.offset_top = -150
    inv_panel.offset_bottom = 150
    # Das Panel selbst fängt Klicks (damit Klicks dahinter nicht durchgehen)
    # Aber nur wenn es sichtbar ist – das regelt toggle_inventory()
    inv_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var inv_label := Label.new()
    inv_label.name = "InventoryLabel"
    inv_label.add_theme_font_size_override("font_size", 20)
    inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    inv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    inv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    inv_panel.add_child(inv_label)
    canvas.add_child(inv_panel)

    # Refs an HUD weitergeben
    canvas.setup_inventory_refs(inv_panel, inv_label)

    # --- Buttons ---
    var screen_size = DisplayServer.window_get_size()
    var btn_size = clamp(screen_size.x * 0.15, 120.0, 200.0)
    var gap = 20.0
    var margin_right = 30.0
    var margin_bottom = 40.0

    var interact_data = _create_action_button(
        "!",
        Color(0.2, 0.8, 0.3, 0.85),
        -btn_size - margin_right,
        -btn_size - margin_bottom,
        -margin_right,
        -margin_bottom,
        btn_size,
        func():
          Logger.log_debug("Interact-Button geklickt", "UIFactory")
          var p = get_tree().get_first_node_in_group("player")
          if p and p.has_method("try_default_interact"):
            p.try_default_interact()
          else:
            Logger.log_error("Player nicht gefunden oder Methode fehlt!", "UIFactory")
    )
    canvas.add_child(interact_data["container"])

    var context_data = _create_action_button(
        "☰",
        Color(0.2, 0.5, 0.9, 0.85),
        -2 * btn_size - gap - margin_right,
        -btn_size - margin_bottom,
        -btn_size - gap - margin_right,
        -margin_bottom,
        btn_size,
        func():
            var players = canvas.get_tree().get_nodes_in_group("player")
            if players.size() > 0:
                players[0].try_open_context_menu()
    )
    canvas.add_child(context_data["container"])

    var inventory_data = _create_action_button(
        "🎒",
        Color(0.7, 0.5, 0.2, 0.85),
        -3 * btn_size - gap * 2 - margin_right,
        -btn_size - margin_bottom,
        -2 * btn_size - gap * 2 - margin_right,
        -margin_bottom,
        btn_size,
        func():
            canvas.toggle_inventory()
    )
    canvas.add_child(inventory_data["container"])

    canvas.setup_buttons(interact_data["button"], context_data["button"])
    Logger.log_debug("create_hud() ENDE", "UIFactory")
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
    # Container ist IGNORE – er hat keine eigene Fläche die Klicks frisst
    var container := Control.new()
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
    # STOP: der Button selbst fängt seinen eigenen Bereich
    btn.mouse_filter = Control.MOUSE_FILTER_STOP

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

# --- Rest unverändert ---
func show_context_menu(actions: Array) -> void:
    var existing = get_tree().get_nodes_in_group("context_menu")
    for n in existing:
        n.queue_free()
    var hud_nodes = get_tree().get_nodes_in_group("hud")
    if hud_nodes.is_empty():
        Logger.log_error("Kein HUD für Kontextmenü!", "UIFactory")
        return
    if actions.is_empty():
        return
    var hud_root = hud_nodes[0]
    var container := Control.new()
    container.add_to_group("context_menu")
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var panel := PanelContainer.new()
    panel.anchor_left   = 0.5
    panel.anchor_right  = 0.5
    panel.anchor_top    = 0.5
    panel.anchor_bottom = 0.5
    var menu_width  = 320.0
    var entry_height = 56.0
    var total_height = entry_height * actions.size() + 20
    panel.offset_left   = -menu_width / 2
    panel.offset_right  =  menu_width / 2
    panel.offset_top    = -total_height / 2
    panel.offset_bottom =  total_height / 2
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.9)
    sb.set_corner_radius_all(12)
    sb.set_content_margin_all(10)
    panel.add_theme_stylebox_override("panel", sb)
    var vbox := VBoxContainer.new()
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(vbox)
    for action in actions:
        var btn := Button.new()
        btn.text = action.label
        btn.custom_minimum_size = Vector2(menu_width - 20, entry_height - 6)
        btn.add_theme_font_size_override("font_size", 20)
        var action_ref = action
        btn.pressed.connect(func():
            container.queue_free()
            Kernel.builder.execute_action(action_ref)
        )
        vbox.add_child(btn)
    container.add_child(panel)
    hud_root.add_child(container)
    get_tree().create_timer(5.0).timeout.connect(func():
        if is_instance_valid(container):
            container.queue_free()
    )

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
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var panel := PanelContainer.new()
    panel.anchor_left   = 0.5
    panel.anchor_right  = 0.5
    panel.anchor_top    = 0.5
    panel.anchor_bottom = 0.5
    panel.offset_left   = -200.0
    panel.offset_right  =  200.0
    panel.offset_top    = -50.0
    panel.offset_bottom =  50.0
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.85)
    sb.set_content_margin_all(16)
    sb.set_corner_radius_all(8)
    panel.add_theme_stylebox_override("panel", sb)
    var lbl := Label.new()
    lbl.text = text
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    lbl.add_theme_font_size_override("font_size", 20)
    lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
    base.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var knob := ColorRect.new()
    knob.custom_minimum_size = Vector2(60, 60)
    knob.color = Color(1, 1, 1, 0.8)
    knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return [base, knob]
    
# In UIFactory.gd
func setup_inventory_controller(hud: HUD) -> void:
    var controller = InventoryUIController.new()
    controller.setup(hud, Kernel.inventory)
    
# In UIFactory.gd — aufgerufen von Main nach _start_game()
# In UIFactory.gd

func setup_interaction_ui(hud: HUD) -> void:
    # Die Factory baut nur noch das Objekt und ruft setup auf.
    # Keine Signal-Logik mehr hier!
    var controller = InteractionUIController.new()
    controller.setup(hud)

# UIFactory.gd — wird in setup_hud() aufgerufen
# UIFactory.gd - Fix für den Crash beim Laden
func setup_joystick(hud: HUD) -> void:
    var players = hud.get_tree().get_nodes_in_group("player")
    if players.is_empty(): return
    
    # Die Factory delegiert die Logik an den Controller
    var controller = JoystickController.new()
    controller.setup(hud, players[0])