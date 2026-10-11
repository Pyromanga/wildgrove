class_name PetPanelVisuals

## PetPanelVisuals — "Pets"-Sheet (Pet-Menü).
##
## ÜBERARBEITUNG (Wunsch "Pet-Menü viel zu unübersichtlich → größer, Köpfe der
## Tiere in einem Grid; Tap auf den Kopf öffnet die Auswahl, was gefarmt werden
## soll; dazu Suche/Filter, um zu sehen, welche Tiere gerade was tun"):
##   - LISTENANSICHT: Grid aus großen Kacheln (PetHeadIcon + Name + Status-Zeile),
##     statt einer langen Liste mit je fünf Fähigkeits-Buttons pro Pet.
##   - DETAILANSICHT: Tap auf eine Kachel zeigt im selben Sheet das große
##     Kopfbild, den aktuellen Status und die Fähigkeits-Toggles (wie bisher,
##     nur eben für EIN Pet statt für alle auf einmal). "← Zurück" geht zum Grid.
##   - SUCHE (Name) + FILTER (Alle / Aktiv / Untätig / aktuell ausgeübte
##     Fähigkeit). Gefiltert wird über Sichtbarkeit der Kacheln — kein Rebuild.
##   - Status ("⛏ arbeitet", "🌿 unterwegs", "💤 Untätig") wird vom Controller
##     ca. 1x/Sekunde über refresh_status() nachgeführt, solange das Panel offen
##     ist. Das ändert NUR Texte/Farben/Sichtbarkeit, baut nie Kacheln neu —
##     Scroll-Position und eine geöffnete Detailansicht bleiben dadurch stabil.
##
## STRUKTURELLE Änderungen (Pet gefangen/despawnt, Panel geöffnet) laufen weiter
## über set_pets() mit komplettem Rebuild der Kacheln (kein Row-Diffing —
## Pet-Listen sind klein). Eine offene Detailansicht überlebt das, solange ihr
## Pet noch existiert.
##
## Bewusst zustandslos bzgl. Spiellogik: Toggle-Klicks werden nur über
## `ability_toggled` nach außen gemeldet — ob/wie PetComponent.set_abilities()
## das übernimmt, entscheidet PetPanelController.
##
## Scrollen: Kacheln sind Buttons (Standard-Mausfilter STOP, würde Wisch-
## Gesten verschlucken) — set_pets() ruft deshalb nach jedem Rebuild
## UIMetrics.allow_scroll_through() auf (siehe dortiger Kommentar).

signal ability_toggled(pet_instance_id: int, ability_id: String, enabled: bool)

## Anzeige-Reihenfolge + Label je Fähigkeit (siehe PetAbilities.ALL).
const ABILITY_ORDER: Array[String] = [
	PetAbilities.GATHERING, PetAbilities.MINING, PetAbilities.WOODCUTTING,
	PetAbilities.COMBAT, PetAbilities.DIGGING,
]
const ABILITY_LABELS: Dictionary = {
	PetAbilities.GATHERING:   "🌿 Sammeln",
	PetAbilities.MINING:      "⛏ Bergbau",
	PetAbilities.WOODCUTTING: "🪓 Fällen",
	PetAbilities.COMBAT:      "⚔ Kampf",
	PetAbilities.DIGGING:     "🕳 Graben",
}

## Filter-IDs. Alles außer diesen drei ist eine PetAbilities-ID und filtert auf
## "Pet übt GERADE diese Fähigkeit aus" (nicht: "Pet besitzt diese Fähigkeit").
const FILTER_ALL  := "all"
const FILTER_BUSY := "busy"
const FILTER_IDLE := "idle"
const FILTER_ORDER: Array[String] = [
	FILTER_ALL, FILTER_BUSY, FILTER_IDLE,
	PetAbilities.GATHERING, PetAbilities.MINING, PetAbilities.WOODCUTTING,
	PetAbilities.COMBAT, PetAbilities.DIGGING,
]

## Breiter als der Sheet-Standard (UIMetrics.SHEET_WIDTH): 3 Kachelspalten.
const PANEL_WIDTH := 520.0
const GRID_COLUMNS := 3
const TILE_SIZE := Vector2(140.0, 168.0)
const TILE_ICON_PX := 84.0
const DETAIL_ICON_PX := 160.0
const LIST_SCROLL_HEIGHT := 420.0

const COLOR_ACTING := Color(0.55, 0.95, 0.55)
const COLOR_SEEKING := Color(1.0, 0.85, 0.4)
const COLOR_IDLE := Color(1, 1, 1, 0.55)

var panel: PanelContainer
var toggle_button: Button

var _list_view: VBoxContainer
var _detail_view: VBoxContainer
var _detail_content: VBoxContainer
var _detail_status: Label
var _search_edit: LineEdit
var _filter_button: Button
var _filter_bar: HFlowContainer
var _filter_group: ButtonGroup = ButtonGroup.new()
## Kachel-Container (GridContainer) — Kinder sind genau die Pet-Kacheln.
var _rows: GridContainer
var _empty_label: Label
var _no_match_label: Label

## Zuletzt gesetzte Pet-Daten (siehe set_pets()) — Quelle für Filter + Detail.
var _pets: Array[Dictionary] = []
## pet_instance_id (int) → { "button": Button, "status": Label }
var _tiles: Dictionary = {}
var _filter: String = FILTER_ALL
var _search: String = ""
## 0 = Listenansicht, sonst instance_id des Pets in der Detailansicht.
var _detail_id: int = 0

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "PetToggleButton"
	toggle_button.text = "🐾"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "PetPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())

	UIMetrics.place_sheet(panel, PANEL_WIDTH)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIMetrics.build_header("🐾 Pets", panel))

	_list_view = _build_list_view()
	vbox.add_child(_list_view)

	_detail_view = _build_detail_view()
	_detail_view.visible = false
	vbox.add_child(_detail_view)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"pets", panel, PanelDock.Kind.SHEET, toggle_button)
	panel.visibility_changed.connect(_on_panel_visibility_changed)

# ─────────────────────────────────────────────
# Aufbau
# ─────────────────────────────────────────────

func _build_list_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ListView"
	box.add_theme_constant_override("separation", 10)

	var subtitle := Label.new()
	subtitle.text = "Pet antippen, um Fähigkeiten zuzuweisen"
	subtitle.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	box.add_child(search_row)

	_search_edit = LineEdit.new()
	_search_edit.name = "PetSearch"
	_search_edit.placeholder_text = "🔍 Pet suchen…"
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.custom_minimum_size = Vector2(0.0, float(UIMetrics.FIELD_MIN))
	_search_edit.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	_search_edit.text_changed.connect(_on_search_changed)
	search_row.add_child(_search_edit)

	_filter_button = Button.new()
	_filter_button.name = "PetFilterButton"
	_filter_button.toggle_mode = true
	_filter_button.text = "⚙ Filter"
	_filter_button.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	UIMetrics.tap(_filter_button, 150.0)
	_filter_button.toggled.connect(_on_filter_button_toggled)
	search_row.add_child(_filter_button)

	_filter_bar = HFlowContainer.new()
	_filter_bar.name = "PetFilterBar"
	_filter_bar.visible = false
	_filter_bar.add_theme_constant_override("h_separation", 8)
	_filter_bar.add_theme_constant_override("v_separation", 8)
	box.add_child(_filter_bar)
	for filter_id in FILTER_ORDER:
		var chip := Button.new()
		chip.name = "Filter_%s" % filter_id
		chip.toggle_mode = true
		chip.button_group = _filter_group
		chip.text = filter_label(filter_id)
		chip.button_pressed = filter_id == FILTER_ALL
		chip.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
		chip.custom_minimum_size = Vector2(0.0, 56.0)
		chip.pressed.connect(_on_filter_chosen.bind(filter_id))
		_filter_bar.add_child(chip)

	_empty_label = Label.new()
	_empty_label.text = "Noch kein Pet gezähmt."
	_empty_label.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	_empty_label.modulate = Color(1, 1, 1, 0.6)
	_empty_label.visible = false
	box.add_child(_empty_label)

	_no_match_label = Label.new()
	_no_match_label.text = "Keine Pets passen zu Suche/Filter."
	_no_match_label.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	_no_match_label.modulate = Color(1, 1, 1, 0.6)
	_no_match_label.visible = false
	box.add_child(_no_match_label)

	_rows = GridContainer.new()
	_rows.name = "PetRows"
	_rows.columns = GRID_COLUMNS
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("h_separation", 10)
	_rows.add_theme_constant_override("v_separation", 10)
	box.add_child(UIMetrics.make_scrollable(_rows, LIST_SCROLL_HEIGHT))

	return box

func _build_detail_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "DetailView"
	box.add_theme_constant_override("separation", 12)

	var back := Button.new()
	back.name = "PetBackButton"
	back.text = "← Zurück"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	UIMetrics.tap(back, 0.0)
	back.pressed.connect(_show_grid)
	box.add_child(back)

	_detail_content = VBoxContainer.new()
	_detail_content.name = "DetailContent"
	_detail_content.add_theme_constant_override("separation", 12)
	box.add_child(_detail_content)

	return box

func _build_tile(pet_data: Dictionary) -> Control:
	var pet_id: int = int(pet_data.get("id", 0))

	var btn := Button.new()
	btn.name = "PetTile_%d" % pet_id
	btn.custom_minimum_size = TILE_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_open_detail.bind(pet_id))

	# Inhalt als Kind des Buttons (Button ist kein Container) — alles IGNORE,
	# damit der Tap auf dem Button selbst landet.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	btn.add_child(margin)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	margin.add_child(col)

	var icon := PetHeadIcon.create(pet_data.get("appearance", {}), TILE_ICON_PX)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(icon)

	var name_lbl := Label.new()
	# FEATURE (Pet-XP/Level): Level direkt im Namen statt einer eigenen Zeile —
	# die Kachel ist mit 140x168px knapp bemessen, ein zusätzliches Label hätte
	# entweder den Kopf verkleinert oder die Status-Zeile verdrängt. Bewusst
	# NICHT in refresh_status() mitgepflegt (nur status_lbl ist dort getrackt,
	# siehe _tiles-Dictionary) — ein Level-Up mitten in einer offenen
	# Panel-Sitzung zeigt sich dadurch erst beim nächsten Öffnen, dafür bleibt
	# der 1x/Sekunde-Status-Tick leichtgewichtig (kein zusätzliches Label-Update).
	name_lbl.text = "%s · Lv. %d" % [pet_data.get("name", "Pet"), int(pet_data.get("level", 1))]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB + 1)
	col.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.clip_text = true
	status_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	col.add_child(status_lbl)

	_tiles[pet_id] = {"button": btn, "status": status_lbl}
	_style_status_label(status_lbl, pet_data, true)
	return btn

# ─────────────────────────────────────────────
# Öffentliche API (PetPanelController)
# ─────────────────────────────────────────────

## pets: Array[Dictionary] mit { "id": int (instance_id), "name": String,
## "abilities": Array[String], "appearance": Dictionary (PetComponent.
## get_appearance()), "activity": String (PetAbilities-ID oder ""), "acting":
## bool, "level": int, "xp_into_level": int, "xp_for_next": int (siehe
## PetLeveling) } — siehe PetPanelController._collect_pet_rows(). Baut die
## Kacheln bei JEDEM Aufruf komplett neu auf.
func set_pets(pets: Array[Dictionary]) -> void:
	_pets = pets

	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_tiles.clear()

	for pet_data in pets:
		_rows.add_child(_build_tile(pet_data))

	# MUSS nach jedem Rebuild erneut laufen — die eben neu erzeugten Buttons
	# haben wieder das Standard-STOP (siehe Klassenkommentar oben).
	UIMetrics.allow_scroll_through(_rows)

	_empty_label.visible = pets.is_empty()
	_apply_filter()

	if _detail_id != 0:
		if _find_pet(_detail_id).is_empty():
			# Pet wurde despawnt, während seine Detailansicht offen war.
			_show_grid()
		else:
			_update_detail_status()

## Leichtgewichtiges Nachführen des "was tut es gerade"-Status (Controller-
## Timer): ändert nur Status-Texte/-Farben und die Filter-Sichtbarkeit, baut
## nichts neu. Unbekannte IDs (Pet seit dem letzten set_pets() neu) werden
## ignoriert — set_pets() holt sie beim nächsten strukturellen Refresh nach.
func refresh_status(pets: Array[Dictionary]) -> void:
	for pet_data in pets:
		var pet_id: int = int(pet_data.get("id", 0))
		var idx := _index_of(pet_id)
		if idx < 0:
			continue
		_pets[idx]["activity"] = String(pet_data.get("activity", ""))
		_pets[idx]["acting"] = bool(pet_data.get("acting", false))
		_refresh_tile_status(pet_id)
	_apply_filter()
	_update_detail_status()

func toggle() -> void:
	panel.visible = !panel.visible

# ─────────────────────────────────────────────
# Status-Texte (static → ohne UI testbar)
# ─────────────────────────────────────────────

static func filter_label(filter_id: String) -> String:
	match filter_id:
		FILTER_ALL:  return "Alle"
		FILTER_BUSY: return "⚡ Aktiv"
		FILTER_IDLE: return "💤 Untätig"
		_:           return String(ABILITY_LABELS.get(filter_id, filter_id))

## short = true → nur Emoji + Phase (Kachel ist schmal), sonst volles Label.
static func status_text(activity: String, acting: bool, has_abilities: bool, short: bool = false) -> String:
	if activity.is_empty():
		return "💤 Untätig" if has_abilities else "🐾 Begleiter"
	var label: String = String(ABILITY_LABELS.get(activity, activity))
	var phase := "arbeitet" if acting else "unterwegs"
	if short:
		return "%s %s" % [label.get_slice(" ", 0), phase]
	return "%s · %s" % [label, phase]

## Passt ein Pet zu Suchtext + Filter? Suche: Teilstring im Namen, ohne
## Groß-/Kleinschreibung. Filter: siehe FILTER_*-Konstanten.
static func pet_matches(pet_data: Dictionary, filter_id: String, search: String) -> bool:
	var needle := search.strip_edges().to_lower()
	if not needle.is_empty():
		if String(pet_data.get("name", "")).to_lower().find(needle) < 0:
			return false
	var activity: String = String(pet_data.get("activity", ""))
	match filter_id:
		FILTER_ALL:  return true
		FILTER_BUSY: return not activity.is_empty()
		FILTER_IDLE: return activity.is_empty()
		_:           return activity == filter_id

# ─────────────────────────────────────────────
# Interna: Filter / Suche
# ─────────────────────────────────────────────

func _on_search_changed(text: String) -> void:
	_search = text
	_apply_filter()

func _on_filter_button_toggled(pressed: bool) -> void:
	_filter_bar.visible = pressed

func _on_filter_chosen(filter_id: String) -> void:
	_filter = filter_id
	_apply_filter()

func _apply_filter() -> void:
	var shown := 0
	for pet_data in _pets:
		var pet_id: int = int(pet_data.get("id", 0))
		var tile: Dictionary = _tiles.get(pet_id, {})
		if tile.is_empty():
			continue
		var matches := pet_matches(pet_data, _filter, _search)
		(tile["button"] as Control).visible = matches
		if matches:
			shown += 1
	_no_match_label.visible = not _pets.is_empty() and shown == 0
	_filter_button.text = "⚙ Filter" if _filter == FILTER_ALL else "⚙ %s" % filter_label(_filter)

# ─────────────────────────────────────────────
# Interna: Status
# ─────────────────────────────────────────────

func _refresh_tile_status(pet_id: int) -> void:
	var tile: Dictionary = _tiles.get(pet_id, {})
	var idx := _index_of(pet_id)
	if tile.is_empty() or idx < 0:
		return
	_style_status_label(tile["status"] as Label, _pets[idx], true)

func _update_detail_status() -> void:
	if _detail_id == 0 or not is_instance_valid(_detail_status):
		return
	var pet_data := _find_pet(_detail_id)
	if pet_data.is_empty():
		return
	_style_status_label(_detail_status, pet_data, false)

func _style_status_label(lbl: Label, pet_data: Dictionary, short: bool) -> void:
	var activity: String = String(pet_data.get("activity", ""))
	var acting: bool = bool(pet_data.get("acting", false))
	var abilities: Array = pet_data.get("abilities", [])
	lbl.text = status_text(activity, acting, not abilities.is_empty(), short)
	if activity.is_empty():
		lbl.modulate = COLOR_IDLE
	elif acting:
		lbl.modulate = COLOR_ACTING
	else:
		lbl.modulate = COLOR_SEEKING

func _index_of(pet_id: int) -> int:
	for i in _pets.size():
		if int(_pets[i].get("id", 0)) == pet_id:
			return i
	return -1

func _find_pet(pet_id: int) -> Dictionary:
	var idx := _index_of(pet_id)
	return _pets[idx] if idx >= 0 else {}

# ─────────────────────────────────────────────
# Interna: Detailansicht
# ─────────────────────────────────────────────

func _open_detail(pet_id: int) -> void:
	var pet_data := _find_pet(pet_id)
	if pet_data.is_empty():
		return
	_detail_id = pet_id

	for child in _detail_content.get_children():
		_detail_content.remove_child(child)
		child.queue_free()

	var icon := PetHeadIcon.create(pet_data.get("appearance", {}), DETAIL_ICON_PX)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_content.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = String(pet_data.get("name", "Pet"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_TITLE)
	_detail_content.add_child(name_lbl)

	# FEATURE (Pet-XP/Level, siehe PetLeveling): Level + Fortschrittsbalken zum
	# nächsten Level. xp_for_next == -1 bei MAX_LEVEL (100) — dann volle Leiste
	# ohne "X / Y XP"-Text, da es kein "nächstes Level" mehr gibt.
	var level_lbl := Label.new()
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	level_lbl.modulate = Color(1.0, 0.85, 0.3)
	var level: int = int(pet_data.get("level", 1))
	var xp_into: int = int(pet_data.get("xp_into_level", 0))
	var xp_for_next: int = int(pet_data.get("xp_for_next", -1))
	var xp_bar := ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 10)
	xp_bar.show_percentage = false
	if xp_for_next <= 0:
		level_lbl.text = "Level %d (max)" % level
		xp_bar.max_value = 1
		xp_bar.value = 1
	else:
		level_lbl.text = "Level %d — %d / %d XP" % [level, xp_into, xp_for_next]
		xp_bar.max_value = xp_for_next
		xp_bar.value = xp_into
	_detail_content.add_child(level_lbl)
	_detail_content.add_child(xp_bar)

	_detail_status = Label.new()
	_detail_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_status.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	_detail_content.add_child(_detail_status)

	var subtitle := Label.new()
	subtitle.text = "Was soll dieses Pet tun?"
	subtitle.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	subtitle.modulate = Color(1, 1, 1, 0.6)
	_detail_content.add_child(subtitle)

	var abilities: Array = pet_data.get("abilities", [])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_detail_content.add_child(grid)
	for ability_id in ABILITY_ORDER:
		var btn := Button.new()
		btn.text = String(ABILITY_LABELS.get(ability_id, ability_id))
		btn.toggle_mode = true
		btn.button_pressed = abilities.has(ability_id)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
		UIMetrics.tap(btn, 0.0)
		btn.toggled.connect(_on_detail_ability_toggled.bind(pet_id, ability_id))
		grid.add_child(btn)

	_update_detail_status()
	_list_view.visible = false
	_detail_view.visible = true

func _on_detail_ability_toggled(enabled: bool, pet_id: int, ability_id: String) -> void:
	# Lokalen Datenstand mitführen, damit Status ("Begleiter" vs. "Untätig")
	# und eine spätere Detailansicht ohne Controller-Refresh stimmen.
	var idx := _index_of(pet_id)
	if idx >= 0:
		var abilities: Array = _pets[idx].get("abilities", [])
		if enabled and not abilities.has(ability_id):
			abilities.append(ability_id)
		elif not enabled:
			abilities.erase(ability_id)
		_pets[idx]["abilities"] = abilities
		_refresh_tile_status(pet_id)
		_update_detail_status()
	ability_toggled.emit(pet_id, ability_id, enabled)

func _show_grid() -> void:
	_detail_id = 0
	_detail_view.visible = false
	_list_view.visible = true

func _on_panel_visibility_changed() -> void:
	# Beim Schließen zurück zur Listenansicht — beim nächsten Öffnen soll
	# wieder das Grid erscheinen, nicht die zuletzt angesehene Detailseite.
	if not panel.visible and _detail_id != 0:
		_show_grid()
