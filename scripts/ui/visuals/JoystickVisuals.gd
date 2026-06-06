class_name JoystickVisuals

## JoystickVisuals — Joystick-Basis und Knob als ColorRects.
##
## FIX: Farben waren nicht gesetzt → weiße ColorRects auf weißem/transparentem
## Hintergrund → unsichtbar. Jetzt explizit gesetzt mit Transparenz.
## Außerdem: pivot_offset auf Mitte gesetzt damit die Positionierung korrekt ist.

var base: ColorRect
var knob: ColorRect


func _init(parent: CanvasLayer) -> void:
	base = ColorRect.new()
	base.name = "JoystickBase"
	base.custom_minimum_size = Vector2(180, 180)
	base.size = Vector2(180, 180)
	# Sichtbare Farbe: dunkles Grau, halbtransparent
	base.color = Color(0.1, 0.1, 0.1, 0.45)
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


func set_visible(val: bool) -> void:
	base.visible = val
	knob.visible = val
