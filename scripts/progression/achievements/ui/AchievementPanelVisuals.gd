class_name AchievementPanelVisuals

## AchievementPanelVisuals — reine Darstellung, keine Logik (analog
## SkillPanelVisuals/QuestPanelVisuals). Round 104.
##
## Baut das Panel programmatisch (kein .tscn) — exakt dasselbe Muster wie
## alle anderen HUD-Panels im Projekt (Skill/Quest/Shop/Bank/Trade/
## Auktionshaus), bewusst gewählt statt eines Editor-Scene-Files: Round 103
## hatte ein UI-Panel zurückgestellt, weil ein blind gebautes `.tscn` ohne
## Godot-Editor-Zugriff das höchste Risiko im gesamten Achievement-System
## gewesen wäre. Der programmatische Weg umgeht dieses Risiko vollständig,
## da er derselbe bereits mehrfach produktiv verifizierte Code-Pfad ist.
##
## Toggle-Button-Position: nächster freier Slot in der oberen Button-Reihe
## nach Skill (112–192) und Quest (208–288) → 304–384.

const CATEGORY_LABELS: Dictionary = {
	"combat": "Kampf",
	"economy": "Wirtschaft",
	"social": "Sozial",
	"stats": "Statistiken",
	"easter_egg": "??? Geheimnisse",
}

var panel: PanelContainer
var toggle_button: Button

var _list_vbox: VBoxContainer
var _category_sections: Dictionary = {}  # category -> VBoxContainer
var _rows: Dictionary = {}  # achievement_id -> { container, name_label, desc_label, bar, progress_label }

func _init(parent: CanvasLayer) -> void:
	toggle_button = Button.new()
	toggle_button.name = "AchievementToggleButton"
	toggle_button.text = "🏆"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle)

	panel = PanelContainer.new()
	panel.name = "AchievementPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())

	UIMetrics.place_sheet(panel, UIMetrics.SHEET_WIDTH)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(outer_vbox)

	outer_vbox.add_child(UIMetrics.build_header("🏆 Erfolge", panel))

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 10)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(UIMetrics.make_scrollable(_list_vbox))

	parent.add_child(panel)
	PanelDock.register_in(parent, &"achievements", panel, PanelDock.Kind.SHEET, toggle_button)

## Erstellt die Zeile bei Bedarf (erster Aufruf pro achievement_id) und
## aktualisiert sie danach immer vollständig — idempotent, kann beliebig oft
## mit demselben oder geändertem Zustand aufgerufen werden.
##
## Easter Eggs (definition["hidden"] == true, siehe AchievementDefinition.gd):
## solange nicht freigeschaltet, werden Name/Beschreibung durch "???"/einen
## generischen Hinweistext ersetzt — reine Anzeige-Redaktion, Fortschrittsbalken
## und Ziel-Zahl bleiben unverändert sichtbar (ein halbvoller Balken bei einem
## "???"-Eintrag ist Teil des Reizes, nicht verwirrend: man sieht, dass sich
## etwas tut, ohne zu wissen was). Sobald is_unlocked true wird, verschwindet
## die Redaktion automatisch beim nächsten update_achievement()-Aufruf.
func update_achievement(achievement_id: String, definition: Dictionary, current: float, is_unlocked: bool) -> void:
	if not _rows.has(achievement_id):
		_add_row(achievement_id, definition)

	var row: Dictionary = _rows[achievement_id]
	var target: float = float(definition.get("target", 1.0))
	var display_current: float = min(current, target)
	var is_hidden_and_locked: bool = bool(definition.get("hidden", false)) and not is_unlocked
	var name_text: String = "???" if is_hidden_and_locked else String(definition.get("name", achievement_id))
	var desc_text: String = (
		"Geheimes Achievement — wird enthüllt, sobald du es findest."
		if is_hidden_and_locked else String(definition.get("description", ""))
	)

	(row["name_label"] as Label).text = ("✅ " if is_unlocked else "🔒 ") + name_text
	(row["desc_label"] as Label).text = desc_text

	var bar := row["bar"] as ProgressBar
	bar.max_value = max(target, 0.01)
	bar.value = display_current

	var reward: int = int(definition.get("reward_gold", 0))
	var progress_text: String = "%d / %d" % [int(round(display_current)), int(round(target))]
	if reward > 0:
		progress_text += "   ·   %d Gold" % reward
	(row["progress_label"] as Label).text = progress_text

	var container := row["container"] as VBoxContainer
	container.modulate = Color(1, 1, 1, 1.0) if is_unlocked else Color(1, 1, 1, 0.6)

func _add_row(achievement_id: String, definition: Dictionary) -> void:
	var category: String = String(definition.get("category", "misc"))
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

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 12)
	bar.show_percentage = false
	container.add_child(bar)

	var progress_lbl := Label.new()
	progress_lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_SUB)
	progress_lbl.modulate = Color(1, 1, 1, 0.6)
	container.add_child(progress_lbl)

	section.add_child(container)
	_rows[achievement_id] = {
		"container": container, "name_label": name_lbl, "desc_label": desc_lbl,
		"bar": bar, "progress_label": progress_lbl,
	}

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
