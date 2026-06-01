class_name InteractionVisuals

var bar: ProgressBar

func _init(parent: CanvasLayer) -> void:
    bar = ProgressBar.new()
    bar.custom_minimum_size = Vector2(250, 24)
    bar.show_percentage = false
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    bar.offset_top = 100
    bar.visible = false
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Style-Logik hierher verlagert
    var sb_bg := StyleBoxFlat.new()
    sb_bg.bg_color = Color(0, 0, 0, 0.6)
    sb_bg.set_corner_radius_all(4)
    
    var sb_fg := StyleBoxFlat.new()
    sb_fg.bg_color = Color(0.2, 0.8, 0.3)
    sb_fg.set_corner_radius_all(4)
    
    bar.add_theme_stylebox_override("background", sb_bg)
    bar.add_theme_stylebox_override("fill", sb_fg)
    
    parent.add_child(bar)

func set_visible(val: bool) -> void:
    bar.visible = val

func set_value(val: float) -> void:
    bar.value = val

func create_tween() -> Tween:
    return bar.create_tween()