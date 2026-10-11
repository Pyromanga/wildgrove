class_name QuestPanelVisuals

var panel: PanelContainer
var toggle_button: Button
var _rows: VBoxContainer
var _quest_rows: Dictionary = {}  # { quest_id: Container }

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "QuestToggleButton"
	toggle_button.text = "📜"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "QuestPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())

	UIMetrics.place_sheet(panel, UIMetrics.SHEET_WIDTH)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIMetrics.build_header("📜 Quests", panel))

	# Feste Maximalhöhe + Scroll statt unbegrenzt mitwachsend (wie BuildPanelVisuals) — aktive
	# und abgeschlossene Quests stecken hier zusammen in derselben Liste.
	_rows = VBoxContainer.new()
	_rows.name = "QuestRows"
	_rows.add_theme_constant_override("separation", 10)
	vbox.add_child(UIMetrics.make_scrollable(_rows))

	parent.add_child(panel)
	PanelDock.register_in(parent, &"quests", panel, PanelDock.Kind.SHEET, toggle_button)

func show_quest(quest_id: String, title: String, objectives: Array[Dictionary]) -> void:
	if _quest_rows.has(quest_id):
		_update_quest_row(quest_id, objectives)
		return

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	title_lbl.modulate = Color(1.0, 0.9, 0.4)
	container.add_child(title_lbl)

	var obj_container := VBoxContainer.new()
	obj_container.name = "Objectives"
	container.add_child(obj_container)

	_rows.add_child(container)
	_quest_rows[quest_id] = {"container": container, "obj_container": obj_container}
	_update_quest_row(quest_id, objectives)

func _update_quest_row(quest_id: String, objectives: Array[Dictionary]) -> void:
	var row: Dictionary = _quest_rows[quest_id]
	var obj_container := row["obj_container"] as VBoxContainer
	for child in obj_container.get_children():
		obj_container.remove_child(child)
		child.free()
	for obj_data in objectives:
		var lbl := Label.new()
		var done: bool = obj_data["current"] >= obj_data["required"]
		var prefix := "✓ " if done else "○ "
		lbl.text = "%s%s  %d/%d" % [prefix, obj_data["label"], obj_data["current"], obj_data["required"]]
		lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
		lbl.modulate = Color(0.6, 1.0, 0.6) if done else Color(1, 1, 1, 0.8)
		obj_container.add_child(lbl)

func remove_quest(quest_id: String) -> void:
	if not _quest_rows.has(quest_id):
		return
	var row: Dictionary = _quest_rows[quest_id]
	var container := row["container"] as Control
	container.get_parent().remove_child(container)
	container.free()
	_quest_rows.erase(quest_id)

func toggle() -> void:
	panel.visible = !panel.visible

## Fügt eine abgeschlossene Quest zur Completed-Sektion hinzu.
func add_completed(quest_id: String, title: String) -> void:
	# Trennlinie + "Abgeschlossen"-Header nur beim ersten completed Quest
	if not _rows.has_node("CompletedSection"):
		var sep := HSeparator.new()
		sep.name = "CompletedSection"
		_rows.add_child(sep)

		var header := Label.new()
		header.text = "✓ Abgeschlossen"
		header.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
		header.modulate = Color(0.6, 0.9, 0.6, 0.8)
		_rows.add_child(header)

	var lbl := Label.new()
	lbl.name = "Completed_" + quest_id
	lbl.text = "✓ " + title
	lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	lbl.modulate = Color(0.5, 0.8, 0.5)
	_rows.add_child(lbl)
