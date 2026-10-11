# res://tests/unit/test_enemy_spawner.gd
extends GutTest

## Unit-Tests für EnemySpawner (reine Platzierungslogik, RefCounted).
##
## WICHTIGE Einschränkung: spawn_animals()/spawn_enemies() seeden ihren
## RandomNumberGenerator intern aus Time.get_unix_time_from_system() — es
## gibt KEINEN Weg von außen, den Seed zu injizieren. Exakte Positionen oder
## exakte Aufruf-Anzahlen sind deshalb NICHT deterministisch testbar (ein
## Test der "genau N Aufrufe" erwartet, wäre bei ungünstigem Zufall flaky).
##
## Stattdessen: Tests, die für JEDEN möglichen Zufallswert gelten müssen
## (Invarianten), plus ein paar Grenzfälle, die durch einen Stub-
## TerrainField komplett DETERMINISTISCH gemacht werden (z.B. "Terrain
## lehnt jede Position ab" -> IMMER 0 Aufrufe, unabhängig vom Zufall).
##
## Abgedeckt:
##   - Terrain lehnt jede Höhe ab (h < 0.3 bzw. h == 0.3 exakt an der
##     Grenze) -> deterministisch 0 Spawns, für Tiere UND Feinde
##   - Ohne TerrainField (null): Höhen-Check komplett übersprungen,
##     candidate.y bleibt 0.0 (Tiere) bzw. wird zum Default 1.5 (Feinde) —
##     beides deterministisch prüfbar unabhängig von x/z
##   - Mit gültigem TerrainField: jede tatsächlich gespawnte Position hat
##     candidate.y == exakt der von get_height_at() gelieferte Wert
##   - Radius-Invariante: jede gespawnte Tier-Position hat length() >= 8.0,
##     jede Feind-Position Vector2(x,z).length() >= 10.0 (beides über ALLE
##     tatsächlich aufgezeichneten Aufrufe, egal wie viele es wurden)
##   - Mindestabstand-Invariante: keine zwei Tier-Positionen näher beieinander
##     als der min_dist des SPÄTER platzierten Typs (so garantiert es der Code)
##   - type-Werte sind immer aus der erwarteten Menge (deer/rabbit/boar/fox/
##     squirrel/sheep bzw. goblin/skeleton)

const ANIMAL_MIN_DIST := {
	"deer": 6.0, "rabbit": 3.0, "boar": 7.0,
	"fox": 5.0, "squirrel": 2.5, "sheep": 4.0,
}


class StubEntityOrchestrator extends EntityOrchestrator:
	var calls: Array = []  ## [[type_id, position], ...] in Aufrufreihenfolge
	func spawn_entity(type_id: String, position: Vector3, _config: Dictionary = {}, _peer_id: int = 1) -> Node3D:
		calls.append([type_id, position])
		return null


class StubTerrainField extends TerrainField:
	var fixed_height: float = 1.0
	func get_height_at(_x: float, _z: float) -> float:
		return fixed_height


var _orchestrator: StubEntityOrchestrator
var _terrain: StubTerrainField


func before_each() -> void:
	_orchestrator = StubEntityOrchestrator.new()
	add_child_autofree(_orchestrator)
	_terrain = StubTerrainField.new()


func after_each() -> void:
	_orchestrator = null
	_terrain = null


# ─────────────────────────────────────────────
# Terrain lehnt jede Position ab -> deterministisch 0 Spawns
# ─────────────────────────────────────────────

func test_spawn_animals_zero_calls_when_terrain_always_too_low() -> void:
	_terrain.fixed_height = 0.0  # < 0.3 -> jeder Kandidat wird abgelehnt
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_animals()
	assert_eq(_orchestrator.calls.size(), 0)

func test_spawn_animals_zero_calls_just_below_height_boundary() -> void:
	_terrain.fixed_height = 0.29999
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_animals()
	assert_eq(_orchestrator.calls.size(), 0)

func test_spawn_enemies_zero_calls_at_exact_height_boundary() -> void:
	_terrain.fixed_height = 0.3  # Code prüft "if h > 0.3" -> bei genau 0.3 FALSE -> abgelehnt
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_enemies()
	assert_eq(_orchestrator.calls.size(), 0)

func test_spawn_enemies_zero_calls_when_terrain_too_low() -> void:
	_terrain.fixed_height = 0.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_enemies()
	assert_eq(_orchestrator.calls.size(), 0)


# ─────────────────────────────────────────────
# Ohne TerrainField (null) — Höhen-Check komplett übersprungen
# ─────────────────────────────────────────────

func test_spawn_animals_without_terrain_uses_y_zero() -> void:
	var spawner := EnemySpawner.new(_orchestrator, null)
	spawner.spawn_animals()
	for call in _orchestrator.calls:
		var pos: Vector3 = call[1]
		assert_eq(pos.y, 0.0, "Ohne Terrain bleibt candidate.y beim Initialwert 0.0.")

func test_spawn_enemies_without_terrain_uses_default_height() -> void:
	var spawner := EnemySpawner.new(_orchestrator, null)
	spawner.spawn_enemies()
	for call in _orchestrator.calls:
		var pos: Vector3 = call[1]
		assert_eq(pos.y, 1.5, "Ohne Terrain greift der Code-Default h=1.5.")


# ─────────────────────────────────────────────
# Mit gültigem Terrain: jede gespawnte Position übernimmt EXAKT dessen Höhe
# ─────────────────────────────────────────────

func test_spawn_animals_uses_terrain_height_for_every_spawn() -> void:
	_terrain.fixed_height = 4.2
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_animals()
	assert_true(_orchestrator.calls.size() > 0, "Bei h=4.2 (weit über der 0.3-Grenze) sollte mind. etwas platziert werden.")
	for call in _orchestrator.calls:
		var pos: Vector3 = call[1]
		assert_almost_eq(pos.y, 4.2, 0.0001, "Vector3.y ist float32 — 4.2 (double-Literal) verliert beim Speichern Präzision.")

func test_spawn_enemies_uses_terrain_height_for_every_spawn() -> void:
	_terrain.fixed_height = 4.2
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_enemies()
	for call in _orchestrator.calls:
		var pos: Vector3 = call[1]
		assert_almost_eq(pos.y, 4.2, 0.0001, "Vector3.y ist float32 — 4.2 (double-Literal) verliert beim Speichern Präzision.")


# ─────────────────────────────────────────────
# Radius-Invarianten (gelten für JEDEN Zufallswert)
# ─────────────────────────────────────────────

func test_spawn_animals_every_position_is_outside_center_radius() -> void:
	_terrain.fixed_height = 1.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_animals()
	for call in _orchestrator.calls:
		var pos: Vector3 = call[1]
		var flat := Vector3(pos.x, 0.0, pos.z)
		assert_true(flat.length() >= 8.0 - 0.0001,
			"Tier-Position %s hat radialen Abstand < 8.0 zum Zentrum." % pos)

func test_spawn_enemies_every_position_is_outside_center_radius() -> void:
	_terrain.fixed_height = 1.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_enemies()
	for call in _orchestrator.calls:
		var pos: Vector3 = call[1]
		assert_true(Vector2(pos.x, pos.z).length() >= 10.0 - 0.0001,
			"Feind-Position %s hat radialen Abstand < 10.0 zum Zentrum." % pos)


# ─────────────────────────────────────────────
# Typ-Invarianten
# ─────────────────────────────────────────────

func test_spawn_animals_types_are_from_expected_set() -> void:
	_terrain.fixed_height = 1.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_animals()
	for call in _orchestrator.calls:
		assert_true(call[0] in ["deer", "rabbit", "boar", "fox", "squirrel", "sheep"], "Unerwarteter Tier-Typ: %s" % call[0])

func test_spawn_enemies_types_are_from_expected_set() -> void:
	_terrain.fixed_height = 1.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_enemies()
	for call in _orchestrator.calls:
		assert_true(call[0] in ["goblin", "skeleton"], "Unerwarteter Feind-Typ: %s" % call[0])

func test_spawn_enemies_calls_at_most_five_times() -> void:
	# Die Schleife läuft genau range(5) mal — jede Iteration spawnt HÖCHSTENS
	# einmal (kann durch Distanz-/Höhen-Check übersprungen werden), also ist
	# 5 eine harte Obergrenze unabhängig vom Zufall.
	_terrain.fixed_height = 1.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_enemies()
	assert_true(_orchestrator.calls.size() <= 5)


# ─────────────────────────────────────────────
# Mindestabstand-Invariante (Tiere, kumulativ über alle Typen hinweg)
# ─────────────────────────────────────────────

func test_spawn_animals_respects_min_distance_against_all_earlier_positions() -> void:
	_terrain.fixed_height = 1.0
	var spawner := EnemySpawner.new(_orchestrator, _terrain)
	spawner.spawn_animals()
	for i in range(_orchestrator.calls.size()):
		var type_i: String = _orchestrator.calls[i][0]
		var pos_i: Vector3 = _orchestrator.calls[i][1]
		var min_dist: float = ANIMAL_MIN_DIST[type_i]
		for j in range(i):
			var pos_j: Vector3 = _orchestrator.calls[j][1]
			assert_true(pos_i.distance_to(pos_j) >= min_dist - 0.0001,
				"Position #%d (%s) zu nah an früher platzierter Position #%d (Abstand %.2f, erwartet >= %.2f)." % [
					i, type_i, j, pos_i.distance_to(pos_j), min_dist
				])
