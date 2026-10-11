class_name GroundToolVisuals

## GroundToolVisuals — drei Buttons "Graben" / "Füllen" / "Leiter", nur sichtbar mit ausgerüsteter Schaufel.
##
## Position: über dem Kontext-Button (0.70 / 0.85), links vom Sprung-Button — Rechte Bildschirm-
## seite bleibt für Kamera-Drag frei, nichts überlappt (Sprung x ≥ 0.85, Kontext y ≥ 0.85).

var container: HBoxContainer
var dig_button: Button
var fill_button: Button
var ladder_button: Button
## Sense: eigener Knopf-Container (nur sichtbar mit ausgerüsteter Sense), gleiche Position wie die Schaufel-Knöpfe.
var mow_container: HBoxContainer
var mow_button: Button
var plane_container: VBoxContainer
var plane_label: Label
var plane_toggle_button: Button
var plane_set_button: Button
var plane_up_button: Button
var plane_down_button: Button
var plane_level_button: Button

func _init(parent: CanvasLayer) -> void:
	container = HBoxContainer.new()
	container.name = "GroundToolButtons"
	container.anchor_left   = 0.70
	container.anchor_right  = 0.70
	container.anchor_top    = 0.70
	container.anchor_bottom = 0.70
	container.offset_left   = -190
	container.offset_right  = 190
	container.offset_top    = -52
	container.offset_bottom = 52
	container.add_theme_constant_override("separation", 16)
	container.visible = false
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	dig_button  = _make_button("GroundDigButton",  "⬇\nGraben")
	fill_button = _make_button("GroundFillButton", "⬆\nFüllen")
	ladder_button = _make_button("GroundLadderButton", "≣\nLeiter")
	container.add_child(dig_button)
	container.add_child(fill_button)
	container.add_child(ladder_button)
	parent.add_child(container)
	_build_plane_row(parent)

	mow_container = HBoxContainer.new()
	mow_container.name = "GroundMowButtons"
	mow_container.anchor_left   = 0.70
	mow_container.anchor_right  = 0.70
	mow_container.anchor_top    = 0.70
	mow_container.anchor_bottom = 0.70
	mow_container.offset_left   = -90
	mow_container.offset_right  = 90
	mow_container.offset_top    = -52
	mow_container.offset_bottom = 52
	mow_container.visible = false
	mow_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mow_button = _make_button("GroundMowButton", "≋\nMähen")
	mow_container.add_child(mow_button)
	parent.add_child(mow_container)

## Zweite Reihe über den Hauptknöpfen: Ebnen-Modus. "Ebene" schaltet den Modus um; nur im Modus
## erscheinen ⌖ (Ebene hier festlegen), ▲▼ (Ebene ±0,25 m) und "Ebnen" (beide Richtungen).
## Im Modus zielen "Graben"/"Füllen" auf die Ebene (Beschriftung wechselt).
func _build_plane_row(parent: CanvasLayer) -> void:
	plane_container = VBoxContainer.new()
	plane_container.name = "GroundPlanePanel"
	plane_container.anchor_left   = 0.70
	plane_container.anchor_right  = 0.70
	plane_container.anchor_top    = 0.70
	plane_container.anchor_bottom = 0.70
	plane_container.offset_left   = -215
	plane_container.offset_right  = 215
	plane_container.offset_top    = -225
	plane_container.offset_bottom = -68
	plane_container.alignment = BoxContainer.ALIGNMENT_END
	plane_container.add_theme_constant_override("separation", 6)
	plane_container.visible = false
	plane_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	plane_label = Label.new()
	plane_label.name = "GroundPlaneLabel"
	plane_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plane_label.add_theme_font_size_override("font_size", 18)
	plane_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	plane_label.add_theme_constant_override("outline_size", 6)
	plane_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plane_container.add_child(plane_label)

	var row := HBoxContainer.new()
	row.name = "GroundPlaneButtons"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plane_container.add_child(row)

	plane_toggle_button = _make_plane_button("GroundPlaneToggleButton", "▬\nEbene")
	plane_toggle_button.toggle_mode = true
	plane_set_button    = _make_plane_button("GroundPlaneSetButton", "⌖\nHier")
	plane_up_button     = _make_plane_button("GroundPlaneUpButton", "▲\n+0,25")
	plane_down_button   = _make_plane_button("GroundPlaneDownButton", "▼\n−0,25")
	plane_level_button  = _make_plane_button("GroundPlaneLevelButton", "⇅\nEbnen")
	for b: Button in [plane_toggle_button, plane_set_button, plane_up_button, plane_down_button, plane_level_button]:
		row.add_child(b)
	set_plane_mode(false)
	parent.add_child(plane_container)

func set_active(active: bool) -> void:
	container.visible = active
	plane_container.visible = active

func set_mow_active(active: bool) -> void:
	mow_container.visible = active

func set_busy(busy: bool) -> void:
	mow_button.disabled = busy
	dig_button.disabled = busy
	fill_button.disabled = busy
	ladder_button.disabled = busy
	for b: Button in [plane_set_button, plane_up_button, plane_down_button, plane_level_button]:
		b.disabled = busy

## Ebnen-Modus an/aus: zeigt/versteckt die Ebenen-Knöpfe und beschriftet Graben/Füllen um.
func set_plane_mode(on: bool) -> void:
	if plane_toggle_button.button_pressed != on:
		plane_toggle_button.set_pressed_no_signal(on)
	for b: Button in [plane_set_button, plane_up_button, plane_down_button, plane_level_button]:
		b.visible = on
	plane_label.visible = on
	dig_button.text = "⬇\nAbtragen" if on else "⬇\nGraben"
	fill_button.text = "⬆\nAuffüllen" if on else "⬆\nFüllen"

func set_plane_text(text: String) -> void:
	plane_label.text = text

func _make_plane_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(UIMetrics.TOOLBAR_BUTTON - 8, UIMetrics.TOOLBAR_BUTTON - 8)
	b.add_theme_font_size_override("font_size", 18)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b

func _make_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(UIMetrics.TOOLBAR_BUTTON + 20, UIMetrics.TOOLBAR_BUTTON + 16)
	b.add_theme_font_size_override("font_size", 20)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b
