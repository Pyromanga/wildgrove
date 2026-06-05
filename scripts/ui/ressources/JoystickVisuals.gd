class_name JoystickVisuals

var base: ColorRect
var knob: ColorRect


func _init(parent: CanvasLayer) -> void:
	base = ColorRect.new()
	base.custom_minimum_size = Vector2(180, 180)
	base.visible = false
	parent.add_child(base)

	knob = ColorRect.new()
	knob.custom_minimum_size = Vector2(60, 60)
	knob.visible = false
	parent.add_child(knob)


func set_visible(val: bool) -> void:
	base.visible = val
	knob.visible = val
