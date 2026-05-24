extends Node
## Main.gd — Minimal Bootstrap
## Funktioniert ohne Child-Nodes, ohne Autoloads, ohne Assets
## Einfach als Script an die Root-Node der Main.tscn hängen

func _ready() -> void:
	print("[WildGrove] Main geladen ✅")
	_build_test_scene()


func _build_test_scene() -> void:
	# Welt-Container
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	# Boden
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(50, 50)
	ground_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.25)
	ground_mesh.material_override = mat
	world.add_child(ground_mesh)

	# Kollision für den Boden
	var ground_body := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	ground_col.shape = BoxShape3D.new()
	(ground_col.shape as BoxShape3D).size = Vector3(50, 0.1, 50)
	ground_body.add_child(ground_col)
	ground_body.position = Vector3(0, -0.05, 0)
	world.add_child(ground_body)

	# Ein paar Test-Objekte (Bäume als Capsule)
	for i in 8:
		var tree := MeshInstance3D.new()
		var caps := CapsuleMesh.new()
		caps.radius = 0.3
		caps.height = 2.5
		tree.mesh = caps
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.1, 0.5, 0.1)
		tree.material_override = tmat
		tree.position = Vector3(
			randf_range(-15, 15),
			1.25,
			randf_range(-15, 15)
		)
		world.add_child(tree)

	# Licht
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)

	# Umgebung
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.9)
	sky_mat.sky_horizon_color = Color(0.6, 0.8, 1.0)
	sky_mat.ground_bottom_color = Color(0.3, 0.6, 0.25)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_node.environment = env
	add_child(env_node)

	# Spieler (Capsule als Platzhalter)
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group("player")

	var p_mesh := MeshInstance3D.new()
	var p_caps := CapsuleMesh.new()
	p_caps.radius = 0.35
	p_caps.height = 1.8
	p_mesh.mesh = p_caps
	var p_mat := StandardMaterial3D.new()
	p_mat.albedo_color = Color(0.9, 0.6, 0.1)
	p_mesh.material_override = p_mat
	p_mesh.position.y = 0.9
	player.add_child(p_mesh)

	var p_col := CollisionShape3D.new()
	p_col.shape = CapsuleShape3D.new()
	(p_col.shape as CapsuleShape3D).radius = 0.35
	(p_col.shape as CapsuleShape3D).height = 1.8
	p_col.position.y = 0.9
	player.add_child(p_col)

	player.position = Vector3(0, 0.9, 0)
	world.add_child(player)

	# Kamera am Spieler
	var spring := SpringArm3D.new()
	spring.spring_length = 8.0
	spring.rotation_degrees = Vector3(-40, 0, 0)
	spring.position = Vector3(0, 1.0, 0)
	player.add_child(spring)

	var cam := Camera3D.new()
	spring.add_child(cam)

	# Simpler Bewegungs-Controller direkt hier
	var controller := _SimpleController.new()
	controller.player = player
	controller.spring_arm = spring
	add_child(controller)

	print("[WildGrove] Test-Szene aufgebaut ✅")
	print("[WildGrove] Steuerung: WASD / Pfeiltasten, Maus zum Kamera-Drehen")


# ── Inline-Controller (kein extra Script nötig) ────────────────────────────
class _SimpleController extends Node:
	var player: CharacterBody3D
	var spring_arm: SpringArm3D
	const SPEED := 5.0
	const GRAVITY := 9.8

	func _physics_process(delta: float) -> void:
		if not player:
			return

		# Tastatur-Eingabe
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir.y += 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):   dir.y -= 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):   dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):  dir.x += 1

		# Kamera-relative Bewegung
		if dir.length() > 0.1:
			dir = dir.normalized()
			var cam_basis := spring_arm.global_transform.basis
			var forward := -cam_basis.z
			var right := cam_basis.x
			forward.y = 0; right.y = 0
			var move := (forward * dir.y + right * dir.x).normalized()
			player.velocity.x = move.x * SPEED
			player.velocity.z = move.z * SPEED
		else:
			player.velocity.x = move_toward(player.velocity.x, 0, SPEED * delta * 8)
			player.velocity.z = move_toward(player.velocity.z, 0, SPEED * delta * 8)

		if not player.is_on_floor():
			player.velocity.y -= GRAVITY * delta

		player.move_and_slide()

	func _input(event: InputEvent) -> void:
		# Kamera mit Maus drehen
		if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			spring_arm.rotation.y -= event.relative.x * 0.005
			spring_arm.rotation.x = clamp(
				spring_arm.rotation.x - event.relative.y * 0.005,
				deg_to_rad(-70), deg_to_rad(-15)
			)
