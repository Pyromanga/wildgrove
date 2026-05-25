extends Node

# ── Nodes ──────────────────────────────────────────────────────────────────
var _player: CharacterBody3D
var _spring_arm: SpringArm3D
var _log_label: Label
var _log_lines: Array[String] = []
var _js_base: ColorRect
var _js_knob: ColorRect
var _settings_panel: Control

# ── Touch State ────────────────────────────────────────────────────────────
var _js_finger: int = -1
var _js_origin: Vector2 = Vector2.ZERO
var _js_vec: Vector2 = Vector2.ZERO
const JS_RADIUS: float = 90.0

var _cam_finger: int = -1
var _cam_last: Vector2 = Vector2.ZERO

# Pinch-Zoom
var _pinch_finger_a: int = -1
var _pinch_finger_b: int = -1
var _pinch_pos_a: Vector2 = Vector2.ZERO
var _pinch_pos_b: Vector2 = Vector2.ZERO
var _pinch_last_dist: float = 0.0
const ZOOM_MIN: float = 3.0
const ZOOM_MAX: float = 16.0

# ── Settings ───────────────────────────────────────────────────────────────
var _cam_relative: bool = true   # Bewegung relativ zur Kamera?

# ── Physics ────────────────────────────────────────────────────────────────
const SPEED: float = 5.5
const GRAVITY: float = 9.8


# ══════════════════════════════════════════════════════════════════════════
func _log(msg: String) -> void:
	print(msg)
	_log_lines.append(msg)
	if _log_lines.size() > 10:
		_log_lines.remove_at(0)
	if _log_label:
		_log_label.text = "\n".join(_log_lines)


func _ready() -> void:
	_build_screen_log()
	_log("=== WildGrove START ===")
	_build_world()
	_log("Welt OK")
	_build_player()
	_log("Spieler OK")
	call_deferred("_build_hud")


# ══════════════════════════════════════════════════════════════════════════
#  SCREEN LOG
# ══════════════════════════════════════════════════════════════════════════
func _build_screen_log() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.size = Vector2(1080, 300)
	cl.add_child(bg)
	_log_label = Label.new()
	_log_label.position = Vector2(10, 8)
	_log_label.size = Vector2(1060, 290)
	_log_label.add_theme_font_size_override("font_size", 22)
	_log_label.add_theme_color_override("font_color", Color.GREEN)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cl.add_child(_log_label)


# ══════════════════════════════════════════════════════════════════════════
#  WELT
# ══════════════════════════════════════════════════════════════════════════
func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.6, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.8
	env_node.environment = env
	add_child(env_node)

	var gb := StaticBody3D.new()
	var gc := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 0.2, 200)
	gc.shape = bs
	gb.position.y = -0.1
	gb.add_child(gc)
	add_child(gb)

	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	gm.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.25, 0.6, 0.2)
	gm.material_override = gmat
	add_child(gm)

	var props: Array[Vector3] = [
		Vector3(5,1,5), Vector3(-6,1,4), Vector3(8,1,-5),
		Vector3(-4,1,-8), Vector3(3,1,-3)
	]
	for pos in props:
		var b := StaticBody3D.new()
		var bc := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.5, 2, 1.5)
		bc.shape = bx
		b.add_child(bc)
		var bm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.5, 2, 1.5)
		bm.mesh = box
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.15, 0.4, 0.1)
		bm.material_override = bmat
		b.add_child(bm)
		b.position = pos
		add_child(b)


# ══════════════════════════════════════════════════════════════════════════
#  SPIELER
# ══════════════════════════════════════════════════════════════════════════
func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.add_to_group("player")

	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.4
	caps.height = 1.0
	col.shape = caps
	col.position.y = 0.9
	_player.add_child(col)

	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	mi.mesh = cm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.6, 0.05)
	mi.material_override = pmat
	mi.position.y = 0.9
	_player.add_child(mi)

	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 8.0
	_spring_arm.position = Vector3(0, 1.5, 0)
	_spring_arm.rotation_degrees.x = -35.0
	_player.add_child(_spring_arm)

	var cam := Camera3D.new()
	cam.current = true
	_spring_arm.add_child(cam)

	_player.position = Vector3(0, 0.9, 0)
	add_child(_player)


# ══════════════════════════════════════════════════════════════════════════
#  HUD + SETTINGS
# ══════════════════════════════════════════════════════════════════════════
func _build_hud() -> void:
	_log("HUD START")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_log("VP: " + str(vp))

	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	# ── Joystick ────────────────────────────────────────────────────────
	_js_base = ColorRect.new()
	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
	_js_base.color = Color(1, 1, 1, 0.15)
	_js_base.position = Vector2(30, vp.y - JS_RADIUS * 2 - 30)
	hud.add_child(_js_base)

	_js_knob = ColorRect.new()
	_js_knob.size = Vector2(60, 60)
	_js_knob.color = Color(1, 1, 1, 0.8)
	_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
	hud.add_child(_js_knob)

	# ── Settings Button (Zahnrad-Text) ───────────────────────────────────
	var settings_btn := _make_button("⚙", Vector2(vp.x - 90, 20), Vector2(70, 70))
	settings_btn.pressed.connect(_toggle_settings)
	hud.add_child(settings_btn)

	# ── Settings Panel ───────────────────────────────────────────────────
	_settings_panel = _build_settings_panel(vp, hud)
	_settings_panel.visible = false

	_log("HUD DONE")


func _make_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = size
	btn.add_theme_font_size_override("font_size", 36)
	return btn


func _build_settings_panel(vp: Vector2, hud: CanvasLayer) -> Control:
	# Hintergrund
	var panel := ColorRect.new()
	panel.color = Color(0.1, 0.1, 0.1, 0.92)
	panel.size = Vector2(600, 400)
	panel.position = Vector2(vp.x * 0.5 - 300, vp.y * 0.5 - 200)
	hud.add_child(panel)

	# Titel
	var title := Label.new()
	title.text = "Einstellungen"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(20, 16)
	panel.add_child(title)

	# Trennlinie
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.2)
	line.size = Vector2(560, 2)
	line.position = Vector2(20, 62)
	panel.add_child(line)

	# ── Option: Kamera-relative Bewegung ────────────────────────────────
	var lbl1 := Label.new()
	lbl1.text = "Bewegung relativ zur Kamera"
	lbl1.add_theme_font_size_override("font_size", 28)
	lbl1.add_theme_color_override("font_color", Color.WHITE)
	lbl1.position = Vector2(20, 90)
	panel.add_child(lbl1)

	var sub1 := Label.new()
	sub1.text = "EIN: Joystick hoch = Blickrichtung\nAUS: Joystick hoch = immer Norden"
	sub1.add_theme_font_size_override("font_size", 20)
	sub1.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	sub1.position = Vector2(20, 126)
	panel.add_child(sub1)

	var toggle_cam := _make_toggle_btn(_cam_relative, Vector2(20, 190))
	toggle_cam.pressed.connect(func() -> void:
		_cam_relative = not _cam_relative
		toggle_cam.text = "● EIN" if _cam_relative else "○ AUS"
		_log("Kamera-relativ: " + str(_cam_relative))
	)
	panel.add_child(toggle_cam)

	# Trennlinie 2
	var line2 := ColorRect.new()
	line2.color = Color(1, 1, 1, 0.15)
	line2.size = Vector2(560, 2)
	line2.position = Vector2(20, 250)
	panel.add_child(line2)

	# ── Info: Zoom ───────────────────────────────────────────────────────
	var lbl2 := Label.new()
	lbl2.text = "Zoom"
	lbl2.add_theme_font_size_override("font_size", 28)
	lbl2.add_theme_color_override("font_color", Color.WHITE)
	lbl2.position = Vector2(20, 265)
	panel.add_child(lbl2)

	var sub2 := Label.new()
	sub2.text = "Zwei Finger zusammen/auseinander ziehen"
	sub2.add_theme_font_size_override("font_size", 20)
	sub2.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	sub2.position = Vector2(20, 302)
	panel.add_child(sub2)

	# Schließen
	var close_btn := _make_button("✕ Schließen", Vector2(160, 345), Vector2(280, 50))
	close_btn.pressed.connect(_toggle_settings)
	panel.add_child(close_btn)

	return panel


func _make_toggle_btn(initial: bool, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = "● EIN" if initial else "○ AUS"
	btn.position = pos
	btn.size = Vector2(160, 50)
	btn.add_theme_font_size_override("font_size", 26)
	return btn


func _toggle_settings() -> void:
	if _settings_panel:
		_settings_panel.visible = not _settings_panel.visible


# ══════════════════════════════════════════════════════════════════════════
#  INPUT
# ══════════════════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if not _js_base or not _spring_arm:
		return
	var sw: float = get_viewport().get_visible_rect().size.x

	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			# Pinch: zweiter Finger
			if _pinch_finger_a >= 0 and _pinch_finger_b < 0 and event.index != _pinch_finger_a:
				_pinch_finger_b = event.index
				_pinch_pos_b = pos
				_pinch_last_dist = _pinch_pos_a.distance_to(_pinch_pos_b)
			elif _pinch_finger_a < 0:
				if pos.x < sw * 0.5:
					if _js_finger < 0:
						_js_finger = event.index
						_pinch_finger_a = event.index
						_pinch_pos_a = pos
						_js_origin = pos
						_js_base.position = pos - Vector2(JS_RADIUS, JS_RADIUS)
						_js_knob.position = pos - Vector2(30, 30)
				else:
					if _cam_finger < 0:
						_cam_finger = event.index
						_pinch_finger_a = event.index
						_pinch_pos_a = pos
						_cam_last = pos
		else:
			if event.index == _js_finger:
				_js_finger = -1
				_js_vec = Vector2.ZERO
				_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
			if event.index == _cam_finger:
				_cam_finger = -1
			if event.index == _pinch_finger_a:
				_pinch_finger_a = -1
				_pinch_last_dist = 0.0
			if event.index == _pinch_finger_b:
				_pinch_finger_b = -1
				_pinch_last_dist = 0.0

	elif event is InputEventScreenDrag:
		# Pinch-Zoom
		if event.index == _pinch_finger_a:
			_pinch_pos_a = event.position
		elif event.index == _pinch_finger_b:
			_pinch_pos_b = event.position

		if _pinch_finger_a >= 0 and _pinch_finger_b >= 0:
			var new_dist: float = _pinch_pos_a.distance_to(_pinch_pos_b)
			if _pinch_last_dist > 0.0:
				var diff: float = _pinch_last_dist - new_dist
				_spring_arm.spring_length = clamp(
					_spring_arm.spring_length + diff * 0.02,
					ZOOM_MIN, ZOOM_MAX
				)
			_pinch_last_dist = new_dist
			return  # Kein Joystick/Kamera während Pinch

		if event.index == _js_finger:
			var delta: Vector2 = event.position - _js_origin
			var clamped: Vector2 = delta.limit_length(JS_RADIUS)
			_js_vec = clamped / JS_RADIUS
			_js_knob.position = _js_origin + clamped - Vector2(30, 30)
		elif event.index == _cam_finger:
			var d: Vector2 = event.position - _cam_last
			_cam_last = event.position
			_spring_arm.rotation.y -= d.x * 0.007
			_spring_arm.rotation.x = clamp(
				_spring_arm.rotation.x - d.y * 0.007,
				deg_to_rad(-65), deg_to_rad(-10)
			)

	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_spring_arm.rotation.y -= event.relative.x * 0.005
			_spring_arm.rotation.x = clamp(
				_spring_arm.rotation.x - event.relative.y * 0.005,
				deg_to_rad(-65), deg_to_rad(-10)
			)

	# Maus-Scroll = Zoom auf PC
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_spring_arm.spring_length = clamp(_spring_arm.spring_length - 0.5, ZOOM_MIN, ZOOM_MAX)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_spring_arm.spring_length = clamp(_spring_arm.spring_length + 0.5, ZOOM_MIN, ZOOM_MAX)


# ══════════════════════════════════════════════════════════════════════════
#  PHYSICS
# ══════════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if not _player or not _spring_arm:
		return

	var kb: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):   kb.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  kb.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  kb.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): kb.x += 1
	if kb.length() > 0.1:
		kb = kb.normalized()

	var input_vec: Vector2 = _js_vec if _js_vec.length() > 0.05 else kb

	if input_vec.length() > 0.05:
		var dir: Vector3
		if _cam_relative:
			# Bewegung relativ zur Kamerarichtung
			var basis: Basis = _spring_arm.global_transform.basis
			var fwd: Vector3 = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
			var right: Vector3 = Vector3(basis.x.x, 0, basis.x.z).normalized()
			dir = (fwd * input_vec.y + right * input_vec.x).normalized()
		else:
			# Feste Weltachsen — Norden ist immer -Z
			dir = Vector3(input_vec.x, 0, -input_vec.y).normalized()

		_player.velocity.x = dir.x * SPEED
		_player.velocity.z = dir.z * SPEED

		# Spieler-Mesh dreht sich in Bewegungsrichtung
		for child in _player.get_children():
			if child is MeshInstance3D:
				var target_y: float = atan2(dir.x, dir.z)
				child.rotation.y = lerp_angle(child.rotation.y, target_y, 12.0 * delta)
				break
	else:
		_player.velocity.x = move_toward(_player.velocity.x, 0, SPEED * 8 * delta)
		_player.velocity.z = move_toward(_player.velocity.z, 0, SPEED * 8 * delta)

	if not _player.is_on_floor():
		_player.velocity.y -= GRAVITY * delta
	else:
		_player.velocity.y = 0.0

	_player.move_and_slide()
