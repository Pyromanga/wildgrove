class_name PlayerMover
extends RefCounted

var speed:   float = 6.0
var gravity: float = 12.0
var accel:   float = 10.0 # Wie schnell er auf Touren kommt

func calculate_velocity(current_vel: Vector3, direction: Vector3, delta: float, on_floor: bool) -> Vector3:
	var target_vel = direction * speed
	
	# Sanftes Beschleunigen/Bremsen (Lerp)
	var temp_vel = current_vel
	temp_vel.x = lerp(temp_vel.x, target_vel.x, accel * delta)
	temp_vel.z = lerp(temp_vel.z, target_vel.z, accel * delta)
	
	# Schwerkraft
	if not on_floor:
		temp_vel.y -= gravity * delta
	else:
		temp_vel.y = 0
		
	return temp_vel