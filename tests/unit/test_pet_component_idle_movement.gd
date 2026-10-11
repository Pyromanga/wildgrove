# res://tests/unit/test_pet_component_idle_movement.gd
extends GutTest

## Unit-Tests für PetComponent._apply_idle_movement() — BUGFIX ("Pets bauen/
## sammeln/kämpfen nur ab, wenn der Besitzer von Anfang an in der Nähe steht
## und sich nicht bewegt"). Reine Positions-/velocity-Assertions, kein
## SceneTree/Physik-Schritt nötig — _apply_idle_movement() liest/schreibt nur
## global_position/velocity/_player_ref/_abilities, alles ohne _ready().

var _pet: PetComponent
var _owner: Node3D

func before_each() -> void:
	_pet = autofree(PetComponent.new())
	_owner = autofree(Node3D.new())
	_pet._player_ref = _owner

func test_pet_without_abilities_follows_tightly_even_within_leash() -> void:
	# Reiner Begleiter (keine Fähigkeiten) — altes, enges Folgeverhalten bleibt.
	_pet._abilities = []
	_pet.global_position = Vector3(5, 0, 0)  # 5m vom Besitzer — weiter als _follow_distance (2.5m)
	_owner.global_position = Vector3.ZERO

	_pet._apply_idle_movement(0.1)

	assert_true(_pet.velocity.length() > 0.0,
		"Ein Pet ohne Fähigkeiten muss sich schon innerhalb von LEASH_RADIUS Richtung Besitzer bewegen")

func test_pet_with_ability_stays_put_within_leash() -> void:
	# Kern des Bugfixes: MIT Fähigkeit bleibt das Pet innerhalb der Leine stehen,
	# statt sich sofort auf _follow_distance an den Besitzer zu kleben.
	_pet._abilities = [PetAbilities.GATHERING]
	_pet.global_position = Vector3(10, 0, 0)  # 10m — weiter als _follow_distance, aber < LEASH_RADIUS (16m)
	_owner.global_position = Vector3.ZERO
	_pet.velocity = Vector3(3, 0, 0)  # simuliert vorherige Bewegung

	# Mehrere Schritte statt einem einzelnen — move_toward() bremst pro Frame nur
	# graduell ab (siehe _apply_idle_movement()), erst nach ein paar Frames ist
	# die Geschwindigkeit tatsächlich bei ~0 angekommen.
	for i in range(20):
		_pet._apply_idle_movement(0.1)

	assert_almost_eq(_pet.velocity.x, 0.0, 0.1,
		"Innerhalb der Leine muss das Pet abbremsen/stehen bleiben, nicht Richtung Besitzer beschleunigen")

func test_pet_with_ability_returns_once_beyond_leash() -> void:
	_pet._abilities = [PetAbilities.GATHERING]
	_pet.global_position = Vector3(20, 0, 0)  # > LEASH_RADIUS (16m)
	_owner.global_position = Vector3.ZERO

	_pet._apply_idle_movement(0.1)

	assert_true(_pet.velocity.x < 0.0,
		"Außerhalb der Leine muss das Pet trotzdem aktiv zum Besitzer zurücklaufen")

func test_leash_radius_is_larger_than_follow_distance() -> void:
	# Strukturelle Absicherung: die Leine MUSS großzügiger sein als das enge
	# Folgeverhalten, sonst wäre der Bugfix wirkungslos.
	assert_true(PetComponent.LEASH_RADIUS > _pet._follow_distance)

# ─────────────────────────────────────────────
# BUGFIX (2026-10-02, per Logging nachgewiesen): _steer_toward() blieb knapp
# AUSSERHALB von stop_distance für immer hängen (asymptotische Abbremsung,
# siehe _steer_toward()-Kommentar) — das Pet erreichte has_arrived_at_
# movement_target() nie, obwohl es optisch direkt vor dem Ziel stand.
# ─────────────────────────────────────────────

func test_steer_toward_eventually_reaches_stop_distance_from_just_outside() -> void:
	# Exakt das reproduzierte Szenario aus dem Log: Pet 0.0004m außerhalb der
	# Ankunfts-Schwelle (stop_distance=2.2) — vorher blieb es dort für IMMER
	# stehen (siehe Log vom 2026-10-02, 25+ Sekunden unverändert).
	var target := Vector3(2.2004, 0, 0)
	_pet.global_position = Vector3.ZERO
	_pet.velocity = Vector3.ZERO

	var reached := false
	for i in range(300):  # 5 Sekunden bei 0.1s-Schritten — vorher: nie.
		_pet._steer_toward(target, 0.1, 2.2)
		_pet.global_position += _pet.velocity * 0.1  # move_and_slide() simulieren
		if _pet.global_position.distance_to(target) <= 2.2:
			reached = true
			break

	assert_true(reached, "Pet muss stop_distance irgendwann TATSÄCHLICH unterschreiten, nicht nur annähern")

func test_steer_toward_maintains_minimum_speed_near_stop_distance() -> void:
	# Kern des Fixes: t darf nicht gegen 0 laufen, solange dist > stop_distance.
	_pet.global_position = Vector3(2.21, 0, 0)  # 1cm außerhalb von stop_distance=2.2
	_pet.velocity = Vector3.ZERO

	_pet._steer_toward(Vector3.ZERO, 0.1, 2.2)

	# Bei der ALTEN Formel (t = (dist-stop_distance)/3.0 ohne Untergrenze) wäre
	# die Zielgeschwindigkeit hier ~0.013 m/s gewesen — nicht Null, aber nahe
	# genug, dass Boden-/Physik-Rundung die Bewegung faktisch verschluckt hat.
	# Mit der Untergrenze (0.2 * _speed) muss die tatsächliche Geschwindigkeit
	# deutlich darüber liegen.
	assert_true(_pet.velocity.length() >= 0.2 * _pet._speed - 0.01,
		"Geschwindigkeit darf kurz vor stop_distance nicht gegen 0 laufen")
