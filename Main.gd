extends Node

var _player: CharacterBody3D
var _spring_arm: SpringArm3D
var _log_label: Label
var _log_lines: Array[String] = []
var _js_base: ColorRect
var _js_knob: ColorRect

var _js_finger: int = -1
var _js_origin: Vector2 = Vector2.ZERO
var _js_vec: Vector2 = Vector2.ZERO
const JS_RADIUS: float = 90.0
var _cam_finger: int = -1
var _cam_last: Vector2 = Vector2.ZERO

const SPEED: float = 5.5
const GRAVITY: float = 9.8


func _log(msg: String) -> void:
	print(msg)
	_log_lines.append(msg)
	if _log_lines.size() > 15:
		_log_lines.remove_at(0)
	if _log_label:
		_log_label.text = "\n".join(_log_lines)


func _ready() -> void:
	_build_screen_log()
	_log("=== _ready() START ===")
	_build_world()
	_log("Welt OK")
	_build_player()
	_log("Spieler OK")
	call_deferred("_build_hud")


func _build_screen_log() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(1080, 420)
	cl.add_child(bg)
	_log_label = Label.new()
	_log_label.position = Vector2(10, 10)
	_log_label.size = Vector2(1060, 400)
	_log_label.add_theme_font_size_override("font_size", 26)
	_log_label.add_theme_color_override("font_color", Color.GREEN)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cl.add_child(_log_label)


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


func _build_hud() -> void:
	_log("HUD START")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_log("VP: " + str(vp))

	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	_js_base = ColorRect.new()
	_js_base.size = Vector2(JS_RADIUS * 2, JS_RADIUS * 2)
	_js_base.color = Color(1, 0, 0, 0.6)
	_js_base.position = Vector2(30, vp.y - JS_RADIUS * 2 - 30)
	hud.add_child(_js_base)

	_js_knob = ColorRect.new()
	_js_knob.size = Vector2(60, 60)
	_js_knob.color = Color(1, 1, 1, 1.0)
	_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
	hud.add_child(_js_knob)

	var cam_hint := ColorRect.new()
	cam_hint.size = Vector2(180, 60)
	cam_hint.color = Color(0, 0.4, 1, 0.5)
	cam_hint.position = Vector2(vp.x - 200, vp.y - 80)
	hud.add_child(cam_hint)

	_log("HUD DONE - Joystick bei: " + str(_js_base.position))


func _input(event: InputEvent) -> void:
	if not _js_base or not _spring_arm:
		return
	var sw: float = get_viewport().get_visible_rect().size.x

	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			_log("Touch " + str(pos))
			if pos.x < sw * 0.5:
				if _js_finger < 0:
					_js_finger = event.index
					_js_origin = pos
					_js_base.position = pos - Vector2(JS_RADIUS, JS_RADIUS)
					_js_knob.position = pos - Vector2(30, 30)
			else:
				if _cam_finger < 0:
					_cam_finger = event.index
					_cam_last = pos
		else:
			if event.index == _js_finger:
				_js_finger = -1
				_js_vec = Vector2.ZERO
				_js_knob.position = _js_base.position + Vector2(JS_RADIUS - 30, JS_RADIUS - 30)
			if event.index == _cam_finger:
				_cam_finger = -1

	elif event is InputEventScreenDrag:
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
		var basis: Basis = _spring_arm.global_transform.basis
		var fwd: Vector3 = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
		var right: Vector3 = Vector3(basis.x.x, 0, basis.x.z).normalized()
		var dir: Vector3 = (fwd * input_vec.y + right * input_vec.x).normalized()
		_player.velocity.x = dir.x * SPEED
		_player.velocity.z = dir.z * SPEED
	else:
		_player.velocity.x = move_toward(_player.velocity.x, 0, SPEED * 8 * delta)
		_player.velocity.z = move_toward(_player.velocity.z, 0, SPEED * 8 * delta)

	if not _player.is_on_floor():
		_player.velocity.y -= GRAVITY * delta
	else:
		_player.velocity.y = 0.0

	_player.move_and_slide()
