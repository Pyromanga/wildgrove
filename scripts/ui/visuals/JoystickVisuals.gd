class_name JoystickVisuals

## JoystickVisuals — Joystick-Basis und Knob als ColorRects.
##
## FIX: Farben waren nicht gesetzt → weiße ColorRects auf weißem/transparentem
## Hintergrund → unsichtbar. Jetzt explizit gesetzt mit Transparenz.
## Außerdem: pivot_offset auf Mitte gesetzt damit die Positionierung korrekt ist.
##
## FEATURE (fixed_joystick): im festen Modus zeigt set_idle_anchor() die Basis
## permanent gedimmt an der konfigurierten Stelle — Orientierungshilfe, damit
## der Spieler weiß, wo er den Daumen aufsetzen muss, ohne dass die Basis erst
## bei Berührung "aus dem Nichts" erscheint. Bei aktiver Berührung (set_visible)
## wird sie auf volle Deckkraft gebracht und der Knob eingeblendet.

const IDLE_ALPHA: float = 0.22
const ACTIVE_ALPHA: float = 0.45

var base: ColorRect
var knob: ColorRect

## true zwischen set_visible(true) und set_visible(false) — verhindert, dass
## set_idle_anchor(..., false) eine gerade aktive Berührung wegblendet.
var _touch_active: bool = false

func _init(parent: CanvasLayer) -> void:
	base = ColorRect.new()
	base.name = "JoystickBase"
	base.custom_minimum_size = Vector2(180, 180)
	base.size = Vector2(180, 180)
	# Sichtbare Farbe: dunkles Grau, halbtransparent
	base.color = Color(0.1, 0.1, 0.1, ACTIVE_ALPHA)
	base.visible = false
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(base)

	knob = ColorRect.new()
	knob.name = "JoystickKnob"
	knob.custom_minimum_size = Vector2(60, 60)
	knob.size = Vector2(60, 60)
	# Heller als die Basis
	knob.color = Color(0.8, 0.8, 0.8, 0.75)
	knob.visible = false
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(knob)

## Aktive Berührung — volle Deckkraft, Knob sichtbar. Wird bei Loslassen
## wieder auf false gesetzt (aufrufende Seite: JoystickController).
func set_visible(val: bool) -> void:
	_touch_active = val
	base.visible = val
	knob.visible = val
	if val:
		base.color.a = ACTIVE_ALPHA

## Zeigt die Basis gedimmt an `pos` (Viewport-Koordinaten), auch ohne aktive
## Berührung — nur relevant im fixed_joystick-Modus (enabled == true).
## enabled == false (schwebender Modus): Idle-Anzeige aus, Basis bleibt
## unsichtbar bis zur nächsten echten Berührung (set_visible(true)).
## Überschreibt eine aktive Berührung NICHT (siehe _touch_active-Guard).
func set_idle_anchor(pos: Vector2, enabled: bool) -> void:
	if _touch_active:
		return
	if not enabled:
		base.visible = false
		return
	base.position = pos - (base.size / 2)
	base.color.a = IDLE_ALPHA
	base.visible = true
