extends RefCounted
class_name WorldFactory

func create_world() -> Node3D:
    Logger.log_debug("create_world() start", "WorldFactory")
    var data := create_world_data()
    Logger.log_debug("WorldData erstellt: " + str(data.get_tree_count()) + " Bäume", "WorldFactory")
    var world := build_world_nodes(data)
    Logger.log_debug("create_world() fertig", "WorldFactory")
    return world

func create_world_data() -> WorldData:
    var data := WorldData.new()
    data.player_position = Vector3(0, 1, 0)
    data.add_tree(Vector3(5, 0, 5))
    data.add_tree(Vector3(-6, 0, 4))
    return data

func build_world_nodes(data: WorldData) -> Node3D:
    var world := Node3D.new()
    world.name = "World"

    Logger.log_debug("Environment wird gebaut...", "WorldFactory")
    _add_environment(world)
    Logger.log_debug("Boden wird gebaut...", "WorldFactory")
    _add_ground(world)
    Logger.log_debug("Player wird gebaut...", "WorldFactory")
    _add_player(world, data.player_position)
    Logger.log_debug("Bäume werden gebaut...", "WorldFactory")
    _add_trees(world, data.tree_positions)
    Logger.log_debug("build_world_nodes() fertig", "WorldFactory")

    return world

func _add_environment(world: Node3D) -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-45, 30, 0)
    sun.light_energy = 1.2
    sun.shadow_enabled = true
    world.add_child(sun)

    var env_node := WorldEnvironment.new()
    env_node.name = "WorldEnvironment"
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color     = Color(0.2, 0.5, 0.9)
    sky_mat.sky_horizon_color = Color(0.6, 0.8, 1.0)
    sky_mat.ground_horizon_color = Color(0.4, 0.6, 0.3)
    sky_mat.ground_bottom_color  = Color(0.2, 0.3, 0.1)
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.5
    env_node.environment = env
    world.add_child(env_node)
    Logger.log_debug("Environment OK", "WorldFactory")

func _add_ground(world: Node3D) -> void:
    var ground := StaticBody3D.new()
    ground.name = "Ground"

    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(100, 0.2, 100)
    col.shape = shape
    ground.add_child(col)

    var mesh_inst := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(100, 0.2, 100)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.6, 0.25)
    mesh_inst.mesh = mesh
    mesh_inst.material_override = mat
    ground.add_child(mesh_inst)

    ground.position.y = -0.1
    world.add_child(ground)
    Logger.log_debug("Boden OK", "WorldFactory")

func _add_player(world: Node3D, pos: Vector3) -> void:
    var player := CharacterBody3D.new()
    player.name = "Player"
    player.set_script(load("res://scripts/player/Player.gd"))
    player.position = pos
    world.add_child(player)
    Logger.log_debug("Player OK bei " + str(pos), "WorldFactory")

func _add_trees(world: Node3D, positions: Array) -> void:
    for i in positions.size():
        var tree := Node3D.new()
        tree.set_script(load("res://scripts/world/objects/OakTree.gd"))
        tree.position = positions[i]
        world.add_child(tree)          # erst add_child, DANN group
        tree.add_to_group("interactable")   # ← NEU
        Logger.log_debug("Baum " + str(i) + " OK bei " + str(positions[i]), "WorldFactory")