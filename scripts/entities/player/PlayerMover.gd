# res://scripts/entities/player/PlayerMover.gd
class_name PlayerMover
extends RefCounted

const LOG_CAT := "PlayerMover"

## Direkt gesetzte Stats (von Player._apply_stats() via DI).
## _stats (PlayerData-Resource) wird nicht mehr benötigt — DataService ist
## die Single Source of Truth, Player injiziert die Werte als floats.
var speed: float = 6.0
var gravity: float = 12.0

## Referenz auf StatModifierService — via Player.on_spawn(ctx) injiziert.
## Nil-safe: wenn kein Service verfügbar, fällt get_current_speed() auf speed zurück.
var _stat_modifiers: StatModifierService = null

var _last_speed_log: float = 0.0

## Injiziert den StatModifierService nach dem Spawn.
## Wird von Player.on_spawn(ctx) aufgerufen.
func inject_stat_modifiers(svc: StatModifierService) -> void:
	_stat_modifiers = svc
	AppLogger.log_debug("StatModifierService injiziert.", LOG_CAT)

## player_id: WESSEN effektiver Speed abgefragt wird. Pflichtparameter ohne
## Default seit ADR-029 Round 69 (StatModifierService führt jetzt player_id:
## String, siehe TODO-offene-probleme.md) — vorher peer_id: int = 1, Default
## nur aus Kompatibilitätsgründen. Der einzige Aufrufer (Player.gd
## _apply_movement()) löst seine eigene _owner_peer_id vorher über eine lokale
## _resolve_player_uuid() auf (PlayerMover selbst bleibt dep-frei, kein
## NetworkBridge-Zugriff — identisches Muster zu InteractionResolver.resolve()).
## Leerer player_id (Auflösung fehlgeschlagen) → kein Crash, fällt auf
## unmodifizierten Basis-Speed zurück, gleicher Vertrag wie überall sonst.
func get_current_speed(player_id: String) -> float:
	var current_speed: float
	if is_instance_valid(_stat_modifiers) and not player_id.is_empty():
		current_speed = _stat_modifiers.get_effective_stat("move_speed", speed, player_id)
	else:
		current_speed = speed

	if not is_equal_approx(current_speed, _last_speed_log):
		AppLogger.log_info(
			"Speed Update: %.2f (Base: %.2f)" % [current_speed, speed],
			LOG_CAT
		)
		_last_speed_log = current_speed

	return current_speed

const MAX_FALL_SPEED: float = 50.0  # Terminal velocity — verhindert unbegrenzten Fall-Log-Spam

## ADR-026: calculate_velocity() ist jetzt eine REINE Funktion — kein Zugriff auf
## _stat_modifiers, kein Logging-Seiteneffekt, keine Mutation von self-State.
## Grund: Client-Side Prediction re-simuliert denselben Aufruf potenziell mehrfach
## pro Frame (Reconciliation, siehe Player.gd). Eine Funktion, die bei Resimulation
## Log-Zeilen spammt oder einen live Stat-Service abfragt, dessen Wert sich zwischen
## Original-Simulation und Resimulation geändert haben könnte (z.B. ein Buff läuft
## mitten im Re-Simulations-Fenster ab), ist NICHT "gleicher Input + gleicher
## Vorzustand → exakt gleiches Ergebnis" — genau das von ADR-026 als ungeprüftes
## Risiko benannte Problem. effective_speed ist deshalb jetzt ein expliziter
## Parameter: der Aufrufer entscheidet, WANN er ihn zieht (live für die reale
## Simulation, aus dem Prediction-Ringpuffer für eine Resimulation — siehe
## Player.gd._resimulate_from()), calculate_velocity() selbst fragt nie nach.
##
## Determinismus-Vertrag: gleiche (current_vel, direction, delta, on_floor,
## effective_speed) → immer exakt dasselbe Ergebnis. Verifiziert in
## tests/unit/test_player_mover_determinism.gd (zweimaliger Aufruf mit
## identischen Argumenten, Vergleich über is_equal_approx()).
func calculate_velocity(
	current_vel: Vector3, direction: Vector3, delta: float, on_floor: bool,
	effective_speed: float
) -> Vector3:
	var target_vel: Vector3 = direction * effective_speed
	var vel: Vector3 = current_vel

	const ACCEL: float = 10.0

	vel.x = lerp(vel.x, target_vel.x, ACCEL * delta)
	vel.z = lerp(vel.z, target_vel.z, ACCEL * delta)

	if on_floor:
		vel.y = 0.0
	else:
		vel.y -= gravity * delta
		# Terminal velocity — ohne Deckel fällt der Spieler durch Kollisionen bei hoher Geschwindigkeit
		vel.y = maxf(vel.y, -MAX_FALL_SPEED)

	return vel
