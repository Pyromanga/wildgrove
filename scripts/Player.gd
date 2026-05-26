extends CharacterBody3D

## Player.gd — Mit Raycast-Interaktion

const SPEED: float       = 5.5
const GRAVITY: float     = 9.8
const CAM_SMOOTH: float  = 14.0
const ZOOM_SMOOTH: float = 8.0

var _spring_arm: SpringArm3D
var _mesh: MeshInstance3D
var _interact_ray: RayCast3D # Der "Blick" des Spielers

var _target_yaw: float   = 0.0
var _target_pitch: float = deg_to_rad(-35.0)
var _target_zoom: float  = 8.0

func _ready() -> void:
	add_to_group("player")
    	_build_mesh()
        	_build_camera()
            	_build_interaction_ray()
                	position = Vector3(0, 0.9, 0)

                    func _build_mesh() -> void:
                    	var col := CollisionShape3D.new()
                        	var caps := CapsuleShape3D.new()
                            	caps.radius = 0.4; caps.height = 1.8
                                	col.shape = caps
                                    	col.position.y = 0.9
                                        	add_child(col)

                                            	_mesh = MeshInstance3D.new()
                                                	var cm := CapsuleMesh.new()
                                                    	cm.radius = 0.4; cm.height = 1.8
                                                        	_mesh.mesh = cm
                                                            	var mat := StandardMaterial3D.new()
                                                                	mat.albedo_color = Color(0.95, 0.6, 0.05)
                                                                    	_mesh.material_override = mat
                                                                        	_mesh.position.y = 0.9
                                                                            	add_child(_mesh)

                                                                                func _build_camera() -> void:
                                                                                	_spring_arm = SpringArm3D.new()
                                                                                    	_spring_arm.spring_length = _target_zoom
                                                                                        	_spring_arm.position = Vector3(0, 1.5, 0)
                                                                                            	_spring_arm.rotation.x = _target_pitch
                                                                                                	add_child(_spring_arm)

                                                                                                    	var cam := Camera3D.new()
                                                                                                        	cam.current = true
                                                                                                            	_spring_arm.add_child(cam)

                                                                                                                func _build_interaction_ray() -> void:
                                                                                                                	_interact_ray = RayCast3D.new()
                                                                                                                    	# Der Raycast schießt von der Kamera-Position 3 Meter nach vorne
                                                                                                                        	_interact_ray.target_position = Vector3(0, 0, -3.0) 
                                                                                                                            	_interact_ray.enabled = true
                                                                                                                                	# Wir hängen den Raycast an die Kamera
                                                                                                                                    	_spring_arm.get_child(0).add_child(_interact_ray)

                                                                                                                                        func _physics_process(delta: float) -> void:
                                                                                                                                        	var touch := _get_touch()
                                                                                                                                            	if not touch: return
                                                                                                                                                	
                                                                                                                                                    	_handle_movement(touch, delta)
                                                                                                                                                        	_handle_camera(touch, delta)
                                                                                                                                                            	_check_interaction(touch)

                                                                                                                                                                func _handle_movement(touch: Node, delta: float) -> void:
                                                                                                                                                                	var input_vec: Vector2 = touch.get("js_vec")
                                                                                                                                                                    	
                                                                                                                                                                        	if input_vec.length() > 0.05:
                                                                                                                                                                            		var cam_basis := _spring_arm.global_transform.basis
                                                                                                                                                                                    		var fwd := Vector3(cam_basis.z.x, 0, cam_basis.z.z).normalized()
                                                                                                                                                                                            		var right := Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
                                                                                                                                                                                                    		var dir := (fwd * -input_vec.y + right * input_vec.x).normalized()

                                                                                                                                                                                                            		velocity.x = dir.x * SPEED
                                                                                                                                                                                                                    		velocity.z = dir.z * SPEED
                                                                                                                                                                                                                            		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
                                                                                                                                                                                                                                    	else:
                                                                                                                                                                                                                                        		velocity.x = move_toward(velocity.x, 0, SPEED * 8 * delta)
                                                                                                                                                                                                                                                		velocity.z = move_toward(velocity.z, 0, SPEED * 8 * delta)

                                                                                                                                                                                                                                                        	if not is_on_floor(): velocity.y -= GRAVITY * delta
                                                                                                                                                                                                                                                            	else: velocity.y = 0.0
                                                                                                                                                                                                                                                                	move_and_slide()

                                                                                                                                                                                                                                                                    func _handle_camera(touch: Node, delta: float) -> void:
                                                                                                                                                                                                                                                                    	if touch.get("cam_delta") != Vector2.ZERO:
                                                                                                                                                                                                                                                                        		var cd: Vector2 = touch.get("cam_delta")
                                                                                                                                                                                                                                                                                		_target_yaw -= cd.x * 0.007
                                                                                                                                                                                                                                                                                        		_target_pitch = clamp(_target_pitch - cd.y * 0.007, deg_to_rad(-65), deg_to_rad(-10))
                                                                                                                                                                                                                                                                                                		touch.set("cam_delta", Vector2.ZERO)

                                                                                                                                                                                                                                                                                                        	if touch.get("zoom_delta") != 0.0:
                                                                                                                                                                                                                                                                                                            		_target_zoom = clamp(_target_zoom + touch.get("zoom_delta"), 3.0, 16.0)
                                                                                                                                                                                                                                                                                                                    		touch.set("zoom_delta", 0.0)

                                                                                                                                                                                                                                                                                                                            	_spring_arm.rotation.y = lerp_angle(_spring_arm.rotation.y, _target_yaw, CAM_SMOOTH * delta)
                                                                                                                                                                                                                                                                                                                                	_spring_arm.rotation.x = lerp(_spring_arm.rotation.x, _target_pitch, CAM_SMOOTH * delta)
                                                                                                                                                                                                                                                                                                                                    	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_zoom, ZOOM_SMOOTH * delta)

                                                                                                                                                                                                                                                                                                                                        func _check_interaction(touch: Node) -> void:
                                                                                                                                                                                                                                                                                                                                        	# Wenn wir auf die rechte Bildschirmhälfte tippen (Interaktion)
                                                                                                                                                                                                                                                                                                                                            	# Hier nutzen wir einfachheitshalber: Wenn cam_delta kurz zuckt oder ein Tap registriert wird
                                                                                                                                                                                                                                                                                                                                                	if _interact_ray.is_colliding():
                                                                                                                                                                                                                                                                                                                                                    		var obj = _interact_ray.get_collider()
                                                                                                                                                                                                                                                                                                                                                            		if obj and obj.has_node("Interactable"):
                                                                                                                                                                                                                                                                                                                                                                    			# In einem echten Spiel würdest du hier einen "Interagieren"-Button einblenden
                                                                                                                                                                                                                                                                                                                                                                                			# Für diesen Test interagieren wir automatisch, wenn wir nah dran sind und stehen bleiben
                                                                                                                                                                                                                                                                                                                                                                                            			if velocity.length() < 0.1:
                                                                                                                                                                                                                                                                                                                                                                                                        				obj.get_node("Interactable").interact(self)

                                                                                                                                                                                                                                                                                                                                                                                                                        func _get_touch() -> Node:
                                                                                                                                                                                                                                                                                                                                                                                                                        	return get_parent().get_node_or_null("TouchInput")extends