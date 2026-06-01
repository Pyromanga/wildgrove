class_name MathHelper

## Kamera-relative Bewegung berechnen
static func calculate_move_direction(camera_arm: Node3D, input: Vector2) -> Vector3:
    if not camera_arm: return Vector3.ZERO
    var basis = camera_arm.global_transform.basis
    var forward = Vector3(-basis.z.x, 0, -basis.z.z).normalized()
    var right = Vector3(basis.x.x, 0, basis.x.z).normalized()
    return (forward * -input.y + right * input.x).normalized()