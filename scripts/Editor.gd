# scripts/Editor.gd
extends Node

var active: bool = false
var world: Node3D
var camera: Camera3D

var spawn_mat: StandardMaterial3D


func init(p_world: Node3D, p_camera: Camera3D) -> void:
	world = p_world
    	camera = p_camera
        	spawn_mat = StandardMaterial3D.new()
            	spawn_mat.albedo_color = Color(0.15, 0.42, 0.1)  # Gleicher Grünton wie Props


                func set_active(flag: bool) -> void:
                	active = flag


                    func is_active() -> bool:
                    	return active


                        # Wird vom Touch-System aufgerufen, wenn ein kurzer Tap im Edit-Modus erfolgt
                        func try_place_at(screen_pos: Vector2) -> void:
                        	if not active or not world or not camera:
                            		return

                                    	var from := camera.project_ray_origin(screen_pos)
                                        	var to := from + camera.project_ray_normal(screen_pos) * 1000.0

                                            	var space_state := world.get_world_3d().direct_space_state
                                                	var query := PhysicsRayQueryParameters3D.create(from, to)
                                                    	query.collision_mask = 1   # Dein Boden ist auf Layer 1? Default ist 1
                                                        	var result := space_state.intersect_ray(query)

                                                            	if result.is_empty():
                                                                		return

                                                                        	var hit_point: Vector3 = result.position
                                                                            	hit_point.y += 1.0   # Box mittig auf den Boden setzen

                                                                                	_spawn_box(hit_point)


                                                                                    func _spawn_box(pos: Vector3) -> void:
                                                                                    	var body := StaticBody3D.new()
                                                                                        	var col := CollisionShape3D.new()
                                                                                            	var shape := BoxShape3D.new()
                                                                                                	shape.size = Vector3(1.5, 2.0, 1.5)
                                                                                                    	col.shape = shape
                                                                                                        	body.add_child(col)

                                                                                                            	var mesh_inst := MeshInstance3D.new()
                                                                                                                	var box := BoxMesh.new()
                                                                                                                    	box.size = Vector3(1.5, 2.0, 1.5)
                                                                                                                        	mesh_inst.mesh = box
                                                                                                                            	mesh_inst.material_override = spawn_mat
                                                                                                                                	body.add_child(mesh_inst)

                                                                                                                                    	body.position = pos
                                                                                                                                        	world.add_child(body)