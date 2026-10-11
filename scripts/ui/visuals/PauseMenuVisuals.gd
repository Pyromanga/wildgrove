class_name PauseMenuVisuals

## PauseMenuVisuals — Das In-Game-Optionsmenü (4 Einträge).
##
## Ausgelöst durch den ≡-Menü-Button oben rechts (PauseMenuController).
## Zeigt: Speichern | Laden | Einstellungen | Hauptmenü

var panel: PanelContainer
var menu_button: Button

## Wird von Settings.gd genutzt — injiziert von PauseMenuController.setup()
var _settings_layer: Node = null

func _init(parent: CanvasLayer) -> void:
	# ── Menü-Button (oben rechts, immer sichtbar im Spiel) ──
	menu_button = Button.new()
	menu_button.name = "PauseMenuButton"
	menu_button.text = "≡"
	menu_button.custom_minimum_size = Vector2(UIMetrics.TOOLBAR_BUTTON, UIMetrics.TOOLBAR_BUTTON)
	menu_button.anchor_left   = 1.0
	menu_button.anchor_right  = 1.0
	menu_button.anchor_top    = 0.0
	menu_button.anchor_bottom = 0.0
	menu_button.offset_left   = -(UIMetrics.MARGIN + UIMetrics.TOOLBAR_BUTTON)
	menu_button.offset_right  = -UIMetrics.MARGIN
	menu_button.offset_top    = UIMetrics.MARGIN
	menu_button.offset_bottom = UIMetrics.MARGIN + UIMetrics.TOOLBAR_BUTTON
	menu_button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(menu_button)

	# ── Panel (initial versteckt) ──
	panel = PanelContainer.new()
	panel.name = "PauseMenuPanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)

	# Zentriert im oberen Bildschirmdrittel (unter dem Button)
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = -140
	panel.offset_right  = 140
	panel.offset_top    = UIMetrics.MARGIN + UIMetrics.TOOLBAR_BUTTON + 12
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	parent.add_child(panel)
	# SYSTEM: schließt beim Öffnen alle Seitenfenster, siehe PanelDock.
	PanelDock.register_in(parent, &"pause_menu", panel, PanelDock.Kind.SYSTEM)

func build_buttons(
	on_save:    Callable,
	on_load:    Callable,
	on_settings: Callable,
	on_main_menu: Callable
) -> void:
	## Baut die 4 Menü-Einträge. Wird von PauseMenuController nach _init aufgerufen.
	var vbox := panel.get_child(0) as VBoxContainer
	if not vbox:
		return

	var entries := [
		["💾  Spielstand speichern", on_save],
		["📂  Spielstand laden",     on_load],
		["⚙️  Einstellungen",         on_settings],
		["🏠  Hauptmenü",             on_main_menu],
	]

	for entry in entries:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(260, 72)
		btn.pressed.connect(entry[1] as Callable)
		vbox.add_child(btn)

	# Schließen-Hint
	var hint := Label.new()
	hint.text = "[ Tippe ≡ nochmal zum Schließen ]"
	hint.add_theme_font_size_override("font_size", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.self_modulate = Color(1, 1, 1, 0.45)
	vbox.add_child(hint)

func toggle() -> void:
	panel.visible = !panel.visible

func is_open() -> bool:
	return panel.visible

func close() -> void:
	panel.visible = false
