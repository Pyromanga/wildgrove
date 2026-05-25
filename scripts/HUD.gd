extends CanvasLayer
## HUD.gd — Joystick-Visuals, Settings-Button, Feedback

signal settings_requested

const JS_RADIUS: float = 90.0

var _js_base: ColorRect
var _js_knob: ColorRect
var _settings_btn: Button
var _ui_offset: Vector2 = Vector2.ZERO

# Feedback-Label
var _feedback_label: Label
var _feedback_timer: SceneTreeTimer


func _ready() -> void:
	add_to_group("hud")   # NEU: Gruppe für Feedback
    	_build_joystick()
        	_build_settings_button()
            	_build_feedback_label()
                	_connect_touch_input()
                    	get_viewport().size_changed.connect(_on_viewport_resized)


                        func _build_joystick() -> void:
                        	_js_base = ColorRect.new()
                            	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
                                	_js_base.color = Color(1, 1, 1, 0.15)
                                    	_js_base.anchor_left   = 0.0
                                        	_js_base.anchor_right  = 0.0
                                            	_js_base.anchor_top    = 1.0
                                                	_js_base.anchor_bottom = 1.0
                                                    	_js_base.offset_left   = 40
                                                        	_js_base.offset_right  = 40 + JS_RADIUS * 2
                                                            	_js_base.offset_top    = -(JS_RADIUS * 2 + 60)
                                                                	_js_base.offset_bottom = -60
                                                                    	add_child(_js_base)

                                                                        	_js_knob = ColorRect.new()
                                                                            	_js_knob.size = Vector2(60, 60)
                                                                                	_js_knob.color = Color(1, 1, 1, 0.8)
                                                                                    	_js_knob.anchor_left   = 0.0
                                                                                        	_js_knob.anchor_right  = 0.0
                                                                                            	_js_knob.anchor_top    = 1.0
                                                                                                	_js_knob.anchor_bottom = 1.0
                                                                                                    	_js_knob.offset_left   = 40 + JS_RADIUS - 30
                                                                                                        	_js_knob.offset_right  = 40 + JS_RADIUS + 30
                                                                                                            	_js_knob.offset_top    = -(JS_RADIUS + 60)
                                                                                                                	_js_knob.offset_bottom = -(JS_RADIUS + 60) + 60
                                                                                                                    	add_child(_js_knob)


                                                                                                                        func _build_settings_button() -> void:
                                                                                                                        	_settings_btn = Button.new()
                                                                                                                            	_settings_btn.text = "⚙"
                                                                                                                                	_settings_btn.custom_minimum_size = Vector2(90, 90)
                                                                                                                                    	_settings_btn.anchor_left   = 1.0
                                                                                                                                        	_settings_btn.anchor_right  = 1.0
                                                                                                                                            	_settings_btn.anchor_top    = 0.0
                                                                                                                                                	_settings_btn.anchor_bottom = 0.0
                                                                                                                                                    	_settings_btn.offset_left   = -110
                                                                                                                                                        	_settings_btn.offset_right  = -20
                                                                                                                                                            	_settings_btn.offset_top    = 40
                                                                                                                                                                	_settings_btn.offset_bottom = 130
                                                                                                                                                                    	_settings_btn.add_theme_font_size_override("font_size", 44)
                                                                                                                                                                        	_settings_btn.pressed.connect(func() -> void: emit_signal("settings_requested"))
                                                                                                                                                                            	add_child(_settings_btn)


                                                                                                                                                                                func _build_feedback_label() -> void:
                                                                                                                                                                                	_feedback_label = Label.new()
                                                                                                                                                                                    	_feedback_label.add_theme_font_size_override("font_size", 32)
                                                                                                                                                                                        	_feedback_label.add_theme_color_override("font_color", Color.WHITE)
                                                                                                                                                                                            	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                                                                                                                                                                                                	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
                                                                                                                                                                                                    	_feedback_label.anchor_left = 0.5
                                                                                                                                                                                                        	_feedback_label.anchor_right = 0.5
                                                                                                                                                                                                            	_feedback_label.anchor_top = 0.0
                                                                                                                                                                                                                	_feedback_label.anchor_bottom = 0.0
                                                                                                                                                                                                                    	_feedback_label.offset_left = -200
                                                                                                                                                                                                                        	_feedback_label.offset_right = 200
                                                                                                                                                                                                                            	_feedback_label.offset_top = 200
                                                                                                                                                                                                                                	_feedback_label.offset_bottom = 260
                                                                                                                                                                                                                                    	_feedback_label.visible = false
                                                                                                                                                                                                                                        	add_child(_feedback_label)


                                                                                                                                                                                                                                            func _connect_touch_input() -> void:
                                                                                                                                                                                                                                            	var nodes: Array = get_tree().get_nodes_in_group("touch_input")
                                                                                                                                                                                                                                                	if nodes.size() > 0:
                                                                                                                                                                                                                                                    		nodes[0].register_joystick_visuals(_js_base, _js_knob)


                                                                                                                                                                                                                                                            func _on_viewport_resized() -> void:
                                                                                                                                                                                                                                                            	apply_ui_offset(_ui_offset)


                                                                                                                                                                                                                                                                func apply_ui_offset(offset: Vector2) -> void:
                                                                                                                                                                                                                                                                	_ui_offset = offset

                                                                                                                                                                                                                                                                    	_js_base.offset_left   = 40 + offset.x
                                                                                                                                                                                                                                                                        	_js_base.offset_right  = 40 + JS_RADIUS * 2 + offset.x
                                                                                                                                                                                                                                                                            	_js_base.offset_top    = -(JS_RADIUS * 2 + 60) + offset.y
                                                                                                                                                                                                                                                                                	_js_base.offset_bottom = -60 + offset.y

                                                                                                                                                                                                                                                                                    	_js_knob.offset_left   = 40 + JS_RADIUS - 30 + offset.x
                                                                                                                                                                                                                                                                                        	_js_knob.offset_right  = 40 + JS_RADIUS + 30 + offset.x
                                                                                                                                                                                                                                                                                            	_js_knob.offset_top    = -(JS_RADIUS + 60) + offset.y
                                                                                                                                                                                                                                                                                                	_js_knob.offset_bottom = -(JS_RADIUS + 60) + 60 + offset.y

                                                                                                                                                                                                                                                                                                    	_settings_btn.offset_left   = -110 + offset.x
                                                                                                                                                                                                                                                                                                        	_settings_btn.offset_right  = -20  + offset.x
                                                                                                                                                                                                                                                                                                            	_settings_btn.offset_top    = 40   + offset.y
                                                                                                                                                                                                                                                                                                                	_settings_btn.offset_bottom = 130  + offset.y


                                                                                                                                                                                                                                                                                                                    # NEU: Feedback anzeigen und nach 2s ausblenden
                                                                                                                                                                                                                                                                                                                    func show_feedback(text: String) -> void:
                                                                                                                                                                                                                                                                                                                    	if not _feedback_label:
                                                                                                                                                                                                                                                                                                                        		return
                                                                                                                                                                                                                                                                                                                                	_feedback_label.text = text
                                                                                                                                                                                                                                                                                                                                    	_feedback_label.visible = true
                                                                                                                                                                                                                                                                                                                                        	# Timer ggf. abbrechen
                                                                                                                                                                                                                                                                                                                                            	if _feedback_timer:
                                                                                                                                                                                                                                                                                                                                                		_feedback_timer.timeout.disconnect(_hide_feedback)
                                                                                                                                                                                                                                                                                                                                                        	_feedback_timer = get_tree().create_timer(2.0)
                                                                                                                                                                                                                                                                                                                                                            	_feedback_timer.timeout.connect(_hide_feedback)


                                                                                                                                                                                                                                                                                                                                                                func _hide_feedback() -> void:
                                                                                                                                                                                                                                                                                                                                                                	if _feedback_label:
                                                                                                                                                                                                                                                                                                                                                                    		_feedback_label.visible = false