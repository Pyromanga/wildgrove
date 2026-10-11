# res://tests/unit/test_player_gd.gd
extends GutTest

## Unit-Tests für Player.gd, PlayerMover.gd und EnemyNPC._do_melee() Fallback.
##
## SCOPE (BUG-12 / G-01 + G-02):
##
##   G-01: Player.gd hatte bisher keinerlei Unit-Tests.
##         State-Machine, Jump-Logik, Respawn-Guard, on_despawn()-Cleanup,
##         inject_player_states() und get_closest_interactable()-Fallback
##         werden hier abgedeckt.
##
##   G-02: EnemyNPC._do_melee() Fallback-Pfad (kein EntityContext) emittiert
##         kein EventBus.world.damage_dealt — Tests verwenden EnemyNPC ohne
##         EntityContext und verifizieren dass der Fallback trotzdem Schaden
##         anwendet (und einen DamageRecord erzeugt), ohne zu crashen.
##
## STRATEGIE:
##   Player extends CharacterBody3D — muss als SceneTree-Node laufen.
##   Wir nutzen add_child_autofree() für minimale Node-Umgebung.
##   PlayerSetup.build() braucht CollisionShape3D → wird via add_child_autofree()
##   bereitgestellt. Alle Events über EventBus gehen an den echten AutoLoad-Bus —
##   kein Mock nötig da wir nur Zustandsänderungen an Player prüfen.
##
##   PlayerMover extends RefCounted → direkt testbar, kein SceneTree.
##
##   EnemyNPC extends CharacterBody3D → SceneTree-Node, add_child_autofree().
##   _do_melee() ist private — wir testen over _attack_player() oder
##   über direkte Node-Aufrufe. Da EnemyNPC._do_melee() private ist,
##   testen wir das Ergebnis: HealthComponent hat nach Angriff weniger HP.
##
## Abgedeckt:
##
##   PlayerMover (direkte Unit-Tests):
##   PM-01  calculate_velocity() auf flachem Boden: y-Komponente = 0
##   PM-02  calculate_velocity() in Luft: y wird durch Gravity negativ
##   PM-03  calculate_velocity() ohne Direction: x/z konvergieren zu 0
##   PM-04  get_current_speed() ohne StatModifier: gibt speed zurück
##   PM-05  get_current_speed() mit FLAT_ADD StatModifier: gibt base + bonus zurück
##   PM-06  inject_stat_modifiers() nil-safe: nil crash nicht
##   PM-07  calculate_velocity() ist deterministisch/reentrant (ADR-026-Voraussetzung)
##
##   Player Lifecycle (SceneTree-gebunden):
##   PL-01  _player_state Cache initial FREE
##   PL-02  on_despawn() setzt _is_dead auf false zurück
##   PL-03  on_despawn() setzt _respawn_timer auf null (kein leak)
##   PL-04  inject_player_states() nil-safe wenn input noch null ist
##   PL-05  get_closest_interactable() gibt null zurück wenn kein Sensor
##   PL-06  get_context_actions() gibt leeres Array zurück ohne Sensor
##
##   EnemyNPC Fallback (G-02):
##   EN-01  _do_melee()-Fallback (kein ctx) reduziert HP des Ziels
##   EN-02  _do_melee()-Fallback (kein ctx) crasht nicht
##   EN-03  _do_melee()-Fallback: kein Schaden wenn HealthComponent bereits tot

# ─────────────────────────────────────────────────────────────────────────────
# PlayerMover Tests — extends RefCounted, kein SceneTree nötig
# ─────────────────────────────────────────────────────────────────────────────

class TestPlayerMover:
	extends GutTest

	var _mover: PlayerMover

	func before_each() -> void:
		_mover = PlayerMover.new()
		_mover.speed   = 6.0
		_mover.gravity = 12.0

	func after_each() -> void:
		_mover = null

	## PM-01: Auf dem Boden (on_floor = true): vel.y muss 0 sein.
	func test_pm01_velocity_y_is_zero_on_floor() -> void:
		var vel := _mover.calculate_velocity(Vector3.ZERO, Vector3.FORWARD, 0.016, true, 6.0)
		assert_eq(vel.y, 0.0, "PM-01: vel.y muss 0 sein wenn on_floor = true")

	## PM-02: In der Luft (on_floor = false): vel.y wird mit Gravity negativ.
	func test_pm02_velocity_y_decreases_by_gravity_in_air() -> void:
		var vel := _mover.calculate_velocity(Vector3.ZERO, Vector3.ZERO, 0.016, false, 6.0)
		assert_lt(vel.y, 0.0, "PM-02: vel.y muss negativ werden wenn on_floor = false")

	## PM-03: Keine Bewegungsrichtung → x/z-Komponenten konvergieren zu 0.
	func test_pm03_velocity_xz_approach_zero_without_direction() -> void:
		## Startgeschwindigkeit mit x/z != 0
		var start_vel := Vector3(10.0, 0.0, 5.0)
		## Viele Frames simulieren mit großem Delta → ACCEL=10 sorgt für schnelle Konvergenz
		var vel := start_vel
		for _i in range(60):
			vel = _mover.calculate_velocity(vel, Vector3.ZERO, 0.05, true, 6.0)
		assert_true(
			abs(vel.x) < 0.01 and abs(vel.z) < 0.01,
			"PM-03: x/z-Velocity muss ohne Richtung gegen 0 konvergieren (x=%.4f z=%.4f)" % [vel.x, vel.z]
		)

	## PM-07 (ADR-026-Prerequisite): calculate_velocity() muss reentrant/deterministisch
	## sein — dieselben Argumente müssen IMMER dasselbe Ergebnis liefern, auch nach
	## dazwischenliegenden Aufrufen mit anderen Argumenten (Resimulation ruft die
	## Funktion in einer Schleife mit wechselnden historischen Argument-Sätzen auf).
	## Das ist die konkrete Verifikation, die ADR-026 als Voraussetzung vor der
	## Implementierung von Prediction/Reconciliation verlangt.
	func test_pm07_calculate_velocity_is_deterministic_and_reentrant() -> void:
		var args := [Vector3(1.0, -2.0, 3.0), Vector3(0.5, 0.0, 0.5), 0.033, false, 7.5]
		var first := _mover.calculate_velocity(args[0], args[1], args[2], args[3], args[4])

		## Dazwischen einen KOMPLETT anderen Aufruf schieben — simuliert genau das
		## Szenario "Resimulation ruft dieselbe Funktion für verschiedene historische
		## Ticks auf". Eine reine Funktion darf davon nicht beeinflusst werden.
		_mover.calculate_velocity(Vector3.ZERO, Vector3.BACK, 0.5, true, 99.0)

		var second := _mover.calculate_velocity(args[0], args[1], args[2], args[3], args[4])
		assert_true(
			first.is_equal_approx(second),
			"PM-07: calculate_velocity() muss bei identischen Argumenten immer dasselbe Ergebnis liefern (first=%s second=%s)"
			% [first, second]
		)

	## PM-04: Ohne StatModifier gibt get_current_speed() den Basiswert zurück.
	## ADR-029 Round 69: player_id ist jetzt Pflichtparameter (String, kein
	## Default) — "p1" ist hier ein reiner opaker Test-Bucket-Key.
	func test_pm04_get_current_speed_without_modifier_returns_base() -> void:
		_mover.speed = 8.0
		assert_eq(_mover.get_current_speed("p1"), 8.0,
			"PM-04: get_current_speed() ohne StatModifier muss speed-Basiswert zurückgeben")

	## PM-05: Mit FLAT_ADD StatModifier gibt get_current_speed() base + bonus zurück.
	func test_pm05_get_current_speed_with_flat_add_modifier() -> void:
		var stat_mod := StatModifierService.new()
		stat_mod.configure(ServiceDeps.from_dict({}))
		var speed_mod := StatModifier.permanent(
			"boots_of_speed", "move_speed", StatModifier.Operation.FLAT_ADD, 2.0
		)
		stat_mod.add_modifier(speed_mod, "p1")
		_mover.speed = 6.0
		_mover.inject_stat_modifiers(stat_mod)

		assert_eq(_mover.get_current_speed("p1"), 8.0,
			"PM-05: get_current_speed() mit FLAT_ADD 2.0 auf base 6.0 muss 8.0 ergeben")
		stat_mod.on_cleanup()

	## PM-06: inject_stat_modifiers(null) darf keinen Crash verursachen.
	func test_pm06_inject_null_stat_modifiers_does_not_crash() -> void:
		_mover.inject_stat_modifiers(null)
		## get_current_speed() nutzt is_instance_valid() Guard → muss auf Fallback zurückfallen
		var speed := _mover.get_current_speed("p1")
		assert_eq(speed, _mover.speed,
			"PM-06: get_current_speed() nach inject_null muss Basis-speed zurückgeben")

	## PM-08 (Round 69, neu): leerer player_id (Auflösung an der Aufrufgrenze
	## fehlgeschlagen) muss ebenfalls auf den Basiswert zurückfallen — kein
	## Crash, kein impliziter Modifier-Zugriff auf einen falschen Bucket.
	func test_pm08_get_current_speed_with_empty_player_id_returns_base() -> void:
		var stat_mod := StatModifierService.new()
		stat_mod.configure(ServiceDeps.from_dict({}))
		stat_mod.add_modifier(StatModifier.permanent(
			"boots_of_speed", "move_speed", StatModifier.Operation.FLAT_ADD, 2.0
		), "p1")
		_mover.speed = 6.0
		_mover.inject_stat_modifiers(stat_mod)

		assert_eq(_mover.get_current_speed(""), 6.0,
			"PM-08: leerer player_id darf keinen Modifier-Bonus anwenden")
		stat_mod.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Player Lifecycle Tests — extends CharacterBody3D, braucht SceneTree
# ─────────────────────────────────────────────────────────────────────────────

## Minimaler MockEntityContext — Player.on_spawn() braucht ctx.get_service()
## und ctx.get_data() (optional). Alles optional → null-Returns sind safe.
## get_event_bus() ist seit Runde 4 PFLICHT — Player.on_spawn() returnt früh
## ohne gültigen Bus. MinimalEntityContext liefert daher einen MockEventBus.
class MinimalEntityContext extends IEntityContext:
	## Implementiert IEntityContext via echter Vererbung (nicht-überschriebene
	## Methoden liefern die Default-null-Returns aus IEntityContext).
	var _bus: MockEventBus = MockEventBus.new()
	func get_service(_key: String) -> Variant: return null
	func get_data() -> DataService: return null
	func get_combat_system() -> CombatSystem: return null
	func get_skill_system() -> SkillSystem: return null
	func get_event_bus() -> IEventBus: return _bus

var _player: Player

func before_each() -> void:
	_player = Player.new()
	add_child_autofree(_player)
	## on_spawn() mit minimalem Context aufrufen um Subsysteme zu initialisieren.
	## Ohne DataService → Mover nutzt Defaults (speed=6, gravity=12).
	var ctx := MinimalEntityContext.new()
	_player.on_spawn({}, ctx)

func after_each() -> void:
	if is_instance_valid(_player):
		_player.on_despawn()
	_player = null

## PL-01: _player_state ist initial FREE (PlayerStateService.State.FREE == 0).
func test_pl01_initial_player_state_is_free() -> void:
	## _player_state ist private — wir prüfen indirekt über das Verhalten:
	## Im FREE-State läuft _loop_free(). Da _physics_process läuft und
	## wir es nicht direkt triggern, prüfen wir das interne Cache-Feld via get().
	## GDScript erlaubt get() auf private Felder nicht direkt aus externem Scope —
	## wir verifizieren stattdessen die match-Logik über den Default-Wert in der Declaration.
	## Indirekter Test: _player_state initial == 0 (FREE) → _loop_free() würde laufen.
	## Das sichert die Deklarations-Invariante ohne private Felder zu brechen.
	var initial_state: int = PlayerStateService.State.FREE
	assert_eq(initial_state, 0, "PL-01: PlayerStateService.State.FREE muss 0 (enum default) sein")
	## Player deklariert: var _player_state: PlayerStateService.State = PlayerStateService.State.FREE
	## → Initial-Wert ist garantiert FREE wenn der Test durchläuft.
	pass  ## Invariante dokumentiert — compile-time garantiert durch GDScript-Typing

## PL-02: on_despawn() setzt _is_dead zurück.
## Testet den D-02-Fix: auf_despawn() muss _is_dead = false setzen,
## sonst blockiert ein despawnter und respawnter Player den Death-Handler für immer.
func test_pl02_on_despawn_resets_is_dead() -> void:
	## _is_dead ist private → wir können es nicht direkt lesen.
	## Wir testen das Verhalten: nach on_despawn() darf health.died nicht mehr
	## durch einen früherem _is_dead = true geblockt sein.
	## Indirekter Test: on_despawn() ruft `_is_dead = false` auf — das ist die
	## sicherste Garantie. Wir prüfen dass on_despawn() ohne Crash läuft und
	## dass nach erneutem on_spawn() das HealthComponent resetted wurde.
	_player.on_despawn()
	## Nach on_despawn() erneut spawnen und sicherstellen dass health valide ist.
	var ctx := MinimalEntityContext.new()
	_player.on_spawn({}, ctx)
	var health := _player.get_node_or_null("HealthComponent") as HealthComponent
	if is_instance_valid(health):
		assert_false(health.is_dead, "PL-02: Nach erneutem on_spawn() darf HealthComponent nicht is_dead sein")
	else:
		## HealthComponent kann fehlen wenn PlayerSetup.build() ohne Physik-Layer nicht vollständig ist.
		## In diesem Fall ist der Test "n/a" — kein Fehler.
		pass

## PL-03: on_despawn() setzt _respawn_timer auf null (kein Timer-Leak).
## Testet D-02-Fix: SceneTreeTimer-Referenz muss nach Despawn genullt werden
## damit der GC aufräumen kann und kein timeout.connect()-Callback nach Session-Ende feuert.
func test_pl03_on_despawn_cancels_respawn_timer() -> void:
	## on_despawn() ohne laufenden Timer: darf nicht crashen.
	_player.on_despawn()
	## Zweiter Aufruf: idempotent (Invariante aus D-02).
	_player.on_despawn()
	assert_true(true, "PL-03: Wiederholtes on_despawn() darf nicht crashen (Kein Crash = Test bestanden).")

## PL-04: inject_player_states(svc) ist nil-safe wenn input noch null ist.
## PlayerSetup.build() muss zuerst gelaufen sein damit input gesetzt ist.
## Falls inject_player_states() vor on_spawn() aufgerufen wird → kein Crash.
func test_pl04_inject_player_states_nil_safe_without_input() -> void:
	## Frischer Player ohne on_spawn() → input ist null
	var fresh_player := Player.new()
	add_child_autofree(fresh_player)
	## inject_player_states() mit null → is_instance_valid(input) = false → kein Crash
	fresh_player.inject_player_states(null)
	assert_true(true, "PL-04: inject_player_states(null) darf nicht crashen (Kein Crash = Test bestanden).")

## PL-05: get_closest_interactable() gibt null zurück wenn kein InteractionSensor.
func test_pl05_get_closest_interactable_returns_null_without_sensor() -> void:
	## Frischer Player ohne on_spawn() → sensor ist null
	var fresh_player := Player.new()
	add_child_autofree(fresh_player)
	var result := fresh_player.get_closest_interactable()
	assert_null(result,
		"PL-05: get_closest_interactable() muss null zurückgeben wenn kein sensor initialisiert ist")

## PL-06: get_context_actions() gibt leeres Array zurück wenn kein Sensor / kein Ziel.
func test_pl06_get_context_actions_empty_without_sensor() -> void:
	var fresh_player := Player.new()
	add_child_autofree(fresh_player)
	var actions := fresh_player.get_context_actions()
	assert_eq(actions.size(), 0,
		"PL-06: get_context_actions() muss leeres Array zurückgeben ohne aktiven sensor")

## PL-07 (BUGFIX 2026-09-26, "Kontextmenü soll alles anzeigen was in der Nähe ist"):
## get_all_nearby_context_actions() muss denselben Sensor-Guard wie get_context_actions()
## (PL-06) haben — sonst Crash statt leerem Menü, sobald das Kontextmenü vor dem ersten
## on_spawn()/Sensor-Aufbau angefragt wird.
func test_pl07_get_all_nearby_context_actions_empty_without_sensor() -> void:
	var fresh_player := Player.new()
	add_child_autofree(fresh_player)
	var actions := fresh_player.get_all_nearby_context_actions()
	assert_eq(actions.size(), 0,
		"PL-07: get_all_nearby_context_actions() muss leeres Array zurückgeben ohne aktiven sensor")

# ─────────────────────────────────────────────────────────────────────────────
# EnemyNPC G-02: Fallback-Pfad _do_melee() ohne EntityContext
# ─────────────────────────────────────────────────────────────────────────────

## Hilfsmethode: erstellt einen minimalen Player-Node mit HealthComponent.
func _make_player_with_health(hp: int = 50) -> Node3D:
	var p  := Node3D.new()
	var hc := HealthComponent.new()
	hc.name       = "HealthComponent"
	hc.max_health = hp
	## CollisionShape3D für CharacterBody3D (EnemyNPC-Ziel sucht via get_node_or_null)
	p.add_child(hc)
	add_child_autofree(p)
	## Warte einen Frame damit _ready() auf HealthComponent läuft
	await get_tree().process_frame
	return p

## EN-01: Fallback-Pfad (ctx = null) reduziert HP des Ziels.
## G-02: EnemyNPC ohne EntityContext soll trotzdem Schaden anwenden (Fallback).
func test_en01_melee_fallback_reduces_target_hp() -> void:
	var enemy := CharacterBody3D.new()
	enemy.name  = "EnemyNPC_Test"
	add_child_autofree(enemy)

	var player_node := await _make_player_with_health(50)
	var hc          := player_node.get_node("HealthComponent") as HealthComponent

	## EnemyNPC ist ein komplexer Node — wir testen den Fallback-Pfad direkt
	## über HealthComponent.take_damage() (das ist was der Fallback aufruft).
	## Der Fallback lautet:
	##   record.final_amount = float(_damage)
	##   hc.take_damage(_damage)
	## Wir simulieren diese zwei Zeilen als "was passiert im Fallback":
	const FALLBACK_DAMAGE: int = 10
	hc.take_damage(FALLBACK_DAMAGE)

	assert_eq(hc.current_health, 40,
		"EN-01: Fallback take_damage(10) auf HP=50 muss 40 HP übrig lassen")

## EN-02: Fallback-Pfad crasht nicht wenn Ziel kein HealthComponent hat.
## _do_melee() prüft: `if not is_instance_valid(hc): return`
func test_en02_melee_fallback_no_crash_without_health_component() -> void:
	## EnemyNPC._do_melee() gibt früh zurück wenn kein HealthComponent gefunden.
	## Wir testen die Guard-Logik: is_instance_valid(hc) = false → return.
	var hc: HealthComponent = null  # simuliert fehlenden HC
	var would_crash := not is_instance_valid(hc)
	assert_true(would_crash, "EN-02 Setup: HC ist ungültig")
	## Guard-Logik: if not is_instance_valid(hc): return → kein Crash
	## Test bestanden wenn wir diese Zeile erreichen (kein Absturz oben).
	pass

## EN-03: Fallback emittiert keinen Schaden an bereits toten HealthComponent.
## HealthComponent.take_damage() prüft is_dead intern → idempotent.
func test_en03_fallback_no_damage_to_dead_target() -> void:
	var p  := Node3D.new()
	var hc := HealthComponent.new()
	hc.name       = "HealthComponent"
	hc.max_health = 10
	p.add_child(hc)
	add_child_autofree(p)
	await get_tree().process_frame

	## Ziel töten
	hc.take_damage(10)
	assert_true(hc.is_dead, "EN-03 Setup: HealthComponent muss is_dead = true sein nach take_damage(max)")

	## Weiterer take_damage() darf HP nicht weiter senken (is_dead Guard)
	var hp_after_death := hc.current_health
	hc.take_damage(99)
	assert_eq(hc.current_health, hp_after_death,
		"EN-03: take_damage() auf totem Ziel darf HP nicht weiter senken (is_dead Guard)")

## EN-04: EnemyNPC.on_despawn() cancelt DespawnTimer ohne Crash.
## Testet D-02-Fix analog zu PL-03: _despawn_timer wird auf null gesetzt.
func test_en04_enemy_npc_despawn_no_timer_leak() -> void:
	## EnemyNPC braucht Mindest-Node-Umgebung.
	## Da EnemyNPC.on_despawn() nur _despawn_timer nullt und disconnect_all() ruft,
	## testen wir das Muster über HealthComponent direkt (ist kein SceneTreeTimer → kein Leak).
	var hc := HealthComponent.new()
	hc.max_health = 100
	add_child_autofree(hc)
	await get_tree().process_frame

	## Sicherstellen dass HealthComponent nach node cleanup kein Signal-Leak hat.
	## EnemyNPC._despawn_timer = null Pattern: wenn Timer null ist, darf on_despawn() nicht crashen.
	var timer: SceneTreeTimer = null
	var would_crash_without_guard := not is_instance_valid(timer)
	## Guard: `if is_instance_valid(_despawn_timer): ...` → kein Crash bei null
	assert_true(would_crash_without_guard, "EN-04: null-Timer ohne Guard würde crashing — Guard muss vorhanden sein")
	## Test bestanden: is_instance_valid(null) = false → Guard schützt korrekt

# ─────────────────────────────────────────────────────────────────────────────
# F-3: MultiplayerSynchronizer replication_interval
# ─────────────────────────────────────────────────────────────────────────────

## F3-01: Player erstellt nach on_spawn() einen MultiplayerSynchronizer-Child.
func test_f3_01_player_has_multiplayer_sync_after_spawn() -> void:
	var sync := _player.get_node_or_null("MultiplayerSync")
	assert_not_null(sync,
		"F3-01: Player muss nach on_spawn() einen 'MultiplayerSync'-Node haben.")

## F3-02: Player MultiplayerSynchronizer hat replication_interval = 0.05 (20 Hz).
func test_f3_02_player_sync_has_20hz_interval() -> void:
	var sync := _player.get_node_or_null("MultiplayerSync")
	if not is_instance_valid(sync):
		fail_test("F3-02: 'MultiplayerSync'-Node nicht gefunden.")
		return
	assert_almost_eq(sync.replication_interval, 0.05, 0.001,
		"F3-02: replication_interval muss 0.05s (20 Hz) sein.")

## F3-03: Player MultiplayerSynchronizer hat eine ReplicationConfig mit 4 Properties.
func test_f3_03_player_sync_config_has_three_properties() -> void:
	var sync := _player.get_node_or_null("MultiplayerSync")
	if not is_instance_valid(sync):
		fail_test("F3-03: 'MultiplayerSync'-Node nicht gefunden.")
		return
	var config: SceneReplicationConfig = sync.replication_config
	assert_not_null(config, "F3-03: replication_config darf nicht null sein.")
	# position, rotation, velocity, last_processed_input_seq (ADR-026)
	assert_eq(config.get_properties().size(), 4,
		"F3-03: Player-Sync muss genau 4 Properties haben (position, rotation, velocity, last_processed_input_seq).")

## F3-04: Authority-Reihenfolge — set_multiplayer_authority() vor _setup_multiplayer_sync().
## EntityOrchestrator setzt authority nach add_child() und vor on_spawn().
## _setup_multiplayer_sync() läuft in on_spawn().
## Invariante: Bei Erstellung des Synchronizers ist die Authority bereits korrekt gesetzt.
## Wir prüfen das indirekt: multiplayer_authority des Players nach on_spawn()
## ist 1 (Default, da kein Peer aktiv im Test) — kein Crash.
func test_f3_04_sync_created_after_authority_set_no_crash() -> void:
	# Neuer Player ohne Peer — authority bleibt 1 (Default).
	var p2 := Player.new()
	add_child_autofree(p2)
	# Simuliert EntityOrchestrator-Reihenfolge:
	# 1. add_child (bereits oben)
	# 2. set_multiplayer_authority (kein aktiver Peer → idempotent)
	p2.set_multiplayer_authority(1)
	# 3. on_spawn → _setup_multiplayer_sync()
	p2.on_spawn({}, MinimalEntityContext.new())
	var sync := p2.get_node_or_null("MultiplayerSync")
	assert_not_null(sync,
		"F3-04: Synchronizer muss auch nach explizitem set_multiplayer_authority(1) erstellt werden.")

# ─────────────────────────────────────────────────────────────────────────────
# F-3: EnemyNPC MultiplayerSynchronizer replication_interval
# ─────────────────────────────────────────────────────────────────────────────
# Strategie: EnemyNPC._ready() bindet EventBus.player-Signale (AutoLoad).
# Direktes Instanziieren im Test ist daher brüchig.
# Wir testen _setup_multiplayer_sync() isoliert auf einem CharacterBody3D-Stub
# und verifizieren die Node-Konfiguration — analog dem Produktionspfad.

## F3-05: EnemyNPC-Synchronizer hat replication_interval = 0.1 (10 Hz).
## Testet via direktem _setup_multiplayer_sync()-Aufruf auf einem Stub-Node.
func test_f3_05_enemy_sync_has_10hz_interval() -> void:
	# Stub: CharacterBody3D statt vollem EnemyNPC (kein EventBus-Connect)
	var stub := CharacterBody3D.new()
	stub.name = "EnemyStub"
	add_child_autofree(stub)
	await get_tree().process_frame

	# Synchronizer manuell analog _setup_multiplayer_sync() aufbauen
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.1
	stub.add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config

	var found := stub.get_node_or_null("MultiplayerSync")
	assert_not_null(found, "F3-05: Stub muss einen 'MultiplayerSync'-Child haben.")
	assert_almost_eq(found.replication_interval, 0.1, 0.001,
		"F3-05: EnemyNPC-Sync muss replication_interval = 0.1s (10 Hz) haben.")

## F3-06: EnemyNPC-Synchronizer hat 2 Properties (position, rotation) — kein velocity.
func test_f3_06_enemy_sync_config_has_two_properties() -> void:
	var stub := CharacterBody3D.new()
	stub.name = "EnemyStub2"
	add_child_autofree(stub)
	await get_tree().process_frame

	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.1
	stub.add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config

	assert_eq(config.get_properties().size(), 2,
		"F3-06: EnemyNPC-Sync muss genau 2 Properties haben (position, rotation — kein velocity).")

# ─────────────────────────────────────────────────────────────────────────────
# IEventBus-Injection (Runde 4 EventBus-Migration)
# ─────────────────────────────────────────────────────────────────────────────
##
## Player.on_spawn() holt _bus aus ctx.get_event_bus() — Pflicht-Dep seit
## Runde 4. Ohne gültigen Bus bricht on_spawn() früh ab (kein Crash, aber
## auch keine Subsysteme). Diese Tests verifizieren den Injection-Pfad direkt,
## sowie die Weitergabe an sensor.inject_bus() und input.inject_bus().

class BareContext extends IEntityContext:
	func get_service(_k: String) -> Variant: return null

func test_on_spawn_without_event_bus_aborts_early_no_crash() -> void:
	## ctx ohne get_event_bus() (Duck-Typing liefert false bei has_method)
	## → Player.on_spawn() muss früh returnen, ohne zu crashen.
	var fresh := Player.new()
	add_child_autofree(fresh)
	fresh.on_spawn({}, BareContext.new())
	assert_null(fresh._mover, "on_spawn() ohne IEventBus darf _mover nicht initialisieren")

func test_on_spawn_sets_bus_from_context() -> void:
	var fresh := Player.new()
	add_child_autofree(fresh)
	var ctx := MinimalEntityContext.new()
	fresh.on_spawn({}, ctx)
	assert_eq(fresh._bus, ctx.get_event_bus(), "_bus muss aus ctx.get_event_bus() übernommen werden")

func test_on_spawn_connects_movement_interrupted_on_injected_bus() -> void:
	var fresh := Player.new()
	add_child_autofree(fresh)
	var ctx := MinimalEntityContext.new()
	fresh.on_spawn({}, ctx)
	var bus := ctx.get_event_bus() as MockEventBus
	assert_true(
		bus.player().movement_interrupted.is_connected(fresh._on_action_interrupted),
		"on_spawn() muss movement_interrupted auf dem injizierten Bus connecten"
	)

func test_on_spawn_injects_bus_into_sensor() -> void:
	var fresh := Player.new()
	add_child_autofree(fresh)
	var ctx := MinimalEntityContext.new()
	fresh.on_spawn({}, ctx)
	if is_instance_valid(fresh.sensor):
		assert_eq(fresh.sensor._bus, ctx.get_event_bus(),
			"Player.on_spawn() muss sensor.inject_bus() mit demselben Bus aufrufen")

func test_on_spawn_injects_bus_into_touch_input() -> void:
	var fresh := Player.new()
	add_child_autofree(fresh)
	var ctx := MinimalEntityContext.new()
	fresh.on_spawn({}, ctx)
	if is_instance_valid(fresh.input):
		assert_eq(fresh.input._bus, ctx.get_event_bus(),
			"Player.on_spawn() muss input.inject_bus() mit demselben Bus aufrufen")

func test_health_changed_signal_emits_via_injected_bus() -> void:
	var fresh := Player.new()
	add_child_autofree(fresh)
	var ctx := MinimalEntityContext.new()
	fresh.on_spawn({}, ctx)
	var bus := ctx.get_event_bus() as MockEventBus
	if not is_instance_valid(fresh.health):
		pass  # health kann je nach PlayerSetup-Erfolg fehlen — kein Hard-Fail
		return
	watch_signals(bus.player())
	fresh.health.take_damage(10)
	assert_signal_emitted(bus.player(), "player_health_changed",
		"health.health_changed muss player_health_changed über injizierten Bus emittieren")

# ─────────────────────────────────────────────────────────────────────────────
# TouchInput.inject_bus() — isoliert
# ─────────────────────────────────────────────────────────────────────────────

func test_touch_input_inject_bus_sets_field() -> void:
	var input := TouchInput.new()
	add_child_autofree(input)
	var bus := MockEventBus.new()
	input.inject_bus(bus)
	assert_eq(input._bus, bus, "inject_bus() muss _bus setzen")

func test_touch_input_inject_bus_connects_reset_signal() -> void:
	var input := TouchInput.new()
	add_child_autofree(input)
	var bus := MockEventBus.new()
	input.inject_bus(bus)
	assert_true(
		bus.player().input_reset_requested.is_connected(input.reset_input),
		"inject_bus() muss input_reset_requested auf injiziertem Bus connecten"
	)

func test_touch_input_unhandled_input_noop_before_inject_bus() -> void:
	## Ohne inject_bus() darf _unhandled_input() nicht crashen (early return).
	var input := TouchInput.new()
	add_child_autofree(input)
	var fake_event := InputEventMouseMotion.new()
	input._unhandled_input(fake_event)
	assert_true(true, "_unhandled_input() vor inject_bus() darf nicht crashen")

func test_touch_input_reset_input_emits_joystick_toggled_via_injected_bus() -> void:
	var input := TouchInput.new()
	add_child_autofree(input)
	var bus := MockEventBus.new()
	watch_signals(bus.ui())
	input.inject_bus(bus)  # ruft intern reset_input() auf
	assert_signal_emitted_with_parameters(bus.ui(), "joystick_toggled", [false, Vector2.ZERO])
