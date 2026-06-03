class_name MathHelper

## Kamera-relative Bewegungsrichtung aus Input berechnen.
## camera_arm: Node3D der als Kamera-Basis dient (SpringArm3D / PlayerCamera)
## input:      Joystick-Vektor (x = rechts, y = runter)
static func calculate_move_direction(camera_arm: Node3D, input: Vector2) -> Vector3:
	if not is_instance_valid(camera_arm):
		return Vector3.ZERO
	var basis   := camera_arm.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right   := Vector3( basis.x.x, 0.0,  basis.x.z).normalized()
	return (forward * -input.y + right * input.x).normalized()