class_name JoystickController

var _visuals: JoystickVisuals

func setup(visuals: JoystickVisuals) -> void:
    _visuals = visuals
    # Wir lauschen jetzt auf den Bus
    Kernel.events.ui.joystick_toggled.connect(_on_toggled)
    Kernel.events.ui.joystick_moved.connect(_on_moved)

func _on_toggled(active: bool, origin: Vector2) -> void:
    _visuals.set_visible(active)
    if active:
        # Hier fragst du später den LayoutManager!
        _visuals.base.global_position = origin - (_visuals.base.size / 2)

func _on_moved(origin: Vector2, offset: Vector2) -> void:
    # Nur Logik-Update, Visuals werden verschoben
    _visuals.knob.global_position = origin + offset - (_visuals.knob.size * 0.5)