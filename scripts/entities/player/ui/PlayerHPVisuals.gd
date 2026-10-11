class_name PlayerHPVisuals

var container: Control
var bar: ProgressBar
var label: Label

func _init(parent: CanvasLayer) -> void:
	container = Control.new()
	container.name = "PlayerHP"
	container.anchor_left   = 0.5
	container.anchor_right  = 0.5
	container.anchor_top    = 1.0
	container.anchor_bottom = 1.0
	container.offset_left   = -100
	container.offset_right  = 100
	container.offset_top    = -160
	container.offset_bottom = -130

	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 24)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	# Rote Farbe
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.12, 0.12)
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_style)
	container.add_child(bar)

	label = Label.new()
	label.text = "❤ 100 / 100"
	label.position = Vector2(0, 26)
	label.add_theme_font_size_override("font_size", 14)
	container.add_child(label)

	parent.add_child(container)

func update(current: int, maximum: int) -> void:
	bar.max_value = maximum
	bar.value = current
	label.text = "❤ %d / %d" % [current, maximum]
	# Farbe wechselt je nach HP-Stand
	var ratio := float(current) / float(maximum)
	var fill_style := StyleBoxFlat.new()
	fill_style.set_corner_radius_all(4)
	if ratio > 0.6:
		fill_style.bg_color = Color(0.15, 0.75, 0.15)
	elif ratio > 0.3:
		fill_style.bg_color = Color(0.85, 0.70, 0.05)
	else:
		fill_style.bg_color = Color(0.85, 0.12, 0.12)
	bar.add_theme_stylebox_override("fill", fill_style)
