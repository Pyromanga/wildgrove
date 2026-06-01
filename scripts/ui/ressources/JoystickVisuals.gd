class_name JoystickVisuals

var base: ColorRect
var knob: ColorRect

func _init(parent: CanvasLayer) -> void:
    base = ColorRect.new()
    # ... style das ...
    parent.add_child(base)
    
    knob = ColorRect.new()
    # ... style das ...
    parent.add_child(knob)