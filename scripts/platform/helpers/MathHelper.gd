class_name MathHelper

## Kamera-relative Bewegungsrichtung aus Input berechnen.
## camera_arm: Node3D der als Kamera-Basis dient (SpringArm3D / PlayerCamera)
## input:      Joystick-Vektor (x = rechts, y = runter)
static func calculate_move_direction(camera_arm: Node3D, input: Vector2) -> Vector3:
	if not is_instance_valid(camera_arm):
		return Vector3.ZERO
	var basis := camera_arm.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (forward * -input.y + right * input.x).normalized()

## ADR-025: dieselbe kamera-relative Bewegungsrichtung, aber aus einem reinen
## Yaw-Winkel statt einem Kamera-Node berechnet. Grund: die Autorität (Server)
## simuliert Bewegung für JEDEN Spieler, hat aber für fremde Spieler keinen
## Kamera-Node, der jemals echten Rotations-Input bekommen hat (echte Input-
## Events entstehen nur auf der Maschine, die den Touch/die Maus physisch
## empfängt) — der camera_yaw kommt deshalb explizit vom Client als Teil des
## Movement-Input-Snapshots (siehe NetworkContract.gd, Abschnitt UNRELIABLE).
##
## Mathematisch identisch zu calculate_move_direction(): nur die Y-Komponente
## der Kamera-Rotation fließt in die Original-Formel ein (basis.x/basis.z werden
## dort ohnehin auf die XZ-Ebene projiziert), ein reiner Y-Achsen-Basis aus dem
## Yaw-Winkel liefert deshalb bit-identische Ergebnisse zu einem Kamera-Node mit
## demselben rotation.y — Pitch/Roll spielen in der Original-Formel keine Rolle.
static func calculate_move_direction_from_yaw(camera_yaw: float, input: Vector2) -> Vector3:
	var basis := Basis(Vector3.UP, camera_yaw)
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (forward * -input.y + right * input.x).normalized()
