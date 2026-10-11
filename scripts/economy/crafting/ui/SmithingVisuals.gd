class_name SmithingVisuals

## SmithingVisuals — reines UI-Building für das Schmiede-Panel (kein Verhalten, siehe
## ShopVisuals/QuestPanelVisuals-Konvention). SmithingUIController hält die Logik.
##
## Eine Zeile pro Rezept der geöffneten Station: Name, Zutaten-Zeile (vorhanden/benötigt) und ein
## "Herstellen"-Button. Nicht ausführbare Rezepte bleiben sichtbar (ausgegraut, mit Grund in der
## Zutaten-Zeile) — der Spieler soll sehen, WAS ihm noch fehlt, nicht nur, was schon geht.

signal close_requested

var panel: PanelContainer
var title_label: Label
var skill_label: Label
var list: VBoxContainer

func _init(parent: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.name = "SmithingPanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.05, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 520)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	title_label = Label.new()
	title_label.text = "Schmiede"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
	close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(close_btn)
	vbox.add_child(header)

	skill_label = Label.new()
	skill_label.text = "🔨 Schmieden: Stufe 1"
	skill_label.modulate = Color(1.0, 0.7, 0.35)
	vbox.add_child(skill_label)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	vbox.add_child(scroll)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"smithing", panel, PanelDock.Kind.MODAL)

func open(station_name: String) -> void:
	title_label.text = station_name
	panel.visible = true

func close() -> void:
	panel.visible = false

func update_skill(level: int) -> void:
	skill_label.text = "🔨 Schmieden: Stufe %d" % level

## entries: Array[Dictionary] mit {recipe_id, display_name, detail, enabled}
## `detail` ist die zweite Zeile (Zutaten/Voraussetzungen), `enabled` steuert den Button.
func set_entries(entries: Array[Dictionary], on_craft: Callable) -> void:
	_clear(list)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(hier gibt es nichts herzustellen)"
		empty.modulate = Color(1, 1, 1, 0.5)
		list.add_child(empty)
		return
	for entry in entries:
		list.add_child(_build_row(entry, on_craft))
	UIMetrics.allow_scroll_through(list)

func _build_row(entry: Dictionary, on_craft: Callable) -> PanelContainer:
	var enabled: bool = bool(entry.get("enabled", false))
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", UIMetrics.row_style())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = String(entry.get("display_name", ""))
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	name_lbl.modulate = Color(1, 1, 1, 1.0) if enabled else Color(1, 1, 1, 0.55)
	texts.add_child(name_lbl)
	var detail_lbl := Label.new()
	detail_lbl.text = String(entry.get("detail", ""))
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.add_theme_font_size_override("font_size", 14)
	detail_lbl.modulate = Color(0.75, 0.9, 0.75, 0.9) if enabled else Color(1.0, 0.65, 0.55, 0.9)
	texts.add_child(detail_lbl)
	row.add_child(texts)

	var btn := Button.new()
	btn.text = "Herstellen"
	btn.custom_minimum_size = Vector2(130, UIMetrics.TAP_MIN)
	btn.disabled = not enabled
	var recipe_id: String = String(entry.get("recipe_id", ""))
	btn.pressed.connect(func(): on_craft.call(recipe_id))
	row.add_child(btn)
	return row_panel

func _clear(container: VBoxContainer) -> void:
	# queue_free() statt free(): _clear() läuft synchron innerhalb der Button-pressed-Signalkette,
	# die es auslöst (siehe ShopVisuals._clear(), BUGFIX 2026-09-21).
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
