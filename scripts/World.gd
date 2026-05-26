extends Node3D

## World.gd — Prozedurale Umgebung mit Interaktion

const InteractableScript := preload("res://scripts/Interactable.gd")

func _ready() -> void:
	_build_lighting()
    	_build_terrain()
        	_build_props()

            func _build_lighting() -> void:
            	# Sonne
                	var sun := DirectionalLight3D.new()
                    	sun.rotation_degrees = Vector3(-55, 30, 0)
                        	sun.light_energy = 1.2
                            	sun.shadow_enabled = true
                                	add_child(sun)

                                    	# Welt-Umgebung
                                        	var env_node := WorldEnvironment.new()
                                            	var env := Environment.new()
                                                	env.background_mode = Environment.BG_COLOR
                                                    	env.background_color = Color(0.3, 0.6, 0.9)
                                                        	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
                                                            	env.ambient_light_color = Color(1, 1, 1)
                                                                	env.ambient_light_energy = 0.4
                                                                    	env_node.environment = env
                                                                        	add_child(env_node)

                                                                            func _build_terrain() -> void:
                                                                            	# Boden-Physik
                                                                                	var body := StaticBody3D.new()
                                                                                    	var col := CollisionShape3D.new()
                                                                                        	var shape := BoxShape3D.new()
                                                                                            	shape.size = Vector3(200, 0.2, 200)
                                                                                                	col.shape = shape
                                                                                                    	body.position.y = -0.1
                                                                                                        	body.add_child(col)
                                                                                                            	add_child(body)

                                                                                                                	# Boden-Optik
                                                                                                                    	var mesh_inst := MeshInstance3D.new()
                                                                                                                        	var plane := PlaneMesh.new()
                                                                                                                            	plane.size = Vector2(200, 200)
                                                                                                                                	mesh_inst.mesh = plane
                                                                                                                                    	var mat := StandardMaterial3D.new()
                                                                                                                                        	mat.albedo_color = Color(0.2, 0.45, 0.2) # Ein satteres Grün
                                                                                                                                            	mesh_inst.material_override = mat
                                                                                                                                                	add_child(mesh_inst)

                                                                                                                                                    func _build_props() -> void:
                                                                                                                                                    	# Wir definieren Positionen und was man dort bekommt
                                                                                                                                                        	var props_data := [
                                                                                                                                                                		{"pos": Vector3(5, 1, 5), "skill": "Bergbau", "xp": 25},
                                                                                                                                                                        		{"pos": Vector3(-6, 1, 4), "skill": "Holzfällen", "xp": 15},
                                                                                                                                                                                		{"pos": Vector3(8, 1, -5), "skill": "Bergbau", "xp": 25},
                                                                                                                                                                                        		{"pos": Vector3(-4, 1, -8), "skill": "Holzfällen", "xp": 15},
                                                                                                                                                                                                		{"pos": Vector3(12, 1, 2), "skill": "Stärke", "xp": 50}
                                                                                                                                                            ]
                                                                                                                                                            	
                                                                                                                                                                	for data in props_data:
                                                                                                                                                                    		_spawn_interactable_box(data.pos, data.skill, data.xp)

                                                                                                                                                                            func _spawn_interactable_box(pos: Vector3, skill: String, xp: int) -> void:
                                                                                                                                                                            	# Das physische Objekt (Box)
                                                                                                                                                                                	var body := StaticBody3D.new()
                                                                                                                                                                                    	body.position = pos
                                                                                                                                                                                        	body.add_to_group("interactable_object") # Wichtig für den Player-Raycast
                                                                                                                                                                                            	
                                                                                                                                                                                                	# Kollision
                                                                                                                                                                                                    	var col := CollisionShape3D.new()
                                                                                                                                                                                                        	var shape := BoxShape3D.new()
                                                                                                                                                                                                            	shape.size = Vector3(1.5, 2.0, 1.5)
                                                                                                                                                                                                                	col.shape = shape
                                                                                                                                                                                                                    	body.add_child(col)

                                                                                                                                                                                                                        	# Optik
                                                                                                                                                                                                                            	var mesh_inst := MeshInstance3D.new()
                                                                                                                                                                                                                                	var box := BoxMesh.new()
                                                                                                                                                                                                                                    	box.size = Vector3(1.5, 2.0, 1.5)
                                                                                                                                                                                                                                        	mesh_inst.mesh = box
                                                                                                                                                                                                                                            	var mat := StandardMaterial3D.new()
                                                                                                                                                                                                                                                	# Farbe basierend auf Skill
                                                                                                                                                                                                                                                    	if skill == "Bergbau": mat.albedo_color = Color(0.4, 0.3, 0.2)
                                                                                                                                                                                                                                                        	elif skill == "Holzfällen": mat.albedo_color = Color(0.2, 0.5, 0.1)
                                                                                                                                                                                                                                                            	else: mat.albedo_color = Color(0.7, 0.1, 0.1)
                                                                                                                                                                                                                                                                	
                                                                                                                                                                                                                                                                    	mesh_inst.material_override = mat
                                                                                                                                                                                                                                                                        	body.add_child(mesh_inst)

                                                                                                                                                                                                                                                                            	# Die Interactable-Komponente hinzufügen
                                                                                                                                                                                                                                                                                	var interact = Node.new()
                                                                                                                                                                                                                                                                                    	interact.set_script(InteractableScript)
                                                                                                                                                                                                                                                                                        	interact.xp_skill = skill
                                                                                                                                                                                                                                                                                            	interact.xp_amount = xp
                                                                                                                                                                                                                                                                                                	interact.name = "Interactable"
                                                                                                                                                                                                                                                                                                    	body.add_child(interact)

                                                                                                                                                                                                                                                                                                        	add_child(body)extends
                                                                                                                                                            ]