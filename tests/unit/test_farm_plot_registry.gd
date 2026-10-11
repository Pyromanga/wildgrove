# res://tests/unit/test_farm_plot_registry.gd
extends GutTest

## Tests für FarmPlotRegistry (Bugfix 2026-09-27, "bepflanzte Felder nicht
## persistent"). Siehe scripts/agent/world_persistence_check.py für die
## Godot-freie Verhaltens-Simulation von FarmPlot.on_spawn()'s Restore-Logik
## (dort auch das Kernszenario "während die App zu war fertig gewachsen").

const STAGE_EMPTY := 0
const STAGE_GROWING := 1
const STAGE_READY := 2

var _registry: FarmPlotRegistry

func before_each() -> void:
	_registry = FarmPlotRegistry.new()

func test_new_registry_is_empty() -> void:
	assert_true(_registry.is_empty())
	assert_eq(_registry.get_state("anything"), {})

func test_set_state_stores_stage_and_ready_at() -> void:
	_registry.set_state("plot_a", STAGE_GROWING, 12345.0)
	var rec := _registry.get_state("plot_a")
	assert_eq(rec.get("stage"), STAGE_GROWING)
	assert_eq(rec.get("ready_at"), 12345.0)

func test_setting_empty_stage_clears_the_entry() -> void:
	# Sparse-Prinzip: EMPTY wird nicht gespeichert, ein evtl. vorhandener
	# Eintrag (z.B. nach einer Ernte) wird entfernt.
	_registry.set_state("plot_a", STAGE_READY, 0.0)
	assert_false(_registry.is_empty())
	_registry.set_state("plot_a", STAGE_EMPTY, 0.0)
	assert_true(_registry.is_empty())
	assert_eq(_registry.get_state("plot_a"), {})

func test_clear_removes_a_single_entry() -> void:
	_registry.set_state("plot_a", STAGE_READY, 0.0)
	_registry.set_state("plot_b", STAGE_GROWING, 999.0)
	_registry.clear("plot_a")
	assert_eq(_registry.get_state("plot_a"), {})
	assert_eq(_registry.get_state("plot_b").get("stage"), STAGE_GROWING)

# ── Persistenz (Save/Load-Roundtrip, Kern des Bugfixes) ──────────────────

func test_save_and_load_roundtrip_preserves_all_plots() -> void:
	_registry.set_state("plot_a", STAGE_GROWING, 555.5)
	_registry.set_state("plot_b", STAGE_READY, 0.0)

	var saved := _registry.to_save()
	assert_eq(saved.size(), 2)

	var loaded := FarmPlotRegistry.new()
	loaded.load_save(saved)

	assert_eq(loaded.get_state("plot_a").get("stage"), STAGE_GROWING)
	assert_almost_eq(float(loaded.get_state("plot_a").get("ready_at")), 555.5, 0.001)
	assert_eq(loaded.get_state("plot_b").get("stage"), STAGE_READY)

func test_load_save_with_garbage_entries_does_not_crash() -> void:
	var loaded := FarmPlotRegistry.new()
	loaded.load_save([
		{"key": "ok", "stage": STAGE_GROWING, "ready_at": 10.0},
		{"key": "missing_fields"},
		"not_a_dictionary",
		{"key": 123, "stage": STAGE_READY, "ready_at": 5.0},  # key falscher Typ
	])
	assert_eq(loaded.get_state("ok").get("stage"), STAGE_GROWING)
	assert_eq(loaded.get_state("missing_fields"), {})

func test_load_save_with_non_array_clears_and_does_not_crash() -> void:
	_registry.set_state("plot_a", STAGE_READY, 0.0)
	_registry.load_save("not an array")
	assert_true(_registry.is_empty())

func test_load_save_defaults_to_empty_for_older_saves() -> void:
	# Ältere Spielstände ohne "farm_plots"-Schlüssel liefern "[]" (siehe
	# WorldSaveHandler.restore_world() Default) — darf nicht crashen.
	var loaded := FarmPlotRegistry.new()
	loaded.load_save([])
	assert_true(loaded.is_empty())
