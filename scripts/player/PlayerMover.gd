class_name PlayerMover
extends RefCounted

var speed:   float = 6.0
var gravity: float = 12.0
var accel:   float = 10.0

func calculate_velocity(
	current_vel: Vector3,
	direction:   Vector3,
	delta:       float,
	on_floor:    bool
) -> Vector3:
	var target_vel := direction * speed
	var vel        := current_vel
	vel.x = lerp(vel.x, target_vel.x, accel * delta)
	vel.z = lerp(vel.z, target_vel.z, accel * delta)
	vel.y = 0.0 if on_floor else vel.y - gravity * delta
	return vel