# res://tests/unit/test_pet_restorer.gd
extends GutTest

## Unit-Tests für PetRestorer.restore() (Save-Daten-Parsing mit defensiven
## Defaults für Alt-Saves ohne owner_peer_id).
##
## StubEntityOrchestrator (gleiches Muster wie in test_enemy_spawner.gd)
## zeichnet alle spawn_entity()-Aufrufe auf. WorldData ist reines RefCounted-
## Datenobjekt, keine Deps nötig — set_meta()/get_meta()/has_meta() sind
## Object-Basisfunktionalität.
##
## Abgedeckt:
##   - Ungültiges/fehlendes/falsch typisiertes saved_pets-Meta -> No-Op
##   - Einträge, die keine Dictionary sind, werden übersprungen
##   - pos: gültiger String -> geparst; fehlend -> Default Vector3(0,1,0);
##     kaputter String (kein Vector3) -> Eintrag übersprungen (kein Crash)
##   - color: gültiger String -> geparst; fehlend/kaputt -> Default
##     Color(0.7,0.5,0.3) (mit Alpha 1.0)
##   - owner_peer_id: fehlt -> Default 1 (Solo/Host), sonst übernommen und
##     sowohl im config-Dict ALS AUCH als eigener peer_id-Parameter durchgereicht
##   - name: fehlt -> Default "Pet"
##   - spawn_entity() liefert null zurück -> kein Crash, kein Restore-Zähler
##     nötig (der Zähler ist rein intern/geloggt, hier nicht direkt prüfbar)


class StubEntityOrchestrator extends EntityOrchestrator:
	var calls: Array = []  ## [[type_id, position, config, peer_id], ...]
	var spawn_result: Node3D = null
	func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}, peer_id: int = 1) -> Node3D:
		calls.append([type_id, position, config, peer_id])
		return spawn_result


var _orchestrator: StubEntityOrchestrator
var _world_root: Node3D


func before_each() -> void:
	_orchestrator = StubEntityOrchestrator.new()
	add_child_autofree(_orchestrator)
	_world_root = Node3D.new()
	add_child_autofree(_world_root)


func after_each() -> void:
	_orchestrator = null
	_world_root = null


# ─────────────────────────────────────────────
# No-Op-Fälle
# ─────────────────────────────────────────────

func test_invalid_world_data_is_noop() -> void:
	var restorer := PetRestorer.new(null, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 0)

func test_missing_saved_pets_meta_is_noop() -> void:
	var data := WorldData.new()
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 0)

func test_saved_pets_meta_wrong_type_is_noop() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", "not_an_array")
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 0)

func test_empty_array_is_noop() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 0)

func test_non_dictionary_entries_are_skipped() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", ["just_a_string", 42, null])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 0)


# ─────────────────────────────────────────────
# pos-Parsing
# ─────────────────────────────────────────────

func test_valid_pos_string_is_parsed() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(5, 2, 9)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 1)
	assert_eq(_orchestrator.calls[0][1], Vector3(5, 2, 9))

func test_missing_pos_uses_default() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"name": "Rex"}])  # kein "pos"
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][1], Vector3(0, 1, 0))

func test_broken_pos_string_skips_entry() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "not a vector"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 0, "str_to_var() liefert hier keinen Vector3 -> Eintrag übersprungen, kein Crash.")


# ─────────────────────────────────────────────
# color-Parsing
# ─────────────────────────────────────────────

func test_valid_color_string_is_parsed() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)", "color": "Color(0.1, 0.2, 0.3, 1.0)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	var config: Dictionary = _orchestrator.calls[0][2]
	assert_eq(config["color"], Color(0.1, 0.2, 0.3, 1.0))

func test_missing_color_uses_default() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)"}])  # kein "color"
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	var config: Dictionary = _orchestrator.calls[0][2]
	assert_eq(config["color"], Color(0.7, 0.5, 0.3, 1.0))

func test_broken_color_string_falls_back_to_default() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)", "color": "not a color"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	var config: Dictionary = _orchestrator.calls[0][2]
	assert_eq(config["color"], Color(0.7, 0.5, 0.3, 1.0))


# ─────────────────────────────────────────────
# owner_peer_id / name
# ─────────────────────────────────────────────

func test_missing_owner_peer_id_defaults_to_one() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	var call: Array = _orchestrator.calls[0]
	assert_eq(call[3], 1, "peer_id-Parameter von spawn_entity().")
	assert_eq(call[2]["owner_peer_id"], 1, "owner_peer_id auch im config-Dict.")

func test_explicit_owner_peer_id_is_passed_through() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)", "owner_peer_id": 7}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	var call: Array = _orchestrator.calls[0]
	assert_eq(call[3], 7)
	assert_eq(call[2]["owner_peer_id"], 7)

func test_missing_name_defaults_to_pet() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][2]["name"], "Pet")

func test_explicit_name_is_used() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)", "name": "Fluffy"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][2]["name"], "Fluffy")


# ─────────────────────────────────────────────
# abilities / owner_player_id (Pet-Fähigkeiten)
# ─────────────────────────────────────────────

func test_missing_abilities_defaults_to_empty() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][2]["abilities"], [])

func test_explicit_abilities_are_sanitized_and_passed_through() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{
		"pos": "Vector3(0,1,0)",
		"abilities": [PetAbilities.MINING, PetAbilities.DIGGING, "typo"],
	}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][2]["abilities"], [PetAbilities.MINING, PetAbilities.DIGGING])

func test_missing_owner_player_id_defaults_to_empty_string() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][2]["owner_player_id"], "")

func test_explicit_owner_player_id_is_passed_through() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)", "owner_player_id": "uuid-123"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls[0][2]["owner_player_id"], "uuid-123")


# ─────────────────────────────────────────────
# Mehrere Einträge / spawn-Fehlschlag
# ─────────────────────────────────────────────

func test_multiple_entries_all_spawn_in_order() -> void:
	var data := WorldData.new()
	data.set_meta("saved_pets", [
		{"pos": "Vector3(1,1,1)", "name": "A"},
		{"pos": "Vector3(2,1,2)", "name": "B"},
	])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)
	assert_eq(_orchestrator.calls.size(), 2)
	assert_eq(_orchestrator.calls[0][2]["name"], "A")
	assert_eq(_orchestrator.calls[1][2]["name"], "B")

func test_spawn_entity_returning_null_does_not_crash() -> void:
	_orchestrator.spawn_result = null
	var data := WorldData.new()
	data.set_meta("saved_pets", [{"pos": "Vector3(0,1,0)"}])
	var restorer := PetRestorer.new(data, _orchestrator)
	restorer.restore(_world_root)  # darf nicht crashen
	assert_eq(_orchestrator.calls.size(), 1, "Der Aufruf selbst findet trotzdem statt, nur restored bleibt 0 (intern, nicht geprüft).")
