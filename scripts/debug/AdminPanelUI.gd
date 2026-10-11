extends CanvasLayer
class_name AdminPanelUI

## AdminPanelUI — Button-Oberfläche für die AdminMenuCommands.
##
## WARUM: AdminMenuCommands.gd registriert seine Befehle (heal/kill/gold/...)
## ausschließlich als Text-Commands im SimpleTerminal (siehe dortiger
## Klassenkommentar "bringt bereits Toggle-Button + Texteingabe mit"). Für
## einzelne Werte (Gold-Betrag, Item-ID, Ziel-Spieler) ist Text-Eingabe okay,
## aber bei wiederholtem Testen (heal/kill/revive/speed-reset) nervt das
## ständige Neutippen. Diese Klasse dupliziert KEINE Admin-Logik — sie baut
## nur Command-Strings zusammen und reicht sie an SimpleTerminal.execute()
## durch (dieselbe Stelle, die auch die Texteingabe des Terminals bedient).
## Neue/geänderte Admin-Befehle in AdminMenuCommands.gd brauchen dadurch
## keine Parallel-Pflege hier — nur ggf. eine neue Zeile in _build_*() unten,
## falls der neue Befehl auch einen eigenen Button verdient.
##
## ERWEITERUNG (2026-09-25): Item-Zeile nutzt jetzt Kategorie- + Item-
## Dropdowns statt eines Freitext-item_id-Felds (siehe _build_item_row()) —
## der Item-Katalog wächst über die Projektlaufzeit stetig, niemand merkt
## sich zuverlässig ~40+ item_ids auswendig.
##
## ERWEITERUNG (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): neue
## "Diagnose"-Sektion mit Buttons für mem/memhistory/pool (siehe SimpleTerminal.gd) — Tap
## statt Tippen, Ergebnis erscheint direkt im _feedback-Label (siehe _on_log_entry()). Deckt
## nur die Anzeige ab; der eigentliche Fix (Pool-Entities nicht mehr als SceneTree-Orphans,
## siehe EntityPool._park_container) sitzt in EntityPool.gd/EntityOrchestrator.gd.
##
## ERWEITERUNG (2026-09-27): Diagnose-Sektion um "Telemetrie: COPY ALL" ergänzt (siehe
## _build_telemetry_copy_row()) — spiegelt SimpleTerminalUIs "COPY ALL" für Logs 1:1, nur
## gegen TelemetryService.get_all_text()/export_all_text_to_file(). Außerdem: der ADMIN-
## Toggle-Button ist jetzt genau wie der LOG-Button verschiebbar (DraggableToggleController,
## extrahiert aus TerminalController — siehe dort für die BUG-25-Hintergründe).
##
## GATING: identisch zu SimpleTerminal — nur im Debug-Build, nur lokal
## (siehe AdminMenuCommands.gd "SCOPE (bewusst): nur lokal, Solo/Host").
## Wird von SimpleTerminal._ready() analog zu SimpleTerminalUI instanziiert,
## NACH AdminMenuCommands.new(self), damit alle Commands schon registriert
## sind, bevor die Buttons sie aufrufen können.
##
## Ein gemeinsames "Ziel"-Feld (Standard leer = "me", siehe
## AdminMenuCommands._resolve_player()) wird von allen spieler-bezogenen
## Buttons genutzt — für kick/tp/bring MUSS es explizit befüllt werden (ein
## eigenes "Ziel" auf sich selbst ergibt dort keinen Sinn), für alle anderen
## ist "leer" gleichbedeutend mit "me".

const LAYER_ORDER := 129  # eine Ebene über SimpleTerminalUI (128), damit Feedback sichtbar bleibt
const PANEL_BOTTOM_GAP := -150
const PANEL_PADDING := 20
const ROW_HEIGHT := 84
const BTN_MIN_SIZE := Vector2(0, 84)
const FIELD_MIN_WIDTH := 160
const TOGGLE_BTN_SIZE := Vector2(160, 100)
const TOGGLE_BTN_START := Vector2(220, 40)  # rechts neben SimpleTerminalUIs "LOG"-Button (40,40)

var _terminal: Node  # SimpleTerminal-Instanz (Autoload) — Pflicht, siehe _ready()

var _panel: Panel
var _scroll: ScrollContainer
var _btn_toggle: Button
var _drag: DraggableToggleController
var _target_field: LineEdit
var _feedback: Label

## Item-Dropdown-Zustand (siehe _build_item_row()/_refresh_item_catalog()).
var _item_category_option: OptionButton
var _item_option: OptionButton
var _item_catalog: Dictionary = {}   # { Kategorie (String): Array[{id, display_name}] }

func _ready() -> void:
	layer = LAYER_ORDER
	_terminal = get_parent()
	assert(_terminal != null, "AdminPanelUI MUSS ein Kind von SimpleTerminal sein!")

	_build_ui()

	_terminal.entry_added.connect(_on_log_entry)
	_update_visibility(false)

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_bottom = PANEL_BOTTOM_GAP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, PANEL_PADDING
	)
	_panel.add_child(vbox)

	vbox.add_child(_build_target_row())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_scroll.add_child(rows)

	rows.add_child(_section_label("Leben"))
	rows.add_child(_build_simple_row(["Heal", "Kill", "Revive"], ["heal", "kill", "revive"]))
	rows.add_child(_build_value_row("Leben setzen", "sethealth", "Wert"))
	rows.add_child(_build_value_row("Max. Leben setzen", "maxhealth", "Wert"))

	rows.add_child(_section_label("Wirtschaft"))
	rows.add_child(_build_value_row("Gold geben/abziehen", "gold", "Betrag (±)"))
	rows.add_child(_build_item_row())
	rows.add_child(_build_giveall_row())

	rows.add_child(_section_label("Fortschritt"))
	rows.add_child(_build_skill_level_row())

	rows.add_child(_section_label("Bewegung"))
	rows.add_child(_build_value_row("Speed setzen", "speed", "Multiplikator"))
	rows.add_child(_build_simple_row(["Speed zurücksetzen"], ["speed 1"]))

	rows.add_child(_section_label("Session"))
	rows.add_child(_build_simple_row(["Spieler auflisten", "Rollen auflisten"], ["players", "role"]))
	rows.add_child(_build_value_row("Rolle setzen (Ziel + Rolle)", "role", "Rolle"))
	rows.add_child(_build_target_only_row("Kicken", "kick"))
	rows.add_child(_build_target_only_row("Zu Ziel teleportieren", "tp"))
	rows.add_child(_build_target_only_row("Ziel zu mir holen", "bring"))

	rows.add_child(_section_label("Umgebung"))
	rows.add_child(_build_weather_row())
	rows.add_child(_build_time_of_day_row())
	rows.add_child(_build_tick_speed_row())

	# BUGFIX/ERWEITERUNG (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): bisher nur
	# per Text-Befehl im Terminal abrufbar (mem/memhistory/pool, siehe SimpleTerminal.gd) —
	# als Buttons hier reicht ein Tap, das Ergebnis erscheint direkt im _feedback-Label
	# darunter (siehe _on_log_entry()), kein Eintippen nötig.
	rows.add_child(_section_label("Diagnose"))
	rows.add_child(_build_global_row(
		["Speicher-Snapshot", "Speicher-Verlauf", "Entity-Pool"],
		["mem", "memhistory", "pool"]
	))
	# ERWEITERUNG (2026-09-27, "Copy/Export-Button wie bei Logs, nur für Telemetrie"):
	# spiegelt SimpleTerminalUI._build_toolbar()s "COPY ALL"-Button 1:1 (Clipboard +
	# zusätzliche user://-Datei als Fallback gegen Clipboard-Kürzung auf Mobile), nur
	# gegen TelemetryService.get_all_text()/export_all_text_to_file() statt gegen
	# SimpleTerminal — siehe dortige Kommentare.
	rows.add_child(_build_telemetry_copy_row())

	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.y = 60
	vbox.add_child(_feedback)

	_build_toggle_button()

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	return lbl

## Gemeinsames Ziel-Feld — leer = "me" (siehe AdminMenuCommands._resolve_player()).
func _build_target_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT

	var lbl := Label.new()
	lbl.text = "Ziel:"
	row.add_child(lbl)

	_target_field = LineEdit.new()
	_target_field.placeholder_text = "leer = ich selbst"
	_target_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	row.add_child(_target_field)

	return row

## Reihe mit N Buttons, die je einen festen Command (ohne Wert-Eingabe) mit
## dem aktuellen Ziel-Feld ausführen — z.B. Heal/Kill/Revive.
func _build_simple_row(labels: Array, commands: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = BTN_MIN_SIZE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cmd: String = commands[i]
		btn.pressed.connect(func() -> void: _run(cmd + _target_suffix()))
		row.add_child(btn)
	return row

## Reihe mit N Buttons für GLOBALE Befehle OHNE Ziel-Spieler-Bezug — analog
## _build_weather_row(), aber wiederverwendbar (z.B. Diagnose-Befehle mem/memhistory/pool,
## die anders als _build_simple_row() bewusst KEINEN Ziel-Suffix anhängen, siehe dortiger
## Kommentar zu _build_weather_row()).
func _build_global_row(labels: Array, commands: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = BTN_MIN_SIZE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cmd: String = commands[i]
		btn.pressed.connect(func() -> void: _run(cmd))
		row.add_child(btn)
	return row

## "COPY ALL" für Telemetrie — siehe Aufrufstelle in _build_ui() für den Vergleich zu
## SimpleTerminalUI._on_copy_pressed(). Holt TelemetryService direkt über den
## ServiceOrchestrator (wie _refresh_item_catalog() es für InventorySystem tut) statt über
## einen eigenen Terminal-Befehl — Copy/Export ist reine UI-Aktion, kein Diagnose-Text, der
## auch im Log auftauchen soll (anders als mem/memhistory/pool, siehe _build_global_row()).
func _build_telemetry_copy_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT

	var btn := Button.new()
	btn.text = "Telemetrie: COPY ALL"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = BTN_MIN_SIZE
	btn.pressed.connect(_on_telemetry_copy_pressed)
	row.add_child(btn)
	return row

func _on_telemetry_copy_pressed() -> void:
	var orch := get_node_or_null("/root/ServiceOrchestrator")
	if orch == null:
		_show_feedback("ServiceOrchestrator nicht verfügbar.")
		return
	var telemetry: Object = orch.get_service(ServiceKeys.TELEMETRY)
	if not is_instance_valid(telemetry):
		_show_feedback("TelemetryService nicht verfügbar (Welt nicht geladen?).")
		return

	DisplayServer.clipboard_set(telemetry.get_all_text())
	var exported_path: String = telemetry.export_all_text_to_file()
	if exported_path.is_empty():
		_show_feedback("Telemetrie in Zwischenablage kopiert (Datei-Export fehlgeschlagen, siehe Log).")
	else:
		_show_feedback("Telemetrie kopiert + zusätzlich gespeichert: %s" % exported_path)

## Wetter-Buttons — bewusst NICHT über _build_simple_row(): "weather" ist
## global (kein Ziel-Spieler), die geteilte Ziel-Zeile ("Ziel:") würde bei
## _build_simple_row() unbemerkt an den Befehl angehängt (siehe
## AdminMenuCommands._cmd_weather() — args[1+] wird dort zwar folgenlos
## ignoriert statt einen Fehler zu werfen, aber ein befülltes Ziel-Feld
## suggeriert fälschlich, es habe hier eine Bedeutung).
func _build_weather_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var labels := ["Klar", "Regen", "Sturm", "Nebel", "Schnee"]
	var weather_ids := ["clear", "rain", "storm", "fog", "snow"]
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = BTN_MIN_SIZE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var weather_id: String = weather_ids[i]
		btn.pressed.connect(func() -> void: _run("weather " + weather_id))
		row.add_child(btn)
	return row

## Tageszeit-Buttons — dasselbe "eigene Zeile statt _build_simple_row()"-
## Argument wie bei _build_weather_row(): "time" ist global, kein Ziel-Spieler.
func _build_time_of_day_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var labels := ["Morgen", "Mittag", "Abend", "Mitternacht"]
	var presets := ["morgen", "mittag", "abend", "mitternacht"]
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = BTN_MIN_SIZE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var preset: String = presets[i]
		btn.pressed.connect(func() -> void: _run("time " + preset))
		row.add_child(btn)
	return row

## Zeitgeschwindigkeits-Buttons — feste Presets statt einer Werte-Eingabe
## (siehe _build_value_row()), weil "wie schnell soll es normal/schnell
## laufen" eine Handvoll sinnvoller Antworten hat und ein Zahlenfeld hier
## eher zum Vertippen (0.5 vs. 5 vs. 50) einlädt als zu helfen. Absolute
## Zeitgeschwindigkeits-Werte statt Multiplikatoren an der Aufrufstelle,
## damit AdminMenuCommands._cmd_tick() nicht selbst multiplizieren muss —
## Beschriftung zeigt trotzdem den Faktor relativ zu DEFAULT_TIME_SPEED (0.05).
func _build_tick_speed_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var labels := ["Normal", "Schnell (10x)", "Sehr schnell (50x)"]
	var commands := ["tick reset", "tick 0.5", "tick 2.5"]
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = BTN_MIN_SIZE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cmd: String = commands[i]
		btn.pressed.connect(func() -> void: _run(cmd))
		row.add_child(btn)
	return row

## Reihe mit Werte-Eingabe + Button — z.B. "sethealth <wert> [ziel]".
func _build_value_row(label: String, command: String, placeholder: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT

	var value_field := LineEdit.new()
	value_field.placeholder_text = placeholder
	value_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	row.add_child(value_field)

	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = BTN_MIN_SIZE
	btn.pressed.connect(func() -> void:
		if value_field.text.strip_edges().is_empty():
			_show_feedback("Wert fehlt für '%s'." % command)
			return
		_run("%s %s%s" % [command, value_field.text.strip_edges(), _target_suffix()])
	)
	row.add_child(btn)
	return row

## Skill-Level setzen: Freitext-skill_id (bewusst kein Dropdown wie beim
## Item-Katalog — Skills sind eine kleine, stabile Handvoll fester IDs
## (siehe SkillDefinition-Dateien unter data/skills/), kein wachsender
## ~40+-Katalog wie bei Items, für den sich ein Dropdown lohnt) + Level-Feld.
## Ruft AdminMenuCommands._cmd_setskilllevel() → SkillSystem.
## request_set_level() durch.
func _build_skill_level_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT

	var skill_field := LineEdit.new()
	skill_field.placeholder_text = "Skill-ID (z.B. woodcutting)"
	skill_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_field.custom_minimum_size.x = FIELD_MIN_WIDTH
	row.add_child(skill_field)

	var level_field := LineEdit.new()
	level_field.placeholder_text = "Level"
	level_field.custom_minimum_size.x = FIELD_MIN_WIDTH * 0.6
	row.add_child(level_field)

	var btn := Button.new()
	btn.text = "Skill-Level setzen"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = BTN_MIN_SIZE
	btn.pressed.connect(func() -> void:
		var skill_id := skill_field.text.strip_edges()
		var level := level_field.text.strip_edges()
		if skill_id.is_empty() or level.is_empty():
			_show_feedback("Skill-ID und Level werden beide gebraucht.")
			return
		_run("setskilllevel %s %s%s" % [skill_id, level, _target_suffix()])
	)
	row.add_child(btn)
	return row

## Item-Zeile: Dropdown statt Freitext-item_id.
##
## BUGFIX/ERWEITERUNG (2026-09-25, "500 item_ids merken sich niemand"):
## vorher ein reines LineEdit für item_id — man musste die exakte ID
## auswendig kennen. Jetzt zwei OptionButtons (Kategorie → Item), Anzeige per
## display_name statt id, id nur noch intern als Metadata auf dem
## Item-Dropdown-Eintrag.
##
## Kategorisierung ist bewusst NICHT über ein neues @export-Feld auf
## ItemDefinition gelöst (hätte jede der ~40 .tres-Dateien angefasst und
## müsste ab jetzt bei jedem neuen Item von Hand gepflegt werden) — sondern
## rein aus dem bereits vorhandenen Typ/den vorhandenen Feldern abgeleitet
## (siehe _categorize_item()): WeaponDefinition/ToolDefinition-Subtyp, sowie
## ItemDefinition.grants_protection_type/pickpocket_crystal_tier/
## plants_crop_id (ADR-038/039, Farming) — dieselben Felder, die die
## jeweiligen Services bereits zur Laufzeit auswerten. Ein neues Item landet
## dadurch automatisch in der richtigen Kategorie, ganz ohne Zusatzpflege.
func _build_item_row() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT

	_item_category_option = OptionButton.new()
	_item_category_option.custom_minimum_size.x = FIELD_MIN_WIDTH
	_item_category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_category_option.item_selected.connect(func(_idx: int) -> void: _populate_item_dropdown())
	row.add_child(_item_category_option)

	_item_option = OptionButton.new()
	_item_option.custom_minimum_size.x = FIELD_MIN_WIDTH
	_item_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_item_option)

	container.add_child(row)

	var row2 := HBoxContainer.new()
	row2.custom_minimum_size.y = ROW_HEIGHT

	var qty_field := LineEdit.new()
	qty_field.placeholder_text = "Menge=1"
	qty_field.custom_minimum_size.x = FIELD_MIN_WIDTH * 0.6
	row2.add_child(qty_field)

	var btn := Button.new()
	btn.text = "Item geben"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = BTN_MIN_SIZE
	btn.pressed.connect(func() -> void:
		if _item_option.item_count == 0:
			_show_feedback("Kein Item verfügbar — Katalog leer oder noch keine Session geladen (Panel einmal schließen/öffnen).")
			return
		var item_id: String = _item_option.get_item_metadata(_item_option.get_selected())
		var qty := qty_field.text.strip_edges()
		if qty.is_empty():
			qty = "1"
		_run("item %s %s%s" % [item_id, qty, _target_suffix()])
	)
	row2.add_child(btn)

	container.add_child(row2)
	return container

## "Alles geben" — Gegenstück zum einzelnen Item-Dropdown darüber: statt EIN
## Item auswählen zu müssen, füllt dieser Button das Inventar mit je 1x (oder
## <menge>x) jedes bekannten Items auf einen Schlag (siehe AdminMenuCommands.
## _cmd_giveall() — dieselbe Katalogquelle wie _build_item_row()/
## get_all_item_definitions(), kein separat gepflegter "Alle Items"-Datensatz
## hier in der UI).
func _build_giveall_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT

	var qty_field := LineEdit.new()
	qty_field.placeholder_text = "Menge=1"
	qty_field.custom_minimum_size.x = FIELD_MIN_WIDTH * 0.6
	row.add_child(qty_field)

	var btn := Button.new()
	btn.text = "Alle Items geben"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = BTN_MIN_SIZE
	btn.pressed.connect(func() -> void:
		var qty := qty_field.text.strip_edges()
		if qty.is_empty():
			qty = "1"
		_run("giveall %s%s" % [qty, _target_suffix()])
	)
	row.add_child(btn)
	return row

## Kategorie-Reihenfolge fest statt alphabetisch — häufig gebrauchte
## Kategorien (Waffen/Werkzeuge) zuerst, Sammel-Kategorie zuletzt.
const _ITEM_CATEGORY_ORDER := [
	"Waffen", "Werkzeuge", "Schutz-Scrolls", "Diebstahl-Kristalle", "Samen", "Rohstoffe & Sonstiges",
]

## Bucket-Zuordnung eines einzelnen Items — siehe Klassenkommentar
## _build_item_row() für die Begründung, wieso rein aus Typ/Feldern
## abgeleitet statt eines gepflegten Kategorie-Felds.
func _categorize_item(def: ItemDefinition) -> String:
	if def is WeaponDefinition:
		return "Waffen"
	if def is ToolDefinition:
		return "Werkzeuge"
	if not def.grants_protection_type.is_empty():
		return "Schutz-Scrolls"
	if not def.pickpocket_crystal_tier.is_empty():
		return "Diebstahl-Kristalle"
	if not def.plants_crop_id.is_empty():
		return "Samen"
	return "Rohstoffe & Sonstiges"

## Liest den kompletten Item-Katalog frisch von InventorySystem — bewusst bei
## jedem Öffnen des Panels neu (siehe _update_visibility()), nicht einmalig
## in _build_ui(): item_registry ist ein Character-Scope-Service, der beim
## ersten Bauen der UI (Hauptmenü, noch keine Session) evtl. noch gar nicht
## existiert.
func _refresh_item_catalog() -> void:
	_item_category_option.clear()
	_item_catalog.clear()

	var orch := get_node_or_null("/root/ServiceOrchestrator")
	if orch == null:
		return
	var inventory: Object = orch.get_service(ServiceKeys.INVENTORY)
	if not is_instance_valid(inventory):
		return

	var defs: Dictionary = inventory.get_all_item_definitions()
	for item_id in defs.keys():
		var def: ItemDefinition = defs[item_id]
		if not is_instance_valid(def):
			continue
		var category := _categorize_item(def)
		if not _item_catalog.has(category):
			_item_catalog[category] = []
		_item_catalog[category].append({"id": item_id, "display_name": def.display_name if not def.display_name.is_empty() else item_id})

	for category in _item_catalog:
		(_item_catalog[category] as Array).sort_custom(func(a, b): return a["display_name"] < b["display_name"])

	# Feste Reihenfolge zuerst, danach alles Unbekannte (falls _categorize_item()
	# je um eine Kategorie erweitert wird, ohne _ITEM_CATEGORY_ORDER nachzuziehen).
	var ordered_categories: Array = []
	for cat in _ITEM_CATEGORY_ORDER:
		if _item_catalog.has(cat):
			ordered_categories.append(cat)
	for cat in _item_catalog.keys():
		if cat not in ordered_categories:
			ordered_categories.append(cat)

	for cat in ordered_categories:
		_item_category_option.add_item("%s (%d)" % [cat, (_item_catalog[cat] as Array).size()])
		_item_category_option.set_item_metadata(_item_category_option.item_count - 1, cat)

	if _item_category_option.item_count > 0:
		_item_category_option.select(0)
	_populate_item_dropdown()

## Füllt das Item-Dropdown mit den Items der aktuell gewählten Kategorie.
func _populate_item_dropdown() -> void:
	_item_option.clear()
	if _item_category_option.item_count == 0:
		return
	var category: String = _item_category_option.get_item_metadata(_item_category_option.get_selected())
	var items: Array = _item_catalog.get(category, [])
	for entry in items:
		_item_option.add_item(entry["display_name"])
		_item_option.set_item_metadata(_item_option.item_count - 1, entry["id"])
	if _item_option.item_count > 0:
		_item_option.select(0)

## Für kick/tp/bring: das Ziel-Feld ist hier PFLICHT (kein "me"-Fallback,
## siehe AdminMenuCommands._cmd_kick()/_cmd_tp()/_cmd_bring()).
func _build_target_only_row(label: String, command: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = BTN_MIN_SIZE
	btn.pressed.connect(func() -> void:
		var target := _target_field.text.strip_edges()
		if target.is_empty():
			_show_feedback("'%s' braucht ein ausgefülltes Ziel-Feld." % command)
			return
		_run("%s %s" % [command, target])
	)
	row.add_child(btn)
	return row

func _target_suffix() -> String:
	var t := _target_field.text.strip_edges()
	return "" if t.is_empty() else " " + t

func _run(command_line: String) -> void:
	_terminal.execute(command_line)

func _show_feedback(text: String) -> void:
	_feedback.text = text

func _on_log_entry(entry) -> void:
	# Nur zeigen wenn das Panel offen ist — spiegelt AdminMenu-Ausgaben
	# (_out_info/_out_warn laufen über AppLogger → SimpleTerminal) direkt
	# hier, ohne zusätzlich das LOG-Panel öffnen zu müssen.
	if entry == null or not _panel.visible:
		return
	_feedback.text = entry.formatted

func _build_toggle_button() -> void:
	_btn_toggle = Button.new()
	_btn_toggle.text = "ADMIN"
	_btn_toggle.z_index = 100
	_btn_toggle.custom_minimum_size = TOGGLE_BTN_SIZE
	# BUGFIX (2026-09-27, "Admin-Button soll wie der Log-Button verschiebbar sein"): vorher
	# ein einfacher .pressed-Klick — jetzt dieselbe (BUG-25-gehärtete) Drag-Erkennung wie der
	# LOG-Button (SimpleTerminalUI._build_toggle_button()/TerminalController), extrahiert nach
	# DraggableToggleController (siehe dort) statt dupliziert. on_tap = genau der bisherige
	# .pressed-Handler.
	_drag = DraggableToggleController.new(func() -> void: _update_visibility(not _panel.visible))
	_btn_toggle.gui_input.connect(func(event: InputEvent) -> void: _drag.handle_button_input(event, _btn_toggle))
	add_child(_btn_toggle)
	_btn_toggle.global_position = TOGGLE_BTN_START

func _update_visibility(is_visible: bool) -> void:
	_panel.visible = is_visible
	_btn_toggle.text = "CLOSE" if is_visible else "ADMIN"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if is_visible else Control.MOUSE_FILTER_IGNORE
	# Katalog bei jedem Öffnen frisch laden (siehe _refresh_item_catalog()-
	# Kommentar: inventory-Service existiert evtl. erst NACH dem Bauen dieser UI).
	if is_visible:
		_refresh_item_catalog()
