extends Node
## UIFactory.gd — Erschafft UI-Elemente direkt per Script

# Standard-Farben für dein Interface
const COLOR_BG = Color(0, 0, 0, 0.4)
const COLOR_PROGRESS = Color(0.2, 0.8, 0.3) # Grün

func create_ui_pos(x: float, y: float) -> Vector2:
	return Vector2(x, y)

func create_world_pos(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)

## Erstellt einen Fortschrittsbalken für Interaktionen (z.B. Hacken)
func create_progress_bar(width: float = 200.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 20)
	bar.show_percentage = false
	
	# Styling per Script (ohne .tres Dateien)
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = COLOR_BG
	sb_bg.set_corner_radius_all(4)
	
	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = COLOR_PROGRESS
	sb_fg.set_corner_radius_all(4)
	
	bar.add_theme_stylebox_override("background", sb_bg)
	bar.add_theme_stylebox_override("fill", sb_fg)
	
	return bar

## Erstellt ein einfaches Label mit Hintergrund (für Item-Popups oder Namen)
func create_label_box(text: String) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(lbl)
	
	return pc