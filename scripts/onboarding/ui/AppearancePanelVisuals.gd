class_name AppearancePanelVisuals

## AppearancePanelVisuals — reine Darstellung, keine Logik. Programmatisch
## gebaut, gleiches Muster wie SkillPanelVisuals/AchievementPanelVisuals.
##
## Baut EIN Zeilenpaar (◀ Label ▶) pro Feld aus CharacterLook.FIELDS, gruppiert
## unter Überschriften (field.group). Zeigt IMMER das aktuell gewählte Label,
## nicht die ID — der Controller ruft update_field() bei jeder Änderung.
##
## Kennt CharacterLook NICHT direkt (keine harte Kopplung an den Katalog) —
## build_fields() bekommt die Feldliste vom Controller übergeben.

signal field_stepped(field: String, delta: int)
## Feuert, sobald das Panel sichtbar wird (Toggle-Button ODER show_panel()) —
## der Controller nutzt das, um die Anzeige beim Öffnen aufzufrischen (der Look
## kann sich geändert haben, während das Panel zu war).
signal opened()

var panel: PanelContainer
var toggle_button: Button
var _value_labels: Dictionary = {}  # field -> Label

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "AppearanceToggleButton"
	toggle_button.text = "🧑"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "AppearancePanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 420)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "Aussehen"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "✕"
	close_button.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var fields_vbox := VBoxContainer.new()
	fields_vbox.add_theme_constant_override("separation", 10)
	fields_vbox.name = "FieldsVBox"
	scroll.add_child(fields_vbox)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"appearance", panel, PanelDock.Kind.MODAL, toggle_button)

## fields: Array wie CharacterLook.FIELDS ({key, label, group}). Baut die
## Zeilen einmalig auf — bei erneutem Aufruf (Test-Wiederverwendung) werden
## vorherige Zeilen entfernt.
func build_fields(fields: Array) -> void:
	var fields_vbox := panel.find_child("FieldsVBox", true, false) as VBoxContainer
	if not is_instance_valid(fields_vbox):
		return
	for child in fields_vbox.get_children():
		child.queue_free()
	_value_labels.clear()

	var last_group := ""
	for field in fields:
		var f: Dictionary = field
		var key: String = String(f["key"])
		var group: String = String(f.get("group", ""))
		if group != last_group:
			var group_lbl := Label.new()
			group_lbl.text = group
			group_lbl.add_theme_font_size_override("font_size", 13)
			group_lbl.modulate = Color(1, 1, 1, 0.55)
			fields_vbox.add_child(group_lbl)
			last_group = group

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_lbl := Label.new()
		name_lbl.text = String(f.get("label", key))
		name_lbl.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_lbl)

		var prev := Button.new()
		prev.text = "◀"
		prev.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
		prev.pressed.connect(func() -> void: field_stepped.emit(key, -1))
		row.add_child(prev)

		var value_lbl := Label.new()
		value_lbl.text = ""
		value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_lbl)
		_value_labels[key] = value_lbl

		var next := Button.new()
		next.text = "▶"
		next.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
		next.pressed.connect(func() -> void: field_stepped.emit(key, 1))
		row.add_child(next)

		fields_vbox.add_child(row)

	UIMetrics.allow_scroll_through(fields_vbox)

## Zeigt das aktuell gewählte Label für ein Feld an (z. B. "Kastanie" statt
## "chestnut"). Unbekanntes Feld -> No-Op.
func update_field(field: String, value_label: String) -> void:
	var lbl := _value_labels.get(field, null) as Label
	if is_instance_valid(lbl):
		lbl.text = value_label

func show_panel() -> void:
	panel.visible = true
	opened.emit()

func hide_panel() -> void:
	panel.visible = false

func _on_close_pressed() -> void:
	hide_panel()

func toggle() -> void:
	panel.visible = !panel.visible
	if panel.visible:
		opened.emit()
