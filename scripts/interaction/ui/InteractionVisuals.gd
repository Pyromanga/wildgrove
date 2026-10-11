class_name InteractionVisuals

var bar: ProgressBar

func _init(parent: CanvasLayer) -> void:
	bar = ProgressBar.new()
	bar.name = "InteractionProgressBar"
	bar.custom_minimum_size = Vector2(300, 28)
	bar.size = Vector2(300, 28)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Anchors: horizontal zentriert, vertikal oberes Drittel
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	# Offset: -150 links/rechts zentriert den 300px-Bar, 120px vom oberen Rand
	bar.offset_left = -150
	bar.offset_right = 150
	bar.offset_top = 120
	bar.offset_bottom = 148  # 120 + 28px Höhe

	bar.visible = false

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
