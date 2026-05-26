extends CanvasLayer
## Settings.gd — UI-Panel für Einstellungen

var _panel: ColorRect
const ROTATION_LABELS: Array = ["Frei", "Nur Hochkant", "Nur Querformat", "Hochkant + 180°"]
const ROTATION_MODES: Array = [DisplayServer.SCREEN_SENSOR, DisplayServer.SCREEN_PORTRAIT, DisplayServer.SCREEN_LANDSCAPE, DisplayServer.SCREEN_SENSOR_PORTRAIT]

func _ready() -> void:
    add_to_group("settings")
    var vp: Vector2 = get_viewport().get_visible_rect().size
    _build_panel(vp)
    _panel.visible = false
    get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
    if _panel:
        var vp = get_viewport().get_visible_rect().size
        _panel.size = Vector2(680, vp.y * 0.85)
        _panel.position = Vector2(vp.x * 0.5 - 340, vp.y * 0.075)

func toggle() -> void: _panel.visible = not _panel.visible
func is_settings_open() -> bool: return _panel.visible if _panel else false

func _build_panel(vp: Vector2) -> void:
    _panel = ColorRect.new()
    _panel.color = Color(0.08, 0.08, 0.08, 0.95)
    _panel.size = Vector2(680, vp.y * 0.85)
    _panel.position = Vector2(vp.x * 0.5 - 340, vp.y * 0.075)
    add_child(_panel)

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(0, 72); scroll.size = Vector2(680, _panel.size.y - 72)
    _panel.add_child(scroll)
    var content := VBoxContainer.new()
    scroll.add_child(content)

    # Aufbau des Menüs
    _add_setting_toggle(content, "Joystick-Modus", "fixed_joystick")
    _add_setting_toggle(content, "Joystick Y-Achse umkehren", "joystick_inverted")
    _add_setting_toggle(content, "Bewegung relativ zur Kamera", "cam_relative")
    
    _section(content, "Bildschirm-Rotation", "")
    content.add_child(_make_rotation_picker())
    
    content.add_child(_make_slider(content, "Kamera-Speed", "cam_smooth", 2.0, 30.0))
    content.add_child(_make_slider(content, "Zoom-Speed", "zoom_smooth", 1.0, 20.0))
    
    _spacer(content, 30)
    var close := Button.new()
    close.text = "✕ Schließen"; close.custom_minimum_size = Vector2(200, 60)
    close.pressed.connect(toggle)
    content.add_child(close)

# ── Komponenten-Logik ──────────────────────────────────────────────────────

func _add_setting_toggle(parent: VBoxContainer, title: String, key: String) -> void:
    _section(parent, title, "")
    var btn := Button.new()
    btn.text = "● EIN" if Kernel.data.get_setting(key) else "○ AUS"
    btn.pressed.connect(func():
        var new_val = not Kernel.data.get_setting(key)
        Kernel.data.set_setting(key, new_val)
        btn.text = "● EIN" if new_val else "○ AUS"
    )
    parent.add_child(btn)

func _make_slider(parent: VBoxContainer, label: String, key: String, mn: float, mx: float) -> Control:
    _section(parent, label, "")
    var hbox := HBoxContainer.new()
    var slider := HSlider.new()
    slider.min_value = mn; slider.max_value = mx
    slider.value = Kernel.data.get_setting(key)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    var val_lbl := Label.new()
    val_lbl.text = str(int(slider.value))
    slider.value_changed.connect(func(v): 
        Kernel.data.set_setting(key, v)
        val_lbl.text = str(int(v))
    )
    hbox.add_child(slider)
    hbox.add_child(val_lbl)
    return hbox

func _make_rotation_picker() -> Control:
    var vbox := VBoxContainer.new()
    for i in ROTATION_LABELS.size():
        var btn := Button.new()
        btn.text = ROTATION_LABELS[i]
        btn.pressed.connect(func():
            Kernel.data.set_setting("screen_rotation", i)
            DisplayServer.screen_set_orientation(ROTATION_MODES[i])
        )
        vbox.add_child(btn)
    return vbox

# ── Hilfsfunktionen ──────────────────────────────────────────────────────
func _section(parent: Control, title: String, sub: String) -> void:
    var lbl := Label.new(); lbl.text = title; parent.add_child(lbl)
    _spacer(parent, 5)

func _spacer(parent: Control, h: int = 16) -> void:
    var s := Control.new(); s.custom_minimum_size = Vector2(0, h); parent.add_child(s)