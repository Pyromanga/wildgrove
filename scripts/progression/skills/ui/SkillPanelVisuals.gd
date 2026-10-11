class_name SkillPanelVisuals

var panel: PanelContainer
var toggle_button: Button
var _rows: VBoxContainer
var _skill_labels: Dictionary = {}  # { skill_id: { label, bar, xp_label } }

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "SkillToggleButton"
	toggle_button.text = "⚔"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "SkillPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())

	UIMetrics.place_sheet(panel, UIMetrics.SHEET_WIDTH)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIMetrics.build_header("⚔ Skills", panel))

	# Feste Maximalhöhe + Scroll statt unbegrenzt mitwachsend (wie BuildPanelVisuals) — mit
	# jedem neuen Skill sonst wieder dasselbe Problem wie beim Baumenü.
	_rows = VBoxContainer.new()
	_rows.name = "SkillRows"
	_rows.add_theme_constant_override("separation", 10)
	vbox.add_child(UIMetrics.make_scrollable(_rows))

	parent.add_child(panel)
	PanelDock.register_in(parent, &"skills", panel, PanelDock.Kind.SHEET, toggle_button)

func update_skill(skill_id: String, level: int, xp: int, xp_needed: int) -> void:
	if not _skill_labels.has(skill_id):
		_add_skill_row(skill_id)

	var row: Dictionary = _skill_labels[skill_id]
	(row["label"] as Label).text = "%s  Lv.%d" % [skill_id.capitalize(), level]
	var bar := row["bar"] as ProgressBar
	bar.max_value = xp_needed
	bar.value = xp
	(row["xp_label"] as Label).text = "%d / %d XP" % [xp, xp_needed]

func _add_skill_row(skill_id: String) -> void:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = skill_id.capitalize()
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	container.add_child(name_lbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240, 18)
	bar.show_percentage = false
	container.add_child(bar)

	var xp_lbl := Label.new()
	xp_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	xp_lbl.modulate = Color(1, 1, 1, 0.6)
	container.add_child(xp_lbl)

	_rows.add_child(container)
	_skill_labels[skill_id] = {"label": name_lbl, "bar": bar, "xp_label": xp_lbl}

func toggle() -> void:
	panel.visible = !panel.visible
