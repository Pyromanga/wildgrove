class_name PetHeadIcon
extends Control

## PetHeadIcon — kleines 2D-Kopfbild eines Pets fürs Pet-Menü-Grid.
##
## Zeichnet per _draw() einen stilisierten Kopf aus denselben Feldern, aus denen
## AnimalVisualBuilder das 3D-Modell baut (Farbe, Ohren-, Schnauzen-, Kopfschmuck-
## Stil, siehe AnimalVisualProfile) — kein SubViewport/3D-Render pro Kachel, das
## wäre bei vielen Pets auf dem Handy unnötig teuer. Das Icon ist rein
## kosmetisch und zustandslos: set_appearance() setzt die Felder neu und löst
## ein Neuzeichnen aus.
##
## mouse_filter = IGNORE: Taps gehen an die umgebende Kachel (Button) durch.

var _color:          Color = Color(0.7, 0.5, 0.3)
var _ear_style:      int   = AnimalVisualProfile.EarStyle.ROUND
var _snout_style:    int   = AnimalVisualProfile.SnoutStyle.SHORT
var _headgear_style: int   = AnimalVisualProfile.HeadgearStyle.NONE

## Bequemer Konstruktor: appearance = PetComponent.get_appearance(), px =
## Mindestkantenlänge in Pixeln.
static func create(appearance: Dictionary, px: float) -> PetHeadIcon:
	var icon := PetHeadIcon.new()
	icon.custom_minimum_size = Vector2(px, px)
	icon.set_appearance(appearance)
	return icon

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_appearance(appearance: Dictionary) -> void:
	var col: Variant = appearance.get("color", _color)
	_color          = col if col is Color else _color
	_ear_style      = int(appearance.get("ear_style", _ear_style))
	_snout_style    = int(appearance.get("snout_style", _snout_style))
	_headgear_style = int(appearance.get("headgear_style", _headgear_style))
	queue_redraw()

func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 1.0:
		return
	var center: Vector2 = size * 0.5
	var r: float = s * 0.30
	var head: Vector2 = center + Vector2(0.0, s * 0.06)
	var dark: Color = _color.darkened(0.35)
	var light: Color = _color.lightened(0.35)

	# Dezente Scheibe hinter dem Kopf — hebt ihn von der Kachel ab.
	draw_circle(center, s * 0.48, Color(1, 1, 1, 0.05))

	for side in 2:
		var sx: float = -1.0 if side == 0 else 1.0
		_draw_headgear_back(head, r, s, sx)
		_draw_ear(head, r, sx, dark)

	draw_circle(head, r, _color)
	_draw_snout(head, r, light, dark)

	for side in 2:
		var sx2: float = -1.0 if side == 0 else 1.0
		_draw_headgear_front(head, r, sx2)
		var eye: Vector2 = head + Vector2(sx2 * r * 0.38, -r * 0.12)
		draw_circle(eye, r * 0.11, Color(0.08, 0.08, 0.1))
		draw_circle(eye + Vector2(-r * 0.03, -r * 0.03), r * 0.04, Color(1, 1, 1, 0.8))

func _draw_ear(head: Vector2, r: float, sx: float, dark: Color) -> void:
	match _ear_style:
		AnimalVisualProfile.EarStyle.ROUND:
			var p: Vector2 = head + Vector2(sx * r * 0.75, -r * 0.8)
			draw_circle(p, r * 0.38, _color)
			draw_circle(p, r * 0.2, dark)
		AnimalVisualProfile.EarStyle.POINTY:
			var tri := PackedVector2Array([
				head + Vector2(sx * r * 0.30, -r * 0.70),
				head + Vector2(sx * r * 0.95, -r * 0.55),
				head + Vector2(sx * r * 0.62, -r * 1.45),
			])
			draw_colored_polygon(tri, _color)
		AnimalVisualProfile.EarStyle.LONG:
			_draw_ellipse(head + Vector2(sx * r * 0.42, -r * 1.35), Vector2(r * 0.2, r * 0.8), _color)
		AnimalVisualProfile.EarStyle.FLOPPY:
			_draw_ellipse(head + Vector2(sx * r * 1.0, -r * 0.1), Vector2(r * 0.28, r * 0.62), dark)
		_:
			pass

func _draw_snout(head: Vector2, r: float, light: Color, dark: Color) -> void:
	match _snout_style:
		AnimalVisualProfile.SnoutStyle.SHORT:
			_draw_ellipse(head + Vector2(0.0, r * 0.42), Vector2(r * 0.45, r * 0.32), light)
			draw_circle(head + Vector2(0.0, r * 0.35), r * 0.12, dark)
		AnimalVisualProfile.SnoutStyle.LONG:
			_draw_ellipse(head + Vector2(0.0, r * 0.6), Vector2(r * 0.5, r * 0.5), light)
			draw_circle(head + Vector2(0.0, r * 0.62), r * 0.14, dark)
		_:
			pass

## Geweih (hinter dem Kopf gezeichnet, damit es "aus" dem Kopf wächst).
func _draw_headgear_back(head: Vector2, r: float, s: float, sx: float) -> void:
	var w: float = maxf(2.0, s * 0.035)
	var base: Vector2 = head + Vector2(sx * r * 0.55, -r * 0.75)
	match _headgear_style:
		AnimalVisualProfile.HeadgearStyle.ANTLERS:
			var col := Color(0.82, 0.72, 0.55)
			var tip: Vector2 = base + Vector2(sx * r * 0.25, -r * 0.9)
			draw_line(base, tip, col, w)
			draw_line(base + Vector2(sx * r * 0.12, -r * 0.45), base + Vector2(sx * r * 0.55, -r * 0.65), col, w)
			draw_line(tip, tip + Vector2(sx * r * 0.25, -r * 0.3), col, w)
		AnimalVisualProfile.HeadgearStyle.HORNS:
			# Zwei Striche: Wurzel nach oben/außen, Spitze leicht nach innen gebogen.
			var horn_col := Color(0.85, 0.80, 0.66)
			var mid: Vector2 = base + Vector2(sx * r * 0.22, -r * 0.65)
			draw_line(base, mid, horn_col, w * 1.4)
			draw_line(mid, mid + Vector2(-sx * r * 0.10, -r * 0.40), horn_col, w)
		AnimalVisualProfile.HeadgearStyle.BROAD_ANTLERS:
			# Schaufel: ein flaches Viereck seitlich vom Kopf (Elch).
			var palm_col := Color(0.62, 0.52, 0.38)
			var palm := PackedVector2Array([
				base,
				base + Vector2(sx * r * 0.80, -r * 0.10),
				base + Vector2(sx * r * 0.90, -r * 0.70),
				base + Vector2(sx * r * 0.35, -r * 0.85),
			])
			draw_colored_polygon(palm, palm_col)
		_:
			pass

## Hauer (vor dem Kopf, an der Schnauze).
func _draw_headgear_front(head: Vector2, r: float, sx: float) -> void:
	if _headgear_style != AnimalVisualProfile.HeadgearStyle.TUSKS:
		return
	var tusk := PackedVector2Array([
		head + Vector2(sx * r * 0.22, r * 0.62),
		head + Vector2(sx * r * 0.5, r * 0.62),
		head + Vector2(sx * r * 0.38, r * 0.15),
	])
	draw_colored_polygon(tusk, Color(0.95, 0.93, 0.85))

func _draw_ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 20
	for i in steps:
		var a: float = TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)
