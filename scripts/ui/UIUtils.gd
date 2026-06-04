class_name UIUtils

const COLOR_BG = Color(0, 0, 0, 0.6)
const COLOR_ACCENT = Color(0.2, 0.8, 0.3)


static func create_label_box(text: String) -> PanelContainer:
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


static func create_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 40)
	btn.pressed.connect(callback)
	return btn
