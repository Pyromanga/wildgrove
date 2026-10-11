# res://tests/unit/test_enemy_ai.gd
extends GutTest

## Unit-Tests für EnemyAI (reine State-Machine-Logik, RefCounted, aus
## EnemyNPC._physics_process() extrahiert — siehe Klassenkommentar).
##
## Strategie: caller (CharacterBody3D) und player (Node3D) als einfache
## Nodes via add_child_autofree() — nur global_position wird gebraucht (plus
## look_at() im CHASE-Bewegungspfad, das aber nicht separat auf einen
## konkreten Rotationswert geprüft wird, aus demselben Grund wie in
## test_math_helper.gd: Rotationsrichtung ohne Godot-Laufzeit nicht sicher
## von Hand verifizierbar). Bewegungs-Testfälle sind deshalb bewusst
## achsen-parallel gewählt (Spieler direkt auf der X-Achse) — das macht die
## erwarteten velocity-Werte eindeutig ohne jede Rotationsmathematik.
##
## Abgedeckt:
##   - Alle vier Zustandsübergänge: IDLE→CHASE, CHASE→IDLE, CHASE→ATTACK,
##     ATTACK→CHASE, inkl. der exakten Distanz-Grenzwerte (< vs. <=)
##   - DEAD ist ein Sackgassen-Zustand: update() gibt out_vel unverändert
##     zurück, do_melee immer false, UND attack_timer wird währenddessen gar
##     nicht erst dekrementiert (der DEAD-Check kommt im Code vor der
##     Timer-Berechnung)
##   - Melee-Trigger: nur wenn attack_timer<=0 UND in Reichweite, Cooldown
##     wird danach neu gesetzt; "Spieler verlässt Reichweite" hat Vorrang vor
##     "Cooldown ist abgelaufen" (Reihenfolge der if/elif im Code)
##   - Geschwindigkeits-Interpolation (move_toward) in allen drei aktiven
##     Zuständen, mit den jeweils unterschiedlichen Verzögerungsraten

const DETECT_RANGE := 10.0
const ATTACK_RANGE := 2.0
const ATTACK_CD := 1.0
const SPEED := 5.0

var _ai: EnemyAI
var _caller: CharacterBody3D
var _player: Node3D


func before_each() -> void:
	_ai = EnemyAI.new(DETECT_RANGE, ATTACK_RANGE, ATTACK_CD, SPEED)
	_caller = CharacterBody3D.new()
	add_child_autofree(_caller)
	_caller.global_position = Vector3.ZERO
	_player = Node3D.new()
	add_child_autofree(_player)


func after_each() -> void:
	_ai = null
	_caller = null
	_player = null


# ─────────────────────────────────────────────
# Konstruktor
# ─────────────────────────────────────────────

func test_default_state_is_idle() -> void:
	assert_eq(_ai.state, EnemyAI.State.IDLE)

func test_default_attack_timer_is_zero() -> void:
	assert_eq(_ai.attack_timer, 0.0)

func test_init_stores_configured_ranges() -> void:
	assert_eq(_ai._detect_range, DETECT_RANGE)
	assert_eq(_ai._attack_range, ATTACK_RANGE)
	assert_eq(_ai._attack_cd, ATTACK_CD)
	assert_eq(_ai._speed, SPEED)


# ─────────────────────────────────────────────
# IDLE
# ─────────────────────────────────────────────

func test_idle_decelerates_velocity_when_player_far() -> void:
	_player.global_position = Vector3(100.0, 0.0, 0.0)
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3(3.0, 0.0, 4.0))
	assert_almost_eq(result["velocity"].x, 2.5, 0.001, "move_toward(3, 0, 5*0.1=0.5) = 2.5")
	assert_almost_eq(result["velocity"].z, 3.5, 0.001, "move_toward(4, 0, 0.5) = 3.5")
	assert_eq(_ai.state, EnemyAI.State.IDLE)
	assert_false(result["do_melee"])

func test_idle_stays_idle_at_exact_detect_range_boundary() -> void:
	# dist < _detect_range (strikt) -> bei GENAU detect_range bleibt IDLE.
	_player.global_position = Vector3(DETECT_RANGE, 0.0, 0.0)
	_ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_eq(_ai.state, EnemyAI.State.IDLE)

func test_idle_transitions_to_chase_within_detect_range() -> void:
	_player.global_position = Vector3(DETECT_RANGE - 0.01, 0.0, 0.0)
	_ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_eq(_ai.state, EnemyAI.State.CHASE)


# ─────────────────────────────────────────────
# CHASE
# ─────────────────────────────────────────────

func test_chase_returns_to_idle_when_player_too_far() -> void:
	_ai.state = EnemyAI.State.CHASE
	_player.global_position = Vector3(DETECT_RANGE * 1.5 + 0.01, 0.0, 0.0)
	_ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_eq(_ai.state, EnemyAI.State.IDLE)

func test_chase_stays_chase_at_exact_flee_boundary() -> void:
	# dist > _detect_range*1.5 (strikt) -> bei GENAU dem 1.5-fachen bleibt CHASE.
	_ai.state = EnemyAI.State.CHASE
	_player.global_position = Vector3(DETECT_RANGE * 1.5, 0.0, 0.0)
	_ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_eq(_ai.state, EnemyAI.State.CHASE)

func test_chase_transitions_to_attack_within_attack_range() -> void:
	_ai.state = EnemyAI.State.CHASE
	_player.global_position = Vector3(ATTACK_RANGE - 0.01, 0.0, 0.0)
	_ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_eq(_ai.state, EnemyAI.State.ATTACK)

func test_chase_moves_toward_player_along_axis() -> void:
	# Achsenparallel gewählt (Spieler direkt auf +X) -> eindeutige, von Hand
	# nachrechenbare velocity ohne jede Rotationsmathematik.
	_ai.state = EnemyAI.State.CHASE
	_player.global_position = Vector3(5.0, 0.0, 0.0)  # zwischen attack_range (2) und detect_range*1.5 (15)
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_almost_eq(result["velocity"].x, 1.0, 0.001, "move_toward(0, 1*5=5, 10*0.1=1.0) = 1.0")
	assert_almost_eq(result["velocity"].z, 0.0, 0.001)
	assert_eq(_ai.state, EnemyAI.State.CHASE)
	assert_false(result["do_melee"])


# ─────────────────────────────────────────────
# ATTACK
# ─────────────────────────────────────────────

func test_attack_deals_melee_when_timer_ready_and_in_range() -> void:
	_ai.state = EnemyAI.State.ATTACK
	_ai.attack_timer = 0.0
	_player.global_position = Vector3(1.0, 0.0, 0.0)  # innerhalb attack_range*1.3 = 2.6
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_true(result["do_melee"])
	assert_eq(_ai.attack_timer, ATTACK_CD, "Cooldown wird nach dem Treffer neu gesetzt.")
	assert_eq(_ai.state, EnemyAI.State.ATTACK)

func test_attack_no_melee_while_cooldown_active() -> void:
	_ai.state = EnemyAI.State.ATTACK
	_ai.attack_timer = 0.5
	_player.global_position = Vector3(1.0, 0.0, 0.0)
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_false(result["do_melee"])
	assert_almost_eq(_ai.attack_timer, 0.4, 0.001)

func test_attack_returns_to_chase_when_player_leaves_range() -> void:
	_ai.state = EnemyAI.State.ATTACK
	_ai.attack_timer = 0.0  # Timer wäre bereit, aber Reichweite hat Vorrang
	_player.global_position = Vector3(ATTACK_RANGE * 1.3 + 0.01, 0.0, 0.0)
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3.ZERO)
	assert_eq(_ai.state, EnemyAI.State.CHASE)
	assert_false(result["do_melee"], "Reichweite-Verlassen hat Vorrang vor bereitem Cooldown (if/elif-Reihenfolge im Code).")

func test_attack_decelerates_velocity() -> void:
	_ai.state = EnemyAI.State.ATTACK
	_ai.attack_timer = 999.0  # Cooldown künstlich hoch halten, damit kein Melee die Zuordnung verwässert
	_player.global_position = Vector3(0.5, 0.0, 0.0)  # bleibt in Reichweite -> kein Zustandswechsel
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3(4.0, 0.0, 6.0))
	assert_almost_eq(result["velocity"].x, 3.2, 0.001, "move_toward(4, 0, 8*0.1=0.8) = 3.2")
	assert_almost_eq(result["velocity"].z, 5.2, 0.001, "move_toward(6, 0, 0.8) = 5.2")


# ─────────────────────────────────────────────
# DEAD
# ─────────────────────────────────────────────

func test_set_dead_from_any_state() -> void:
	_ai.state = EnemyAI.State.CHASE
	_ai.set_dead()
	assert_eq(_ai.state, EnemyAI.State.DEAD)

func test_dead_returns_input_velocity_unchanged() -> void:
	_ai.set_dead()
	var result: Dictionary = _ai.update(_caller, _player, 0.1, Vector3(7.0, 0.0, 9.0))
	assert_eq(result["velocity"], Vector3(7.0, 0.0, 9.0))
	assert_false(result["do_melee"])
	assert_eq(_ai.state, EnemyAI.State.DEAD)

func test_dead_does_not_decrement_attack_timer() -> void:
	# Der DEAD-Check im Code kommt VOR der attack_timer-Berechnung -> der
	# Timer wird im DEAD-Zustand gar nicht erst angefasst.
	_ai.set_dead()
	_ai.attack_timer = 5.0
	_ai.update(_caller, _player, 1.0, Vector3.ZERO)
	assert_eq(_ai.attack_timer, 5.0)
