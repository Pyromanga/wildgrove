extends CanvasLayer
## HUD.gd — Komplettes Interface

signal settings_requested

const JS_RADIUS: float = 90.0

var _js_base: ColorRect
var _js_knob: ColorRect
var _settings_btn: Button
var _feedback_label: Label # Für XP & Items
var _ui_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("hud")
    	_build_joystick()
        	_build_settings_button()
            	_build_feedback_ui()
                	_connect_touch_input()
                    	get_viewport().size_changed.connect(_on_viewport_resized)

                        func _build_joystick() -> void:
                        	_js_base = ColorRect.new()
                            	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
                                	_js_base.color = Color(1, 1, 1, 0.15)
                                    	_js_base.anchor_left = 0.0; _js_base.anchor_top = 1.0
                                        	_js_base.anchor_right = 0.0; _js_base.anchor_bottom = 1.0
                                            	add_child(_js_base)

                                                	_js_knob = ColorRect.new()
                                                    	_js_knob.size = Vector2(60, 60)
                                                        	_js_knob.color = Color(1, 1, 1, 0.8)
                                                            	add_child(_js_knob)
                                                                	_on_viewport_resized()

                                                                    func _build_settings_button() -> void:
                                                                    	_settings_btn = Button.new()
                                                                        	_settings_btn.text = "Settings"
                                                                            	_settings_btn.custom_minimum_size = Vector2(100, 50)
                                                                                	_settings_btn.anchor_left = 1.0; _settings_btn.anchor_top = 0.0
                                                                                    	_settings_btn.anchor_right = 1.0; _settings_btn.anchor_bottom = 0.0
                                                                                        	_settings_btn.pressed.connect(func(): settings_requested.emit())
                                                                                            	add_child(_settings_btn)

                                                                                                func _build_feedback_ui() -> void:
                                                                                                	_feedback_label = Label.new()
                                                                                                    	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                                                                                                        	_feedback_label.anchor_left = 0.5; _feedback_label.anchor_top = 0.8
                                                                                                            	_feedback_label.anchor_right = 0.5; _feedback_label.anchor_bottom = 0.8
                                                                                                                	_feedback_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
                                                                                                                    	_feedback_label.add_theme_font_size_override("font_size", 28)
                                                                                                                        	_feedback_label.add_theme_color_override("font_outline_color", Color.BLACK)
                                                                                                                            	_feedback_label.add_theme_constant_override("outline_size", 8)
                                                                                                                                	add_child(_feedback_label)

                                                                                                                                    func show_feedback(text: String) -> void:
                                                                                                                                    	_feedback_label.text = text
                                                                                                                                        	_feedback_label.modulate.a = 1.0
                                                                                                                                            	# Kleiner Effekt: Text blendet nach 2 Sekunden aus
                                                                                                                                                	var tween = create_tween()
                                                                                                                                                    	tween.tween_interval(1.5)
                                                                                                                                                        	tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.5)

                                                                                                                                                            func _connect_touch_input() -> void:
                                                                                                                                                            	await get_tree().process_frame
                                                                                                                                                                	var nodes = get_tree().get_nodes_in_group("touch_input")
                                                                                                                                                                    	if nodes.size() > 0:
                                                                                                                                                                        		nodes[0].register_joystick_visuals(_js_base, _js_knob)

                                                                                                                                                                                func _on_viewport_resized() -> void:
                                                                                                                                                                                	apply_ui_offset(_ui_offset)

                                                                                                                                                                                    func apply_ui_offset(offset: Vector2) -> void:
                                                                                                                                                                                    	_ui_offset = offset
                                                                                                                                                                                        	_js_base.offset_left = 40 + offset.x
                                                                                                                                                                                            	_js_base.offset_top = -(JS_RADIUS * 2 + 60) + offset.y
                                                                                                                                                                                                	_js_knob.global_position = _js_base.global_position + (Vector2(JS_RADIUS, JS_RADIUS) - Vector2(30, 30))
                                                                                                                                                                                                    	_settings_btn.offset_left = -150 + offset.x
                                                                                                                                                                                                        	_settings_btn.offset_top = 40 + offset.y