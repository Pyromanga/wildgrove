# res://tests/unit/test_world_generation_service.gd
extends GutTest

## Unit-Tests für WorldGenerationService (scripts/world/core/WorldGenerationService.gd)
## — bisher ungetestet (siehe architecture_overview.py-Fund, Round 113).
##
## Strategie: getestet wird ausschließlich die reine, dokumentiert
## thread-sichere Berechnung (_generate_world_data()/_generate_positions()/
## _is_far_enough()/seed_from_string()) — direkt aufgerufen, nicht über den
## echten Thread-Wrapper generate_world_async(). Begründung: der Thread-Pfad
## selbst (Thread.start()/call_deferred()/_on_thread_done()) hat in dieser
## Sandbox keine verifizierbare Godot-Runtime zum Gegenprüfen (ehrlich offen,
## wie an anderer Stelle im Projekt) — ein Test, der auf echtes Thread-Timing
## angewiesen wäre, könnte hier nicht zuverlässig verifiziert werden. Die
## Klasse selbst trennt genau deshalb "reine Berechnung" von "Thread-Wrapper"
## (siehe Klassenkommentar von _generate_world_data()) — dieser Testdatei folgt
## derselben Trennung.
##
## Großzügige Parameter (world_half_size stark > count) in den meisten Tests,
## damit die Platzierung nicht von Zufall/Erschöpfung der max_attempts abhängt
## — bei genug Fläche pro gewünschter Position ist Erfolg praktisch garantiert,
## unabhängig vom konkreten Seed.
##
## Abgedeckt:
##   seed_from_string() — deterministisch, unterschiedliche Strings i.d.R. unterschiedlich
##   _generate_world_data() — Reproduzierbarkeit bei gleichem Seed
##   _generate_world_data() — nutzt ausschließlich TREE_TYPES/ORE_TYPES als type_id
##   _generate_world_data() — Baum-Anzahl <= tree_count, Erz-Anzahl <= ore_count
##   Mindestabstand — Bäume untereinander, Erze untereinander, Erze zu Bäumen
##   _is_far_enough() — statische Hilfsfunktion isoliert

var _svc: WorldGenerationService

func before_each() -> void:
	_svc = WorldGenerationService.new()
	# Großzügig: viel Fläche für wenige Positionen -> Platzierung praktisch
	# garantiert erfolgreich, unabhängig vom Seed.
	_svc.world_half_size     = 100.0
	_svc.min_tree_distance   = 2.0
	_svc.min_ore_distance    = 2.0
	_svc.min_spawn_clearance = 1.0
	_svc.tree_count          = 6
	_svc.ore_count           = 4

func after_each() -> void:
	_svc = null

# ─────────────────────────────────────────────
# seed_from_string()
# ─────────────────────────────────────────────

func test_seed_from_string_is_deterministic() -> void:
	assert_eq(WorldGenerationService.seed_from_string("Alice"), WorldGenerationService.seed_from_string("Alice"))

func test_seed_from_string_differs_for_different_input() -> void:
	assert_ne(WorldGenerationService.seed_from_string("Alice"), WorldGenerationService.seed_from_string("Bob"))

func test_seed_from_string_empty_string_does_not_crash() -> void:
	assert_eq(WorldGenerationService.seed_from_string(""), 0)

# ─────────────────────────────────────────────
# _generate_world_data() — Reproduzierbarkeit
# ─────────────────────────────────────────────

func test_generate_world_data_same_seed_produces_identical_result() -> void:
	var a := _svc._generate_world_data(1234, null, Callable())
	var b := _svc._generate_world_data(1234, null, Callable())
	assert_eq(a.typed_tree_positions, b.typed_tree_positions, "Gleicher Seed muss identische Baum-Positionen liefern")
	assert_eq(a.typed_ore_positions, b.typed_ore_positions, "Gleicher Seed muss identische Erz-Positionen liefern")

func test_generate_world_data_different_seed_likely_differs() -> void:
	var a := _svc._generate_world_data(1, null, Callable())
	var b := _svc._generate_world_data(2, null, Callable())
	assert_ne(a.typed_tree_positions, b.typed_tree_positions, "Unterschiedliche Seeds sollten (bei 100x100-Fläche) nicht dieselben Positionen liefern")

func test_generate_world_data_reuses_passed_in_data_object() -> void:
	var existing := WorldData.new()
	existing.world_seed = 999
	var result := _svc._generate_world_data(1234, existing, Callable())
	assert_same(result, existing, "Übergebenes WorldData-Objekt muss wiederverwendet, nicht ersetzt werden")
	assert_eq(result.world_seed, 999, "Bereits gesetzte Felder auf dem übergebenen Objekt bleiben unverändert")

func test_generate_world_data_creates_new_data_when_null() -> void:
	var result := _svc._generate_world_data(1234, null, Callable())
	assert_not_null(result)
	assert_true(result is WorldData)

# ─────────────────────────────────────────────
# Typ-Zuweisung
# ─────────────────────────────────────────────

func test_generated_trees_only_use_known_tree_types() -> void:
	var result := _svc._generate_world_data(42, null, Callable())
	for type_id in result.typed_tree_positions.keys():
		assert_true(type_id in WorldGenerationService.TREE_TYPES, "Unbekannter Baum-Typ: %s" % type_id)

func test_generated_ores_only_use_known_ore_types() -> void:
	var result := _svc._generate_world_data(42, null, Callable())
	for type_id in result.typed_ore_positions.keys():
		assert_true(type_id in WorldGenerationService.ORE_TYPES, "Unbekannter Erz-Typ: %s" % type_id)

# ─────────────────────────────────────────────
# Anzahl — nie mehr als konfiguriert
# ─────────────────────────────────────────────

func test_generated_tree_count_never_exceeds_configured_count() -> void:
	var result := _svc._generate_world_data(42, null, Callable())
	assert_lte(result.get_tree_count(), _svc.tree_count)

func test_generated_ore_count_never_exceeds_configured_count() -> void:
	var result := _svc._generate_world_data(42, null, Callable())
	assert_lte(result.get_ore_count(), _svc.ore_count)

func test_generous_area_places_all_requested_trees() -> void:
	# Bei 100x100-Fläche für nur 6 Bäume (min_tree_distance=2) sollte die
	# Platzierung praktisch immer vollständig gelingen — kein max_attempts-Abbruch.
	var result := _svc._generate_world_data(42, null, Callable())
	assert_eq(result.get_tree_count(), _svc.tree_count)

# ─────────────────────────────────────────────
# Mindestabstand-Invarianten
# ─────────────────────────────────────────────

func _all_positions(data: WorldData, typed_dict: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for type_id in typed_dict.keys():
		for pos in typed_dict[type_id]:
			out.append(pos)
	return out

func test_trees_respect_minimum_distance_to_each_other() -> void:
	var result := _svc._generate_world_data(42, null, Callable())
	var trees := _all_positions(result, result.typed_tree_positions)
	for i in range(trees.size()):
		for j in range(i + 1, trees.size()):
			assert_gte(trees[i].distance_to(trees[j]), _svc.min_tree_distance,
				"Bäume %d/%d unterschreiten min_tree_distance" % [i, j])

func test_ores_respect_minimum_distance_to_trees() -> void:
	var result := _svc._generate_world_data(42, null, Callable())
	var trees := _all_positions(result, result.typed_tree_positions)
	var ores  := _all_positions(result, result.typed_ore_positions)
	for ore_pos in ores:
		for tree_pos in trees:
			assert_gte(ore_pos.distance_to(tree_pos), _svc.min_ore_distance,
				"Erz-Position unterschreitet min_ore_distance zu einem Baum")

# ─────────────────────────────────────────────
# _is_far_enough() — isolierte Hilfsfunktion
# ─────────────────────────────────────────────

func test_is_far_enough_true_when_no_others() -> void:
	assert_true(WorldGenerationService._is_far_enough(Vector3.ZERO, [], 5.0))

func test_is_far_enough_false_when_too_close() -> void:
	var others: Array[Vector3] = [Vector3(1, 0, 0)]
	assert_false(WorldGenerationService._is_far_enough(Vector3.ZERO, others, 5.0))

func test_is_far_enough_true_when_exactly_at_boundary_distance() -> void:
	var others: Array[Vector3] = [Vector3(5, 0, 0)]
	assert_true(WorldGenerationService._is_far_enough(Vector3.ZERO, others, 5.0), "distance_to == min_dist ist NICHT < min_dist, muss also als weit genug gelten")
