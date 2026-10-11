# res://tests/unit/test_entity_pool.gd
extends GutTest

## Unit-Tests für EntityPool.
##
## EntityPool ist RefCounted — kein SceneTree nötig für die meisten Tests.
## Node3D-Instanzen werden über add_child_autofree() verwaltet wo nötig.
##
## Abgedeckt:
##   - Initialisierung: default_max_size gesetzt via _init()
##   - acquire(): gibt null zurück wenn Pool leer (kein Match)
##   - acquire(): gibt gepoolte Instanz zurück wenn vorhanden
##   - release(): speichert Entity im Pool
##   - release(): false wenn Pool voll (default_max_size überschritten)
##   - release(): false wenn Pool voll (pro-Typ-Override überschritten)
##   - set_max_size_for(): pro-Typ-Limit überschreibt default
##   - get_max_size_for(): default wenn kein Override, Override wenn gesetzt
##   - set_max_size_for(): negativer Wert wird ignoriert
##   - Pool-Kapazität: genau max_size Einträge werden akzeptiert, max_size+1 nicht
##   - flush(): alle Einträge werden entfernt, Nodes werden freed
##   - flush(): leerer Pool kein Crash
##   - get_sizes(): korrekte Größen zurück
##   - get_sizes_with_limits(): size + max korrekt
##   - pool_hits / pool_misses: Statistiken korrekt
##   - acquire() / release() Round-Trip: gleiche Instanz zurück

const TYPE_TREE    := "oak_tree"
const TYPE_ENEMY   := "goblin"
const TYPE_UNKNOWN := "nonexistent_type"

var _pool: EntityPool

func before_each() -> void:
	_pool = EntityPool.new(10)

func _make_entity() -> Node3D:
	return add_child_autofree(Node3D.new())

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────

func test_init_sets_default_max_size() -> void:
	var p := EntityPool.new(5)
	assert_eq(p.default_max_size, 5, "_init() muss default_max_size setzen")

func test_init_default_is_ten() -> void:
	var p := EntityPool.new()
	assert_eq(p.default_max_size, 10, "Standard-Default muss 10 sein")

func test_init_stats_zero() -> void:
	assert_eq(_pool.pool_hits,   0, "pool_hits muss initial 0 sein")
	assert_eq(_pool.pool_misses, 0, "pool_misses muss initial 0 sein")

# ─────────────────────────────────────────────────────────────────────────────
# acquire()
# ─────────────────────────────────────────────────────────────────────────────

func test_acquire_empty_pool_returns_null() -> void:
	assert_null(_pool.acquire(TYPE_TREE), "Leerer Pool muss null zurückgeben")

func test_acquire_empty_pool_increments_miss() -> void:
	_pool.acquire(TYPE_TREE)
	assert_eq(_pool.pool_misses, 1, "Miss muss bei leerem Pool inkrementiert werden")

func test_acquire_unknown_type_returns_null() -> void:
	assert_null(_pool.acquire(TYPE_UNKNOWN))

func test_acquire_returns_released_entity() -> void:
	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)
	var acquired := _pool.acquire(TYPE_TREE)
	assert_eq(acquired, entity, "acquire() muss die zuvor released Entity zurückgeben")

func test_acquire_increments_hit() -> void:
	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)
	_pool.acquire(TYPE_TREE)
	assert_eq(_pool.pool_hits, 1, "Hit muss bei erfolgreichem acquire() inkrementiert werden")

func test_acquire_removes_from_pool() -> void:
	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)
	_pool.acquire(TYPE_TREE)
	assert_null(_pool.acquire(TYPE_TREE), "Nach acquire() darf Pool für diesen Typ leer sein")

func test_acquire_empty_type_string_returns_null() -> void:
	assert_null(_pool.acquire(""), "Leerer type_id muss null zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# release()
# ─────────────────────────────────────────────────────────────────────────────

func test_release_returns_true_when_accepted() -> void:
	var entity := _make_entity()
	assert_true(_pool.release(TYPE_TREE, entity), "release() muss true zurückgeben wenn Pool Platz hat")

func test_release_false_when_empty_type_id() -> void:
	var entity := _make_entity()
	assert_false(_pool.release("", entity), "Leerer type_id muss false zurückgeben")

func test_release_increases_pool_size() -> void:
	_pool.release(TYPE_TREE, _make_entity())
	assert_eq(_pool.get_sizes().get(TYPE_TREE, 0), 1)

func test_release_multiple_entities_same_type() -> void:
	_pool.release(TYPE_TREE, _make_entity())
	_pool.release(TYPE_TREE, _make_entity())
	_pool.release(TYPE_TREE, _make_entity())
	assert_eq(_pool.get_sizes().get(TYPE_TREE, 0), 3)

# ─────────────────────────────────────────────────────────────────────────────
# Pool-Größenlimit (default_max_size)
# ─────────────────────────────────────────────────────────────────────────────

func test_release_accepts_exactly_max_size_entities() -> void:
	var pool := EntityPool.new(3)
	for i in range(3):
		assert_true(pool.release(TYPE_TREE, _make_entity()),
			"Bis max_size muss release() true zurückgeben")
	assert_eq(pool.get_sizes().get(TYPE_TREE, 0), 3)

func test_release_rejects_when_full() -> void:
	var pool := EntityPool.new(3)
	for i in range(3):
		pool.release(TYPE_TREE, _make_entity())
	assert_false(pool.release(TYPE_TREE, _make_entity()),
		"Voller Pool muss false zurückgeben")

func test_pool_size_stays_at_max_after_overflow() -> void:
	var pool := EntityPool.new(3)
	for i in range(5):
		pool.release(TYPE_TREE, _make_entity())
	assert_eq(pool.get_sizes().get(TYPE_TREE, 0), 3,
		"Pool-Größe darf max_size nie überschreiten")

func test_different_types_have_independent_limits() -> void:
	var pool := EntityPool.new(2)
	pool.release(TYPE_TREE,  _make_entity())
	pool.release(TYPE_TREE,  _make_entity())
	pool.release(TYPE_ENEMY, _make_entity())
	assert_eq(pool.get_sizes().get(TYPE_TREE,  0), 2, "oak_tree Pool muss 2 enthalten")
	assert_eq(pool.get_sizes().get(TYPE_ENEMY, 0), 1, "goblin Pool muss 1 enthalten")

# ─────────────────────────────────────────────────────────────────────────────
# Pro-Typ-Limits (set_max_size_for / get_max_size_for)
# ─────────────────────────────────────────────────────────────────────────────

func test_get_max_size_for_returns_default_without_override() -> void:
	assert_eq(_pool.get_max_size_for(TYPE_TREE), 10,
		"Ohne Override muss default_max_size zurückgegeben werden")

func test_set_max_size_for_overrides_default() -> void:
	_pool.set_max_size_for(TYPE_TREE, 25)
	assert_eq(_pool.get_max_size_for(TYPE_TREE), 25,
		"Override muss default_max_size für diesen Typ ersetzen")

func test_set_max_size_for_does_not_affect_other_types() -> void:
	_pool.set_max_size_for(TYPE_TREE, 25)
	assert_eq(_pool.get_max_size_for(TYPE_ENEMY), 10,
		"Override für oak_tree darf goblin-Limit nicht verändern")

func test_set_max_size_for_negative_value_ignored() -> void:
	_pool.set_max_size_for(TYPE_TREE, -5)
	assert_eq(_pool.get_max_size_for(TYPE_TREE), 10,
		"Negativer max_size-Wert darf nicht übernommen werden")

func test_per_type_limit_enforced_in_release() -> void:
	_pool.set_max_size_for(TYPE_TREE, 3)
	for i in range(3):
		_pool.release(TYPE_TREE, _make_entity())
	assert_false(_pool.release(TYPE_TREE, _make_entity()),
		"Pro-Typ-Limit muss in release() durchgesetzt werden")

func test_per_type_limit_higher_than_default_allows_more() -> void:
	_pool.set_max_size_for(TYPE_TREE, 20)
	for i in range(20):
		assert_true(_pool.release(TYPE_TREE, _make_entity()))
	assert_false(_pool.release(TYPE_TREE, _make_entity()),
		"Limit von 20 muss bei 21. Eintrag abweisen")

func test_zero_max_size_rejects_all() -> void:
	_pool.set_max_size_for(TYPE_TREE, 0)
	assert_false(_pool.release(TYPE_TREE, _make_entity()),
		"max_size=0 muss alle Einträge ablehnen")

# ─────────────────────────────────────────────────────────────────────────────
# Round-Trip
# ─────────────────────────────────────────────────────────────────────────────

func test_round_trip_same_instance_returned() -> void:
	var e1 := _make_entity()
	var e2 := _make_entity()
	_pool.release(TYPE_TREE, e1)
	_pool.release(TYPE_TREE, e2)
	var got1 := _pool.acquire(TYPE_TREE)
	var got2 := _pool.acquire(TYPE_TREE)
	# Reihenfolge LIFO (Stack) oder FIFO — beide korrekt, solange beide Instanzen zurück
	assert_true(
		(got1 == e1 and got2 == e2) or (got1 == e2 and got2 == e1),
		"Round-Trip muss genau die gespeicherten Instanzen zurückgeben"
	)

func test_round_trip_hit_and_miss_stats() -> void:
	var entity := _make_entity()
	_pool.acquire(TYPE_TREE)         # miss
	_pool.release(TYPE_TREE, entity) # store
	_pool.acquire(TYPE_TREE)         # hit
	_pool.acquire(TYPE_TREE)         # miss (leer)
	assert_eq(_pool.pool_hits,   1)
	assert_eq(_pool.pool_misses, 2)

# ─────────────────────────────────────────────────────────────────────────────
# flush()
# ─────────────────────────────────────────────────────────────────────────────

func test_flush_empty_pool_no_crash() -> void:
	_pool.flush()
	assert_true(true, "flush() auf leerem Pool darf nicht crashen")

func test_flush_returns_count_of_freed_entities() -> void:
	_pool.release(TYPE_TREE,  _make_entity())
	_pool.release(TYPE_TREE,  _make_entity())
	_pool.release(TYPE_ENEMY, _make_entity())
	var freed := _pool.flush()
	assert_eq(freed, 3, "flush() muss die Anzahl freigegebener Entities zurückgeben")

func test_flush_empties_all_types() -> void:
	_pool.release(TYPE_TREE,  _make_entity())
	_pool.release(TYPE_ENEMY, _make_entity())
	_pool.flush()
	assert_eq(_pool.get_sizes().size(), 0, "Nach flush() darf kein Typ mehr im Pool sein")

func test_flush_pool_usable_after_flush() -> void:
	_pool.release(TYPE_TREE, _make_entity())
	_pool.flush()
	var entity := _make_entity()
	assert_true(_pool.release(TYPE_TREE, entity), "Pool muss nach flush() wieder nutzbar sein")

# ─────────────────────────────────────────────────────────────────────────────
# get_sizes() / get_sizes_with_limits()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_sizes_empty_pool_returns_empty_dict() -> void:
	assert_eq(_pool.get_sizes().size(), 0)

func test_get_sizes_reflects_released_entities() -> void:
	_pool.release(TYPE_TREE,  _make_entity())
	_pool.release(TYPE_TREE,  _make_entity())
	_pool.release(TYPE_ENEMY, _make_entity())
	var sizes := _pool.get_sizes()
	assert_eq(sizes.get(TYPE_TREE,  0), 2)
	assert_eq(sizes.get(TYPE_ENEMY, 0), 1)

func test_get_sizes_with_limits_includes_max() -> void:
	_pool.set_max_size_for(TYPE_TREE, 25)
	_pool.release(TYPE_TREE, _make_entity())
	var info := _pool.get_sizes_with_limits()
	assert_true(TYPE_TREE in info)
	assert_eq(info[TYPE_TREE]["size"], 1)
	assert_eq(info[TYPE_TREE]["max"],  25)

func test_get_sizes_with_limits_uses_default_for_unoverridden_types() -> void:
	_pool.release(TYPE_ENEMY, _make_entity())
	var info := _pool.get_sizes_with_limits()
	assert_eq(info[TYPE_ENEMY]["max"], 10, "Default max muss für Typen ohne Override gelten")

# ─────────────────────────────────────────────────────────────────────────────
# EntityOrchestrator-Konfiguration (Regressions-Test)
# ─────────────────────────────────────────────────────────────────────────────
## Stellt sicher dass die in EntityOrchestrator._ready() konfigurierten
## Pro-Typ-Limits korrekt sind und Trees > Default > Enemies.

func test_orchestrator_pool_tree_limit_higher_than_default() -> void:
	var pool := EntityPool.new(10)
	pool.set_max_size_for("oak_tree",    20)
	pool.set_max_size_for("willow_tree", 20)
	pool.set_max_size_for("maple_tree",  20)
	pool.set_max_size_for("goblin",       6)
	pool.set_max_size_for("skeleton",     6)
	assert_true(pool.get_max_size_for("oak_tree") > pool.default_max_size,
		"Baum-Pool muss größer als Default sein (hohe Spawn-Dichte)")
	assert_true(pool.get_max_size_for("goblin") < pool.default_max_size,
		"Enemy-Pool muss kleiner als Default sein (größere Nodes, seltener)")
	pool.set_max_size_for("iron_ore",    15)
	pool.set_max_size_for("copper_ore",  15)
	assert_eq(pool.get_max_size_for("iron_ore"),    15,
		"iron_ore muss mit 15 konfiguriert sein (mittelhohe Spawn-Dichte)")

# ─────────────────────────────────────────────────────────────────────────────
# _park_container — BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes")
# ─────────────────────────────────────────────────────────────────────────────
## Ohne Container (Default, siehe before_each()) bleibt release() bei seinem alten
## Verhalten — entparent komplett. Erst MIT gesetztem Container werden released
## Entities dorthin reparented statt echte SceneTree-Orphans zu werden.

func test_release_without_container_leaves_entity_without_parent() -> void:
	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)
	assert_null(entity.get_parent(),
		"Ohne set_park_container() muss das alte Verhalten (kein Parent) erhalten bleiben")

func test_release_with_container_reparents_instead_of_orphaning() -> void:
	var container := add_child_autofree(Node.new())
	_pool.set_park_container(container)

	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)

	assert_eq(entity.get_parent(), container,
		"Mit gesetztem Container muss release() dorthin reparenten statt zu entparenten")
	assert_true(entity.is_inside_tree(),
		"Geparkte Entity muss weiterhin im SceneTree sein — kein Orphan mehr")

func test_acquire_removes_entity_from_container_before_returning() -> void:
	var container := add_child_autofree(Node.new())
	_pool.set_park_container(container)

	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)
	assert_eq(container.get_child_count(), 1)

	var acquired := _pool.acquire(TYPE_TREE)

	assert_eq(acquired, entity)
	assert_null(acquired.get_parent(),
		"acquire() muss die Entity aus dem Park-Container entfernen — sonst schlägt " +
		"das spätere add_child() im World-Root fehl (\"already has a parent\")")
	assert_eq(container.get_child_count(), 0)

func test_flush_frees_entities_parked_in_container() -> void:
	var container := add_child_autofree(Node.new())
	_pool.set_park_container(container)

	_pool.release(TYPE_TREE, _make_entity())
	_pool.release(TYPE_TREE, _make_entity())

	var freed := _pool.flush()

	assert_eq(freed, 2,
		"flush() muss auch im Container geparkte Entities zählen (nicht mehr per " +
		"is_inside_tree() übersprungen, siehe BUGFIX-Kommentar dort)")
	assert_eq(container.get_child_count(), 0, "Container muss nach flush() leer sein")

func test_flush_does_not_free_entity_reparented_elsewhere_unexpectedly() -> void:
	# Verletzt absichtlich die Pool-Invariante: eine im Pool gelistete Entity hängt
	# (ohne über acquire() geholt worden zu sein) anderswo im Baum — deutet auf einen Bug an
	# ANDERER Stelle hin. flush() soll das NICHT durch Doppel-Free verschlimmern.
	var container := add_child_autofree(Node.new())
	_pool.set_park_container(container)

	var entity := _make_entity()
	_pool.release(TYPE_TREE, entity)

	var other_parent := add_child_autofree(Node.new())
	container.remove_child(entity)
	other_parent.add_child(entity)

	var freed := _pool.flush()

	assert_eq(freed, 0, "Unerwartet anderswo reparentete Entity darf nicht mitgezählt werden")
	assert_true(is_instance_valid(entity), "…und darf erst recht nicht gefreed werden")
