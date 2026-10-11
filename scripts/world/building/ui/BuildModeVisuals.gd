class_name BuildModeVisuals

## BuildModeVisuals — Bedienelemente im Baumodus: Drehen, Bauen, Abbrechen + Hinweistext,
## dazu ein Steuerkreuz rechts (Verschieben in 3 Achsen + Zurück zum Blick-Zielen).
## Die Hauptknöpfe sitzen mittig über der HP-Leiste (0.5 / 0.62); das Steuerkreuz rechts auf
## halber Höhe (0.90 / 0.40) — überlappt weder Joystick (links unten) noch Sprung/Aktionen
## (rechts unten) noch die Toolbar (links oben).
##
## Steuerkreuz (Richtungen relativ zur Kamera, Schritt = 1 Rasterzelle):
##     [ Höher ] [  ▲  ] [ Blick ]
##     [   ◀   ] [Status] [  ▶   ]
##     [ Tiefer ] [  ▼  ] [      ]

var container: HBoxContainer
var rotate_button: Button
var place_button: Button
var cancel_button: Button
var reason_label: Label
var forward_button: Button
var back_button: Button
var left_button: Button
var right_button: Button
var up_button: Button
var down_button: Button
var follow_button: Button
var status_label: Label
var level_button: Button
var level_label: Label
var _pad: GridContainer
var _root: Control

func _init(parent: CanvasLayer) -> void:
	_root = Control.new()
	_root.name = "BuildModeControls"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false

	reason_label = Label.new()
	reason_label.name = "BuildReason"
	reason_label.anchor_left   = 0.5
	reason_label.anchor_right  = 0.5
	reason_label.anchor_top    = 0.55
	reason_label.anchor_bottom = 0.55
	reason_label.offset_left   = -320
	reason_label.offset_right  = 320
	reason_label.offset_top    = -20
	reason_label.offset_bottom = 20
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.add_theme_font_size_override("font_size", 22)
	reason_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	reason_label.add_theme_constant_override("outline_size", 6)
	reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(reason_label)

	# Wasserwagen-Kennzahlen (nur sichtbar, solange der Wasserwagen an ist), unter der Hinweiszeile.
	level_label = Label.new()
	level_label.name = "BuildLevelGaugeLabel"
	level_label.anchor_left   = 0.5
	level_label.anchor_right  = 0.5
	level_label.anchor_top    = 0.55
	level_label.anchor_bottom = 0.55
	level_label.offset_left   = -320
	level_label.offset_right  = 320
	level_label.offset_top    = 22
	level_label.offset_bottom = 56
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	level_label.add_theme_constant_override("outline_size", 6)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.visible = false
	_root.add_child(level_label)

	container = HBoxContainer.new()
	container.name = "BuildButtons"
	container.anchor_left   = 0.5
	container.anchor_right  = 0.5
	container.anchor_top    = 0.62
	container.anchor_bottom = 0.62
	container.offset_left   = -170
	container.offset_right  = 170
	container.offset_top    = -52
	container.offset_bottom = 52
	container.add_theme_constant_override("separation", 14)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(container)

	rotate_button = _make_button("BuildRotateButton", "⟳")
	place_button  = _make_button("BuildPlaceButton", "✔")
	cancel_button = _make_button("BuildCancelButton", "✕")
	place_button.custom_minimum_size = Vector2(UIMetrics.TOOLBAR_BUTTON + 40, UIMetrics.TOOLBAR_BUTTON + 16)
	container.add_child(rotate_button)
	container.add_child(place_button)
	container.add_child(cancel_button)

	_build_pad()

	parent.add_child(_root)

func _build_pad() -> void:
	_pad = GridContainer.new()
	_pad.name = "BuildNudgePad"
	_pad.columns = 3
	_pad.anchor_left   = 0.90
	_pad.anchor_right  = 0.90
	_pad.anchor_top    = 0.40
	_pad.anchor_bottom = 0.40
	_pad.offset_left   = -132
	_pad.offset_right  = 132
	_pad.offset_top    = -132
	_pad.offset_bottom = 132
	_pad.add_theme_constant_override("h_separation", 8)
	_pad.add_theme_constant_override("v_separation", 8)
	_root.add_child(_pad)

	up_button      = _make_pad_button("BuildLevelUpButton", "Höher", 20)
	forward_button = _make_pad_button("BuildForwardButton", "▲", 34)
	follow_button  = _make_pad_button("BuildFollowButton", "Blick", 20)
	left_button    = _make_pad_button("BuildLeftButton", "◀", 34)
	status_label   = Label.new()
	status_label.name = "BuildStatus"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(PAD_BUTTON, PAD_BUTTON)
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	status_label.add_theme_constant_override("outline_size", 6)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_button   = _make_pad_button("BuildRightButton", "▶", 34)
	down_button    = _make_pad_button("BuildLevelDownButton", "Tiefer", 20)
	back_button    = _make_pad_button("BuildBackButton", "▼", 34)
	# Der freie Platz unten rechts im Kreuz: Wasserwagen-Schalter (zeigt Bodenunebenheit).
	level_button = _make_pad_button("BuildLevelGaugeButton", "Wasser-\nwagen", 18)
	level_button.toggle_mode = true

	for c: Control in [up_button, forward_button, follow_button, left_button, status_label,
			right_button, down_button, back_button, level_button]:
		_pad.add_child(c)

func set_active(active: bool) -> void:
	_root.visible = active

## Anzeige im Steuerkreuz: Ebene (0 = Boden) und Zielmodus (Blick folgt / Position fixiert).
func set_status(storey: int, locked: bool) -> void:
	status_label.text = "Ebene %d\n%s" % [storey, "fixiert" if locked else "Blick"]
	follow_button.disabled = not locked

func set_reason(text: String) -> void:
	reason_label.text = text

## Wasserwagen-Schalter synchronisieren (ohne das toggled-Signal auszulösen) und Text zeigen/leeren.
func set_level_on(on: bool) -> void:
	if level_button.button_pressed != on:
		level_button.set_pressed_no_signal(on)
	level_label.visible = on
	if not on:
		level_label.text = ""

func set_level_text(text: String) -> void:
	level_label.text = text

func set_place_enabled(enabled: bool) -> void:
	place_button.disabled = not enabled

const PAD_BUTTON: int = 80

func _make_pad_button(node_name: String, text: String, font_size: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(PAD_BUTTON, PAD_BUTTON)
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b

func _make_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(UIMetrics.TOOLBAR_BUTTON, UIMetrics.TOOLBAR_BUTTON + 16)
	b.add_theme_font_size_override("font_size", 34)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b
