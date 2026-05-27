extends Node

# Design-Konstanten für ein einheitliches Look & Feel
const COLOR_BG = Color(0, 0, 0, 0.6)
const COLOR_ACCENT = Color(0.2, 0.8, 0.3) # Mining-Grün

## 1. Haupt-HUD erstellen (wird von Main.gd aufgerufen)

func create_hud() -> CanvasLayer:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	canvas.add_to_group("hud")
	
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 50)
	canvas.add_child(margin)
	
	var v_box := VBoxContainer.new()
	v_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(v_box)
	
	# XP-Bar als erstes HUD-Element
	var xp_bar = create_progress_bar()
	v_box.add_child(xp_bar)
	
	return canvas

## 2. Fortschrittsbalken-Fabrik
func create_progress_bar(width: float = 250.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 24)
	bar.show_percentage = false
	
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = COLOR_BG
	sb_bg.set_corner_radius_all(4)
	
	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = COLOR_ACCENT
	sb_fg.set_corner_radius_all(4)
	
	bar.add_theme_stylebox_override("background", sb_bg)
	bar.add_theme_stylebox_override("fill", sb_fg)
	
	return bar

## 3. Beschriftungs-Fabrik (z.B. für Objektnamen)
func create_label_box(text: String) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BG
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	pc.add_theme_stylebox_override("panel", sb)
	
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	pc.add_child(lbl)
	
	return pc

## 4. Hilfs-Button Fabrik (für Menüs)
func create_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 40)
	btn.pressed.connect(callback)
	return btn

func create_joystick_visuals() -> Array:
    var base := ColorRect.new()
    base.custom_minimum_size = Vector2(180, 180) # 2 * JS_RADIUS
    base.color = Color(1, 1, 1, 0.2)
    base.set_deferred("visible", false) # Erst bei Touch sichtbar machen
    
    var knob := ColorRect.new()
    knob.custom_minimum_size = Vector2(60, 60)
    knob.color = Color(1, 1, 1, 0.8)
    
    return [base, knob]