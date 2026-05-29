extends ServiceBase
class_name DebugConsole

const MAX_LINES := 12
const FONT_SIZE := 22

var _canvas: CanvasLayer
var _container: VBoxContainer
var _lines: Array[Label] = []
var _visible := true

func _ready() -> void:
    super._ready()
    _build_ui()
    # Logger umleiten
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
    _container.position = Vector2(10, 8)
    _container.add_theme_constant_override("separation", 2)
    bg.add_child(_container)

    # Toggle-Button (oben rechts)
    var btn := Button.new()
    btn.text = "▼ Log"
    btn.custom_minimum_size = Vector2(80, 40)
    btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    btn.position = Vector2(-90, 5)
    btn.pressed.connect(_toggle)
    _canvas.add_child(btn)

func _on_log(msg: String) -> void:
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

    # Hintergrund-Höhe anpassen
    await get_tree().process_frame
    var parent := _container.get_parent() as ColorRect
    if parent:
        parent.custom_minimum_size.y = _container.size.y + 16

func _toggle() -> void:
    _visible = not _visible
    _container.visible = _visible

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_QUOTELEFT:  # ` Taste
            _toggle()