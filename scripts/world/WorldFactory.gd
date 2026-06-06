extends RefCounted
class_name WorldFactory

## WorldFactory — Erzeugt die STATISCHE Spielwelt (Geometrie + Licht + Player).
##
## WICHTIG — Was gehört NICHT hierher:
##   Entities (OakTree, IronOre, NPCs) → EntityOrchestrator (via WorldService)
##   Services, UI → jeweilige Manager
##
## Anti-Pattern VERHINDERT:
##   VERBOTEN: Node3D.new() + node.set_script(script)
##   GRUND: set_script() nach Node-Erstellung triggert _ready() ein zweites Mal
##          (Godot's Engine ruft _ready() beim Tree-Eintritt auf, und nochmal wenn
##          das Script gesetzt wird). Bei CharacterBody3D: undefiniertes Physik-Verhalten.
##   KORREKT: script.new() → direkte Instanz MIT Script von Anfang an.
##            Damit gibt es exakt einen _ready()-Aufruf nach add_child().

const LOG_CAT := "WorldFactory"


## Erzeugt die statische Welt-Geometrie ohne Entities.
## Gibt einen temporären Container-Node zurück — WorldService verschiebt dessen Kinder
## in world_root (die echte World.tscn).
##
## Enthält: Beleuchtung, Himmel, Boden, Player.
## NICHT enthalten: OakTree, IronOre, NPCs → werden von WorldService+EntityOrchestrator gespawnt.
func create_world() -> Node3D:
	var t := Logger.log_begin("create_world()", LOG_CAT)
	var world := Node3D.new()
	world.name = "WorldContainer"

	_add_environment(world)
	_add_ground(world)
	_add_player(world, Vector3(0, 0, 0))

	Logger.log_end("create_world()", t, LOG_CAT)
	Logger.log_info(
		"Statische Welt erstellt. Nodes: %d." % world.get_child_count(), LOG_CAT
	)
	return world


# ─────────────────────────────────────────────
# Umgebung
# ─────────────────────────────────────────────


func _add_environment(world: Node3D) -> void:
	# Sonne
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)

	# Prozeduraler Himmel
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.9)
	sky_mat.sky_horizon_color = Color(0.6, 0.8, 1.0)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env_node.environment = env
	world.add_child(env_node)

	Logger.log_debug("Umgebung (Sonne + Himmel) erstellt.", LOG_CAT)


# ─────────────────────────────────────────────
# Boden
# ─────────────────────────────────────────────


func _add_ground(world: Node3D) -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"

	# Kollisionsform
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 0.2, 100)
	col.shape = shape
	ground.add_child(col)

	# Visuell
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(100, 0.2, 100)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.25)
	mesh_inst.mesh = mesh
	mesh_inst.material_override = mat
	ground.add_child(mesh_inst)

	# Y = -0.1 damit Oberfläche bei Y = 0 liegt (BoxShape height=0.2 → -0.1 bis +0.1)
	ground.position.y = -0.1
	world.add_child(ground)

	Logger.log_debug("Boden erstellt (100x100, y=-0.1).", LOG_CAT)


# ─────────────────────────────────────────────
# Player
# ─────────────────────────────────────────────


func _add_player(world: Node3D, pos: Vector3) -> void:
	## KORREKTE Instanziierung — KEIN set_script() nach new()!
	##
	## Falsch (Anti-Pattern):
	##   var p = CharacterBody3D.new()
	##   p.set_script(load("res://scripts/player/Player.gd"))  ← doppeltes _ready()!
	##
	## Richtig:
	##   var PlayerClass := load("res://scripts/player/Player.gd")
	##   var p: CharacterBody3D = PlayerClass.new()
	##   → _ready() feuert genau EINMAL nach add_child()

	var player_script: GDScript = load("res://scripts/player/Player.gd")
	if not player_script:
		Logger.log_error("Player.gd nicht ladbar — Pfad korrekt?", LOG_CAT)
		return

	var player: CharacterBody3D = player_script.new()
	player.name = "Player"

	## Y-Position: Boden-Oberfläche liegt bei y=0.
	## CollisionShape (Capsule height=1.8) hat Zentrum bei y=0.9.
	## Player auf y=0 gesetzt → steht direkt auf dem Boden.
	player.position = Vector3(pos.x, 0.0, pos.z)

	world.add_child(player)
	Logger.log_info(
		"Player instanziiert. Position: %s." % str(player.position), LOG_CAT
	)
