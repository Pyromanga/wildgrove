class_name BuildPanelVisuals

## BuildPanelVisuals — Seitenfenster "Bauen": Liste der Bauteile mit Kosten und "Bauen"-Button,
## darunter eine zweite Liste kompletter Hausvorlagen (HouseTemplateDefinition).
## Toggle-Button (🔨) landet in der PanelDock-Toolbar; das Fenster ist ein SHEET (exklusiv).
##
## Reine Darstellung: bekommt fertige Einträge (set_entries/set_house_entries) und meldet nur
## die Wahl (piece_chosen/house_chosen). Kennt weder Daten noch Inventar.

signal piece_chosen(piece_id: String)
## Wahl einer kompletten Hausvorlage (siehe HouseTemplateDefinition) — eigenes Signal, weil
## ein Haus im Baumodus einen eigenen Ablauf braucht (mehrere Teile, Vorschau ohne Regel-
## prüfung), nicht nur ein anderer piece_id-Wert von piece_chosen.
signal house_chosen(template_id: String)

## Kategorie-Tabs über der Bauteil-Liste. -1 = "Alle" (zeigt wirklich alle Bauteile, keine
## Kategorie wird dafür herausgefiltert). Die übrigen Keys sind BuildPieceDefinition.Kind-Werte —
## TARGET fasst alle freistehenden Deko-/Funktionsobjekte zusammen (Grabsteine, Laternen,
## Brunnen, Wegweiser, Türme, ...), dafür gibt es keinen eigenen Kind-Wert.
const CATEGORY_ALL: int = -1
const CATEGORIES: Array[Dictionary] = [
	{"key": -1, "label": "Alle"},
	{"key": 1, "label": "Wände"},   # BuildPieceDefinition.Kind.WALL
	{"key": 0, "label": "Böden"},   # Kind.FLOOR
	{"key": 2, "label": "Dächer"},  # Kind.ROOF
	{"key": 3, "label": "Türen"},   # Kind.DOOR
	{"key": 4, "label": "Fenster"}, # Kind.WINDOW
	{"key": 5, "label": "Treppen"}, # Kind.STAIRS
	{"key": 6, "label": "Deko"},    # Kind.TARGET
]

var panel: PanelContainer
var toggle_button: Button
var _list: VBoxContainer
var _house_list: VBoxContainer
## Ungefilterte Einträge aus set_entries() — _render_list() filtert daraus nach _active_category.
var _all_entries: Array[Dictionary] = []
var _active_category: int = CATEGORY_ALL
var _tab_buttons: Dictionary = {}

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "BuildToggleButton"
	toggle_button.text = "🔨"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "BuildPanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.05, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	UIMetrics.place_sheet(panel, 440)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Bauen"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Bauteil wählen, dann vor die gewünschte Stelle stellen. Zum Abreißen am Bauteil \"Abreißen\" wählen."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW - 3)
	hint.modulate = Color(1, 1, 1, 0.7)
	hint.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(hint)

	# Kategorie-Tabs: eigener Scroll, weil bei schmalen Displays sonst schon die Tabs selbst
	# umbrechen/abgeschnitten würden — horizontal wischen statt Zeilenumbruch mitten im Tab.
	var tab_scroll := ScrollContainer.new()
	tab_scroll.name = "CategoryTabScroll"
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(tab_scroll)

	var tabs := HBoxContainer.new()
	tabs.name = "CategoryTabs"
	tabs.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tabs)
	for cat: Dictionary in CATEGORIES:
		var key: int = int(cat["key"])
		var btn := Button.new()
		btn.text = String(cat["label"])
		btn.toggle_mode = true
		btn.button_pressed = key == CATEGORY_ALL
		btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN - 12)
		btn.pressed.connect(func() -> void: _set_category(key))
		tabs.add_child(btn)
		_tab_buttons[key] = btn
	UIMetrics.allow_scroll_through(tabs)

	# Feste Maximalhöhe statt unbegrenzt mitwachsend (UIMetrics.place_sheet lässt das Panel mit
	# seinem Inhalt wachsen — bei 30+ Bauteilen läuft das sonst unten aus dem Bildschirm).
	# Innerhalb dieser Höhe wird gescrollt statt weiter zu wachsen.
	_list = VBoxContainer.new()
	_list.name = "PieceList"
	_list.add_theme_constant_override("separation", 8)
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "PieceListScroll"
	list_scroll.custom_minimum_size = Vector2(0, 360)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.add_child(_list)
	vbox.add_child(list_scroll)

	var house_title := Label.new()
	house_title.name = "HouseTitle"
	house_title.text = "Häuser"
	house_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(house_title)

	var house_hint := Label.new()
	house_hint.text = "Komplettes Haus auf einmal: alles oder nichts, kein halb gebautes Haus, kein verschwendetes Material."
	house_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	house_hint.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW - 3)
	house_hint.modulate = Color(1, 1, 1, 0.7)
	house_hint.custom_minimum_size = Vector2(0, 0)
	vbox.add_child(house_hint)

	_house_list = VBoxContainer.new()
	_house_list.name = "HouseList"
	_house_list.add_theme_constant_override("separation", 8)
	var house_scroll := ScrollContainer.new()
	house_scroll.name = "HouseListScroll"
	house_scroll.custom_minimum_size = Vector2(0, 220)
	house_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	house_scroll.add_child(_house_list)
	vbox.add_child(house_scroll)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"build", panel, PanelDock.Kind.SHEET, toggle_button)

func _set_category(key: int) -> void:
	_active_category = key
	for cat_key: int in _tab_buttons.keys():
		(_tab_buttons[cat_key] as Button).button_pressed = cat_key == key
	_render_list()

func toggle() -> void:
	panel.visible = not panel.visible

func close() -> void:
	panel.visible = false

## entries: [{id, name, cost_text, affordable, kind}] — ersetzt die gesamte Liste. "kind" ist
## optional (fehlt z.B. in Tests): solche Einträge landen immer im "Alle"-Tab.
func set_entries(entries: Array[Dictionary]) -> void:
	_all_entries = entries
	_render_list()

## Baut _list neu aus _all_entries, gefiltert nach _active_category. "Alle" zeigt wirklich
## alles — auch Einträge ohne "kind" — die Kategorie-Tabs zeigen nur ihre eigene Kategorie.
func _render_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for entry in _all_entries:
		if _active_category != CATEGORY_ALL and int(entry.get("kind", CATEGORY_ALL)) != _active_category:
			continue
		_list.add_child(_make_row(entry))
	# FIX (Wunsch "Scrollen geht häufig nicht"): siehe UIMetrics.allow_scroll_through().
	UIMetrics.allow_scroll_through(_list)

func get_row_count() -> int:
	return _list.get_child_count()

## entries: [{id, name, description, cost_text, affordable}] — ersetzt die gesamte Liste.
func set_house_entries(entries: Array[Dictionary]) -> void:
	for child in _house_list.get_children():
		_house_list.remove_child(child)
		child.queue_free()
	for entry in entries:
		_house_list.add_child(_make_house_row(entry))
	UIMetrics.allow_scroll_through(_house_list)

func get_house_row_count() -> int:
	return _house_list.get_child_count()

func _make_house_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = String(entry.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW + 2)
	texts.add_child(name_lbl)
	var desc: String = String(entry.get("description", ""))
	if not desc.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW - 3)
		desc_lbl.modulate = Color(1, 1, 1, 0.65)
		desc_lbl.custom_minimum_size = Vector2(0, 0)
		texts.add_child(desc_lbl)
	var cost_lbl := Label.new()
	cost_lbl.text = String(entry.get("cost_text", ""))
	cost_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW - 2)
	cost_lbl.modulate = Color(0.75, 1.0, 0.75) if bool(entry.get("affordable", false)) else Color(1.0, 0.6, 0.6)
	texts.add_child(cost_lbl)
	row.add_child(texts)

	var btn := Button.new()
	btn.text = "Bauen"
	btn.custom_minimum_size = Vector2(120, UIMetrics.TAP_MIN)
	btn.disabled = not bool(entry.get("affordable", false))
	var template_id: String = String(entry.get("id", ""))
	btn.pressed.connect(func() -> void: house_chosen.emit(template_id))
	row.add_child(btn)
	return row

func _make_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = String(entry.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW + 2)
	texts.add_child(name_lbl)
	var cost_lbl := Label.new()
	cost_lbl.text = String(entry.get("cost_text", ""))
	cost_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW - 2)
	cost_lbl.modulate = Color(0.75, 1.0, 0.75) if bool(entry.get("affordable", false)) else Color(1.0, 0.6, 0.6)
	texts.add_child(cost_lbl)
	row.add_child(texts)

	var btn := Button.new()
	btn.text = "Bauen"
	btn.custom_minimum_size = Vector2(120, UIMetrics.TAP_MIN)
	btn.disabled = not bool(entry.get("affordable", false))
	var piece_id: String = String(entry.get("id", ""))
	btn.pressed.connect(func() -> void: piece_chosen.emit(piece_id))
	row.add_child(btn)
	return row
