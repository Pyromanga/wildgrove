extends RefCounted
class_name ActionBarController

func setup(hud: HUD) -> void:
    # Hier kommt die Logik rein, die aktuell noch in create_hud() steht:
    # 1. Berechne Positionen (vielleicht bald via LayoutManager)
    # 2. Erstelle die 3 Buttons mit UIUtils (ehemals Factory)
    # 3. Verbinde Callbacks
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