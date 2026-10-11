# scripts/ui/visuals/notificationVisuals.gd
class_name NotificationVisuals

var _parent: CanvasLayer

func _init(parent: CanvasLayer) -> void:
	_parent = parent

func show_popup(text: String) -> void:
	# Bestehende Popups aufräumen
	for n in _parent.get_tree().get_nodes_in_group("popup_message"):
		n.queue_free()

	var container := Control.new()
	container.add_to_group("popup_message")
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 100)

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

	panel.add_child(lbl)
	container.add_child(panel)
	_parent.add_child(container)

	# Auto-Close Timer (Logik, die in die Visuals darf, da sie zum 'Aufräumen' der Nodes gehört)
	# BUGFIX (2026-09-13): get_tree().create_timer() lebt UNABHÄNGIG vom
	# Popup-Container weiter. Wird der Container vorher schon durch ein
	# neueres Popup ersetzt (show_popup() räumt alte Popups sofort weg),
	# feuert dieser verwaiste Timer später gegen ein bereits freigegebenes
	# Objekt -> 'Lambda capture at index 0 was freed.' Ein Timer-Kindknoten
	# am Container stirbt automatisch MIT ihm — kein verwaister Timer mehr.
	var auto_close := Timer.new()
	auto_close.wait_time = 3.0
	auto_close.one_shot  = true
	container.add_child(auto_close)
	auto_close.timeout.connect(container.queue_free)
	auto_close.start()
