extends ServiceBase
class_name DebugConsole

const MAX_LINES := 12
const FONT_SIZE := 22

var _canvas: CanvasLayer
var _container: VBoxContainer
var _lines: Array[Label] = []
var _log_buffer: Array[String] = []  # kompletter Log für Copy
var _visible := true

func _ready() -> void:
    super._ready()
    _build_ui()
    Logger.on_log.connect(_on_log)

func _build_ui() -> void:
    _canvas = CanvasLayer.new()
    _canvas.layer = 100
    add_child(_canvas)

    var bg := ColorRect.new()
    bg.color = Color(0, 0, 0, 0.55)
    bg.custom_minimum_size = Vector2(700, 0)
    bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    _canvas.add_child(bg)

    _container = VBoxContainer.new()
    _container.position = Vector2(10, 48)  # Platz für Buttons oben
    _container.add_theme_constant_override("separation", 2)
    bg.add_child(_container)

    # Button-Leiste oben
    var btn_row := HBoxContainer.new()
    btn_row.position = Vector2(10, 5)
    _canvas.add_child(btn_row)

    var toggle_btn := Button.new()
    toggle_btn.text = "▼ Log"
    toggle_btn.custom_minimum_size = Vector2(100, 38)
    toggle_btn.pressed.connect(_toggle)
    btn_row.add_child(toggle_btn)

    var copy_btn := Button.new()
    copy_btn.text = "📋 Copy"
    copy_btn.custom_minimum_size = Vector2(100, 38)
    copy_btn.pressed.connect(_copy_log)
    btn_row.add_child(copy_btn)

    var clear_btn := Button.new()
    clear_btn.text = "✕ Clear"
    clear_btn.custom_minimum_size = Vector2(100, 38)
    clear_btn.pressed.connect(_clear_log)
    btn_row.add_child(clear_btn)

func _on_log(msg: String) -> void:
    _log_buffer.append(msg)  # immer alles speichern

    var lbl := Label.new()
    lbl.text = msg
    lbl.add_theme_font_size_override("font_size", FONT_SIZE)
    lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
    lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
    _container.add_child(lbl)
    _lines.append(lbl)

    if _lines.size() > MAX_LINES:
        _lines[0].queue_free()
        _lines.remove_at(0)

    await get_tree().process_frame
    var parent := _container.get_parent() as ColorRect
    if parent:
        parent.custom_minimum_size.y = _container.size.y + 56

func _copy_log() -> void:
    var text := "\n".join(_log_buffer)
    DisplayServer.clipboard_set(text)

func _toggle() -> void:
    _visible = not _visible
    _container.visible = _visible

func _clear_log() -> void:
    for lbl in _lines:
        lbl.queue_free()
    _lines.clear()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_QUOTELEFT:
            _toggle()