class_name EnemyAI
extends RefCounted

## EnemyAI — State-Machine-Logik für EnemyNPC (IDLE → CHASE → ATTACK → DEAD).
##
## Extrahiert aus EnemyNPC._physics_process().
## Kein Node — reine Logik-Klasse. EnemyNPC übergibt sich selbst per update().
##
## Verantwortung:
##   - Zustandsübergänge berechnen
##   - Bewegungsvektor berechnen (wird an CharacterBody3D angewandt)
##   - Angriffs-Cooldown verwalten
##
## Was EnemyAI NICHT tut:
##   - Kein direktes move_and_slide() — bleibt bei EnemyNPC (CharacterBody3D-API)
##   - Kein EventBus-Emit — bleibt bei EnemyNPC._die()

enum State { IDLE, CHASE, ATTACK, DEAD }

var state:        State = State.IDLE
var attack_timer: float = 0.0

var _detect_range: float
var _attack_range: float
var _attack_cd:    float
var _speed:        float

func _init(detect_range: float, attack_range: float, attack_cd: float, speed: float) -> void:
	_detect_range = detect_range
	_attack_range = attack_range
	_attack_cd    = attack_cd
	_speed        = speed

## Berechnet Velocity-XZ für diesen Frame.
## Gibt true zurück wenn ein Melee-Angriff ausgeführt werden soll.
## caller: der EnemyNPC-Node (für position/look_at).
func update(
	caller:  CharacterBody3D,
	player:  Node3D,
	delta:   float,
	out_vel: Vector3
) -> Dictionary:
	if state == State.DEAD:
		return {"velocity": out_vel, "do_melee": false}

	attack_timer = maxf(0.0, attack_timer - delta)

	var dist: float = caller.global_position.distance_to(player.global_position)
	var do_melee := false
	var vel := out_vel

	match state:
		State.IDLE:
			vel.x = move_toward(vel.x, 0.0, 5.0 * delta)
			vel.z = move_toward(vel.z, 0.0, 5.0 * delta)
			if dist < _detect_range:
				state = State.CHASE

		State.CHASE:
			if dist > _detect_range * 1.5:
				state = State.IDLE
			elif dist < _attack_range:
				state = State.ATTACK
			else:
				vel = _move_toward_target(caller, player.global_position, _speed, delta, vel)

		State.ATTACK:
			vel.x = move_toward(vel.x, 0.0, 8.0 * delta)
			vel.z = move_toward(vel.z, 0.0, 8.0 * delta)
			if dist > _attack_range * 1.3:
				state = State.CHASE
			elif attack_timer <= 0.0:
				do_melee    = true
				attack_timer = _attack_cd

	return {"velocity": vel, "do_melee": do_melee}

func set_dead() -> void:
	state = State.DEAD

func _move_toward_target(
	caller: CharacterBody3D, target: Vector3, spd: float, delta: float, vel: Vector3
) -> Vector3:
	var dir: Vector3 = target - caller.global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		dir = dir.normalized()
		vel.x = move_toward(vel.x, dir.x * spd, 10.0 * delta)
		vel.z = move_toward(vel.z, dir.z * spd, 10.0 * delta)
		caller.look_at(caller.global_position + dir, Vector3.UP)
	return vel
