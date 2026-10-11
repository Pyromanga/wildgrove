# res://tests/unit/test_uuid_gen.gd
extends GutTest

## Tests für UuidGen (ADR-029 Phase 1) — lokale UUID-v4-Erzeugung für
## player_uuid/player_secret in SaveSystem.

func test_generate_v4_returns_correct_format() -> void:
	var uuid := UuidGen.generate_v4()
	var regex := RegEx.new()
	regex.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	assert_true(regex.search(uuid) != null,
		"UUID muss dem v4-Format entsprechen (Version-Nibble '4', Variant '8/9/a/b'): %s" % uuid)

func test_generate_v4_produces_unique_values() -> void:
	var seen: Dictionary = {}
	for i in range(200):
		var uuid := UuidGen.generate_v4()
		assert_false(seen.has(uuid), "UUID-Kollision nach %d Aufrufen: %s" % [i, uuid])
		seen[uuid] = true

func test_generate_v4_length_is_36() -> void:
	assert_eq(UuidGen.generate_v4().length(), 36,
		"UUID-String muss 36 Zeichen lang sein (32 Hex + 4 Bindestriche).")
