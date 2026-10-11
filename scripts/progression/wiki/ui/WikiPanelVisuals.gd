class_name WikiPanelVisuals

## WikiPanelVisuals — reine Darstellung, keine Logik (analog
## AchievementPanelVisuals/SkillPanelVisuals/QuestPanelVisuals). Round 108.
##
## Baut das Panel programmatisch (kein .tscn) — exakt dasselbe Muster wie
## alle anderen HUD-Panels im Projekt, siehe AchievementPanelVisuals-
## Klassenkommentar für die Begründung.
##
## Toggle-Button-Position: nächster freier Slot in der oberen Button-Reihe
## nach Skill (112–192), Quest (208–288), Achievement (304–384) → 400–480.
##
## UNENTDECKT ("???"): anders als Achievement (dort sind ALLE Definitionen
## inkl. Name/Beschreibung immer sichtbar, nur der Fortschrittsbalken
## verändert sich) zeigt ein unentdeckter Wiki-Eintrag bewusst NUR "???" —
## kein Name, keine Beschreibung, keine Werte. Genau das war die
## Scoping-Vorgabe ("er muss es freischalten entdecken"): das Wiki soll
## selbst die Existenz eines Eintrags nicht vorab verraten, nur DASS es
## in dieser Kategorie noch etwas zu entdecken gibt (die Zeile existiert
## als Platzhalter, sobald WikiPanelController sie über den DataService-
## Katalog kennt).

const CATEGORY_LABELS: Dictionary = {
	"enemies": "Gegner",
	"drops":   "Beute",
	"skills":  "Fertigkeiten",
	"quests":  "Quests",
}

var panel: PanelContainer
var toggle_button: Button

var _list_vbox: VBoxContainer
var _category_sections: Dictionary = {}  # category -> VBoxContainer
var _rows: Dictionary = {}  # "<category>/<entry_id>" -> { container, name_label, desc_label }

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "WikiToggleButton"
	toggle_button.text = "📖"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "WikiPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())

	UIMetrics.place_sheet(panel, UIMetrics.SHEET_WIDTH)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(outer_vbox)

	outer_vbox.add_child(UIMetrics.build_header("📖 Wiki", panel))

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 10)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(UIMetrics.make_scrollable(_list_vbox))

	parent.add_child(panel)
	PanelDock.register_in(parent, &"wiki", panel, PanelDock.Kind.SHEET, toggle_button)

## Erstellt die Zeile bei Bedarf (erster Aufruf pro category/entry_id) und
## aktualisiert sie danach immer vollständig — idempotent. `details` wird
## bei `is_discovered=false` bewusst ignoriert (siehe Klassenkommentar
## "UNENTDECKT").
func update_entry(category: String, entry_id: String, is_discovered: bool, details: Dictionary) -> void:
	var row_key := "%s/%s" % [category, entry_id]
	if not _rows.has(row_key):
		_add_row(category, entry_id, row_key)

	var row: Dictionary = _rows[row_key]
	var name_lbl := row["name_label"] as Label
	var desc_lbl := row["desc_label"] as Label
	var container := row["container"] as VBoxContainer

	if not is_discovered:
		name_lbl.text = "🔒 ???"
		desc_lbl.text = "Noch nicht entdeckt."
		container.modulate = Color(1, 1, 1, 0.45)
		return

	container.modulate = Color(1, 1, 1, 1.0)
	name_lbl.text = "📖 " + _display_name(category, entry_id, details)
	desc_lbl.text = _detail_line(category, details)

func _display_name(category: String, entry_id: String, details: Dictionary) -> String:
	match category:
		"enemies": return String(details.get("display_name", entry_id))
		"drops":   return entry_id.capitalize()
		"skills":  return String(details.get("display_name", entry_id))
		"quests":  return String(details.get("title", entry_id))
		_:         return entry_id

func _detail_line(category: String, details: Dictionary) -> String:
	match category:
		"enemies":
			return "Rüstung %.0f%% · Loot: %s" % [
				float(details.get("armor", 0.0)) * 100.0, String(details.get("loot_table_id", "?")),
			]
		"drops":
			var chances: Dictionary = details.get("drop_chances", {})
			var parts: Array = []
			for item_id in chances:
				parts.append("%s %.0f%%" % [String(item_id), float(chances[item_id])])
			var gold_min: int = int(details.get("gold_min", 0))
			var gold_max: int = int(details.get("gold_max", 0))
			var line := ", ".join(parts)
			if gold_max > 0:
				line += "  ·  %d–%d Gold" % [gold_min, gold_max]
			return line
		"skills":
			return String(details.get("description", ""))
		"quests":
			return String(details.get("description", ""))
		_:
			return ""

func _add_row(category: String, entry_id: String, row_key: String) -> void:
	var section := _get_or_create_section(category)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	container.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	desc_lbl.modulate = Color(1, 1, 1, 0.7)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(desc_lbl)

	section.add_child(container)
	_rows[row_key] = {"container": container, "name_label": name_lbl, "desc_label": desc_lbl}

func _get_or_create_section(category: String) -> VBoxContainer:
	if _category_sections.has(category):
		return _category_sections[category]

	var header_lbl := Label.new()
	header_lbl.text = String(CATEGORY_LABELS.get(category, category.capitalize()))
	header_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	header_lbl.modulate = Color(0.75, 0.85, 1.0, 0.9)
	_list_vbox.add_child(header_lbl)

	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	_list_vbox.add_child(section)

	_category_sections[category] = section
	return section

func toggle() -> void:
	panel.visible = !panel.visible
