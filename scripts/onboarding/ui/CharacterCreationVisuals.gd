class_name CharacterCreationVisuals

## CharacterCreationVisuals — reine Darstellung, keine Logik.
## Programmatisch gebaut (kein .tscn), exakt dasselbe Muster wie
## AchievementPanelVisuals/SkillPanelVisuals/QuestPanelVisuals.
##
## Anders als die übrigen HUD-Panels: kein Toggle-Button, kein Ein-/
## Ausblenden per Klick — dieses Overlay wird vom Controller genau einmal
## pro neuem Spielstand gezeigt (`has_seen_creation()`) und blockiert
## bewusst großflächig den Bildschirm (Vollbild-abgedunkelter Hintergrund),
## damit es sich wie ein Onboarding-Schritt anfühlt, nicht wie ein
## optionales Panel.

signal option_selected(option_id: String)
signal skip_pressed()

var panel: PanelContainer
var _backdrop: ColorRect
var _progress_label: Label
var _question_label: Label
var _options_vbox: VBoxContainer

func _init(parent: CanvasLayer) -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "CharacterCreationBackdrop"
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	_backdrop.anchor_left = 0.0
	_backdrop.anchor_top = 0.0
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	parent.add_child(_backdrop)

	panel = PanelContainer.new()
	panel.name = "CharacterCreationPanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 520)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 14)
	panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "Wer bist du?"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var skip_button := Button.new()
	skip_button.text = "Überspringen"
	skip_button.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	header.add_child(skip_button)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.modulate = Color(1, 1, 1, 0.6)
	outer_vbox.add_child(_progress_label)

	_question_label = Label.new()
	_question_label.add_theme_font_size_override("font_size", 17)
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer_vbox.add_child(_question_label)

	_options_vbox = VBoxContainer.new()
	_options_vbox.add_theme_constant_override("separation", 8)
	outer_vbox.add_child(_options_vbox)

	parent.add_child(panel)
	# sticky: Wizard wird nie von einem anderen Fenster weggeschaltet (Backdrop bliebe sonst stehen).
	PanelDock.register_in(parent, &"character_creation", panel, PanelDock.Kind.MODAL, null, true)

## question: ein Eintrag aus CharacterCreationService.QUESTIONS
## (Dictionary mit "text"/"options"). index/total sind 0-basiert bzw. die
## Gesamtzahl, nur für die Fortschrittsanzeige.
func render_question(question: Dictionary, index: int, total: int) -> void:
	_progress_label.text = "Frage %d / %d" % [index + 1, total]
	_question_label.text = String(question.get("text", ""))

	for child in _options_vbox.get_children():
		child.queue_free()

	for option in (question.get("options", []) as Array):
		var opt: Dictionary = option
		var option_id: String = String(opt.get("id", ""))
		var btn := Button.new()
		btn.text = String(opt.get("label", option_id))
		btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
		btn.pressed.connect(func() -> void: option_selected.emit(option_id))
		_options_vbox.add_child(btn)

func show_panel() -> void:
	_backdrop.visible = true
	panel.visible = true

func hide_panel() -> void:
	_backdrop.visible = false
	panel.visible = false
