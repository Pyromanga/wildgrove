extends CanvasLayer
class_name DebugConsoleUI

## DebugConsoleUI.gd
## Das visuelle Overlay. Wird von DebugService als Child zur Szene hinzugefügt.
## Struktur:
##   CanvasLayer (layer=128, damit es immer über allem liegt)
##     Panel (halbtransparent, obere Hälfte des Screens)
##       VBoxContainer
##         HBoxContainer (Toolbar)
##           Label "WildGrove Debug"
##           OptionButton (Level-Filter)
##           LineEdit (Kategorie-Filter)
##           Button "Copy"
##           Button "Clear"
##           Button "✕"
##         ScrollContainer
##           RichTextLabel (Log-Output)
##         HBoxContainer (Input)
##           LineEdit (Command-Input)
##           Button "Run"

const LOG_CAT := "DebugConsoleUI"

# Farben pro Log-Level für BBCode
const LEVEL_COLORS := {
	Logger.LogLevel.DEBUG: "gray",
	Logger.LogLevel.INFO:  "white",
	Logger.LogLevel.WARN:  "yellow",
	Logger.LogLevel.ERROR: "red",
}

var _console: DebugConsole
var _log_output:       RichTextLabel
var _scroll:           ScrollContainer
var _cmd_input:        LineEdit
var _level_filter:     OptionButton
var _category_filter:  LineEdit
var _panel:            Panel

var _current_level_filter:    Logger.LogLevel = Logger.LogLevel.DEBUG
var _current_category_filter: String = ""

# ─────────────────────────────────────────────
# Setup — wird von DebugService aufgerufen
# ─────────────────────────────────────────────

func setup(console: DebugConsole) -> void:
	Logger.log_debug("setup() — baue UI auf...", LOG_CAT)
	_console = console
	layer = 128  # Über allem

	_build_ui()
	_connect_signals()

	# Initialen Log-Inhalt laden
	_rebuild_log()

	# Erstmal versteckt
	_panel.visible = false
	Logger.log_debug("UI aufgebaut und versteckt.", LOG_CAT)

# ─────────────────────────────────────────────
# UI Builder (rein per Code, keine .tscn nötig)
# ─────────────────────────────────────────────

func _build_ui() -> void:
	Logger.log_debug("_build_ui()...", LOG_CAT)

	# Halbtransparentes Panel — obere 55% des Screens
	_panel = Panel.new()
	_panel.name = "DebugPanel"
	_panel.anchor_right  = 1.0
	_panel.anchor_bottom = 0.55
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# Toolbar
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 36
	toolbar.add_theme_constant_override("separation", 8)
	vbox.add_child(toolbar)

	var title := Label.new()
	title.text = "  WildGrove Debug"
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)

	# Level-Filter Dropdown
	_level_filter = OptionButton.new()
	_level_filter.custom_minimum_size.x = 90
	for lvl_name in Logger.LogLevel.keys():
		_level_filter.add_item(lvl_name)
	_level_filter.selected = 0  # DEBUG
	toolbar.add_child(_level_filter)

	# Kategorie-Filter
	_category_filter = LineEdit.new()
	_category_filter.placeholder_text = "Kategorie..."
	_category_filter.custom_minimum_size.x = 120
	toolbar.add_child(_category_filter)

	# Copy-Button
	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.pressed.connect(_on_copy_pressed)
	toolbar.add_child(copy_btn)

	# Clear-Button
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_clear_pressed)
	toolbar.add_child(clear_btn)

	# Schließen-Button
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_on_close_pressed)
	toolbar.add_child(close_btn)

	# ScrollContainer + RichTextLabel für Log
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_log_output = RichTextLabel.new()
	_log_output.bbcode_enabled = true
	_log_output.scroll_following = true
	_log_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_output.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_log_output.add_theme_font_size_override("normal_font_size", 11)
	_scroll.add_child(_log_output)

	# Command-Input
	var input_row := HBoxContainer.new()
	input_row.custom_minimum_size.y = 32
	input_row.add_theme_constant_override("separation", 4)
	vbox.add_child(input_row)

	var prompt := Label.new()
	prompt.text = "  >"
	prompt.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	input_row.add_child(prompt)

	_cmd_input = LineEdit.new()
	_cmd_input.placeholder_text = "Command eingeben... (help für Liste)"
	_cmd_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd_input.text_submitted.connect(_on_command_submitted)
	input_row.add_child(_cmd_input)

	var run_btn := Button.new()
	run_btn.text = "Run"
	run_btn.pressed.connect(func(): _on_command_submitted(_cmd_input.text))
	input_row.add_child(run_btn)

	Logger.log_debug("_build_ui() abgeschlossen.", LOG_CAT)

func _connect_signals() -> void:
	Logger.log_debug("_connect_signals()...", LOG_CAT)
	_console.entry_added.connect(_on_entry_added)
	_console.console_toggled.connect(_on_console_toggled)
	_level_filter.item_selected.connect(_on_level_filter_changed)
	_category_filter.text_changed.connect(_on_category_filter_changed)
	Logger.log_debug("Signals verbunden.", LOG_CAT)

# ─────────────────────────────────────────────
# Log Rendering
# ─────────────────────────────────────────────

func _rebuild_log() -> void:
	Logger.log_debug("_rebuild_log() — filtere und rendere alle Einträge...", LOG_CAT)
	_log_output.clear()
	var entries := _console.get_entries(_current_level_filter, _current_category_filter)
	for entry in entries:
		_append_entry(entry)
	Logger.log_debug("_rebuild_log() — %d Einträge gerendert." % entries.size(), LOG_CAT)

func _append_entry(entry: DebugConsole.LogEntry) -> void:
	var color: String = LEVEL_COLORS.get(entry.level, "white")
	var line := "[color=gray]%s[/color] [color=%s][%s][/color] [color=cyan][%s][/color] %s\n" % [
		entry.timestamp,
		color,
		Logger.LogLevel.keys()[entry.level],
		entry.category,
		entry.message
	]
	_log_output.append_text(line)

# ─────────────────────────────────────────────
# Input — F1 oder Tipp-Geste zum Togglen
# ─────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Desktop: F1
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F1:
			Logger.log_debug("F1 gedrückt — toggle Console.", LOG_CAT)
			_console.toggle()
			get_viewport().set_input_as_handled()

	# Mobile: 4-Finger-Tap (4 simultane Touches)
	if event is InputEventScreenTouch and event.pressed:
		if Input.get_touching_index_count() >= 4:
			Logger.log_debug("4-Finger-Tap erkannt — toggle Console.", LOG_CAT)
			_console.toggle()

# ─────────────────────────────────────────────
# Signal Handler
# ─────────────────────────────────────────────

func _on_entry_added(entry: DebugConsole.LogEntry) -> void:
	if entry.level < _current_level_filter:
		return
	if _current_category_filter != "" and not entry.category.begins_with(_current_category_filter):
		return
	_append_entry(entry)

func _on_console_toggled(visible: bool) -> void:
	Logger.log_debug("_on_console_toggled(%s)" % str(visible), LOG_CAT)
	_panel.visible = visible
	if visible:
		_cmd_input.grab_focus()

func _on_copy_pressed() -> void:
	Logger.log_debug("Copy-Button gedrückt.", LOG_CAT)
	var text := _console.get_all_as_text(_current_level_filter, _current_category_filter)
	DisplayServer.clipboard_set(text)
	Logger.log_info("Log in Zwischenablage kopiert (%d Zeichen)." % text.length(), LOG_CAT)

func _on_clear_pressed() -> void:
	Logger.log_debug("Clear-Button gedrückt.", LOG_CAT)
	_console.execute("clear")
	_log_output.clear()

func _on_close_pressed() -> void:
	Logger.log_debug("Console geschlossen.", LOG_CAT)
	_console.toggle()

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	Logger.log_debug("Command submitted: '%s'" % text, LOG_CAT)
	_console.execute(text)
	_cmd_input.clear()

func _on_level_filter_changed(index: int) -> void:
	_current_level_filter = index as Logger.LogLevel
	Logger.log_debug("Level-Filter geändert → %s" % Logger.LogLevel.keys()[index], LOG_CAT)
	_rebuild_log()

func _on_category_filter_changed(text: String) -> void:
	_current_category_filter = text.strip_edges()
	Logger.log_debug("Kategorie-Filter geändert → '%s'" % _current_category_filter, LOG_CAT)
	_rebuild_log()
