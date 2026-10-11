# res://tests/unit/test_pet_component_xp.gd
extends GutTest

## Unit-Tests für PetComponent.add_xp()/get_level()/get_xp()/get_level_progress()
## und deren Persistenz über get_save_state() — Wunsch "Pets sollen XP bekommen
## wie der Spieler auch, generelles Pet-Level, Cap bei 100".
##
## PetComponent wird NICHT in einen SceneTree gehängt (autofree genügt) — alle
## getesteten Methoden lesen/schreiben nur _xp, kein _ready()/Tree nötig.
## is_multiplayer_authority() liefert für einen Node außerhalb jeder
## Multiplayer-Konfiguration standardmäßig true (gleiche Annahme wie die
## bestehenden set_abilities()-Tests in test_pet_panel_controller.gd).

var _pet: PetComponent

func before_each() -> void:
	_pet = autofree(PetComponent.new())

func test_fresh_pet_starts_at_level_one_with_zero_xp() -> void:
	assert_eq(_pet.get_level(), 1)
	assert_eq(_pet.get_xp(), 0)

func test_add_xp_accumulates() -> void:
	_pet.add_xp(10)
	_pet.add_xp(5)
	assert_eq(_pet.get_xp(), 15)

func test_add_xp_zero_or_negative_is_ignored() -> void:
	_pet.add_xp(0)
	_pet.add_xp(-10)
	assert_eq(_pet.get_xp(), 0)

func test_add_xp_can_level_up() -> void:
	var needed := PetLeveling.xp_required_for_level(2)
	_pet.add_xp(needed)
	assert_eq(_pet.get_level(), 2)

func test_level_never_exceeds_cap() -> void:
	_pet.add_xp(999999999)
	assert_eq(_pet.get_level(), PetLeveling.MAX_LEVEL)

func test_level_progress_reflects_current_xp() -> void:
	_pet.add_xp(PetLeveling.xp_required_for_level(2) + 7)
	var progress := _pet.get_level_progress()
	assert_eq(progress["xp_into_level"], 7)

# ─────────────────────────────────────────────
# Persistenz (get_save_state() / on_spawn()-Config)
# ─────────────────────────────────────────────

func test_get_save_state_includes_xp() -> void:
	_pet.add_xp(42)
	assert_eq(_pet.get_save_state()["xp"], 42)

func test_on_spawn_restores_xp_from_config() -> void:
	var fresh: PetComponent = autofree(PetComponent.new())
	fresh.on_spawn({"xp": 123}, null)
	assert_eq(fresh.get_xp(), 123)
	autofree(fresh)

func test_on_spawn_defaults_xp_to_zero_without_config() -> void:
	var fresh: PetComponent = autofree(PetComponent.new())
	fresh.on_spawn({}, null)
	assert_eq(fresh.get_xp(), 0)

func test_on_spawn_clamps_negative_xp_to_zero() -> void:
	# Verteidigung gegen ein manuell editiertes/beschädigtes Save.
	var fresh: PetComponent = autofree(PetComponent.new())
	fresh.on_spawn({"xp": -50}, null)
	assert_eq(fresh.get_xp(), 0)
