extends Node3D
class_name PlayerVisuals

var mesh: MeshInstance3D
var rotation_speed: float = 10.0


func _init() -> void:
	mesh = MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	mesh.position = Vector3(0, 1.0, 0)
	add_child(mesh)


func handle_rotation(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), rotation_speed * delta)


## Visuelles Feedback für verschiedene Events.
func play_effect(effect_name: String) -> void:
	match effect_name:
		"interrupted":
			# Kleines Shake-Tween als visuelles Feedback
			var tween := create_tween()
			tween.tween_property(self, "position:x", 0.15, 0.05)
			tween.tween_property(self, "position:x", -0.15, 0.05)
			tween.tween_property(self, "position:x", 0.0, 0.05)
