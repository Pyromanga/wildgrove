extends Node3D
class_name PlayerVisuals

var mesh: MeshInstance3D
var rotation_speed: float = 10.0

func _init() -> void:
	# Hier bauen wir das Mesh
	mesh = MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	mesh.position.y = 1.0 # Mesh hochsetzen
	add_child(mesh)

func handle_rotation(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)