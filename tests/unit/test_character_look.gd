# res://tests/unit/test_character_look.gd
extends GutTest

## Tests für CharacterLook (Datenmodell + Katalog des Aussehens-Ausbaus).

func test_default_look_has_all_fields() -> void:
	var look := CharacterLook.default_look()
	for field in CharacterLook.FIELDS:
		var key: String = String((field as Dictionary)["key"])
		assert_true(look.has(key), "default_look() fehlt Feld '%s'." % key)

func test_default_look_values_are_all_valid_catalog_ids() -> void:
	var look := CharacterLook.default_look()
	for field in CharacterLook.FIELDS:
		var key: String = String((field as Dictionary)["key"])
		assert_true(String(look[key]) in CharacterLook.option_ids(key), "Default-Wert von '%s' ist keine gültige Katalog-ID." % key)

func test_sanitize_with_null_returns_full_default_look() -> void:
	var look := CharacterLook.sanitize(null)
	assert_eq(look, CharacterLook.default_look())

func test_sanitize_with_garbage_types_falls_back_to_default() -> void:
	var look := CharacterLook.sanitize({"skin": 42, "hair_style": ["a"], "shirt": {"id": "sonnig"}})
	assert_eq(look["skin"], CharacterLook.DEFAULTS["skin"])
	assert_eq(look["hair_style"], CharacterLook.DEFAULTS["hair_style"])
	assert_eq(look["shirt"], CharacterLook.DEFAULTS["shirt"])

func test_sanitize_keeps_valid_known_ids() -> void:
	var look := CharacterLook.sanitize({"skin": "dark", "hair_color": "blue"})
	assert_eq(look["skin"], "dark")
	assert_eq(look["hair_color"], "blue")

func test_sanitize_rejects_unknown_id_falls_back_to_base_then_default() -> void:
	var base := CharacterLook.sanitize({"skin": "dark"})
	var look := CharacterLook.sanitize({"skin": "does_not_exist"}, base)
	assert_eq(look["skin"], "dark", "Ungültige ID soll auf den Basis-Look zurückfallen, nicht auf einen leeren String.")

func test_sanitize_drops_unknown_keys_silently() -> void:
	var look := CharacterLook.sanitize({"totally_unknown_field": "x"})
	assert_false(look.has("totally_unknown_field"))

func test_sanitize_ignores_non_dictionary_base() -> void:
	var look := CharacterLook.sanitize({}, {"skin": 123})
	assert_eq(look["skin"], CharacterLook.DEFAULTS["skin"])

func test_from_archetype_known_preset_overrides_shirt_color_field() -> void:
	var look := CharacterLook.from_archetype("wald")
	assert_eq(look["shirt"], "wald")

func test_from_archetype_unknown_preset_returns_default_look() -> void:
	var look := CharacterLook.from_archetype("unbestimmt")
	assert_eq(look, CharacterLook.default_look())

func test_from_archetype_result_is_always_fully_valid() -> void:
	for preset_id in ["sonnig", "wald", "flut", "asche", "unbestimmt", "garbage"]:
		var look := CharacterLook.from_archetype(preset_id)
		assert_eq(look, CharacterLook.sanitize(look), "from_archetype('%s') muss bereits ein gültiger Look sein." % preset_id)

func test_every_archetype_shirt_color_matches_creation_service_color() -> void:
	# Kopplung, die versehentlich auseinanderdriften könnte: die Shirt-Farbe
	# eines Archetyp-Looks muss exakt der Archetyp-Farbe aus
	# CharacterCreationService entsprechen — sonst zeigt der Editor eine
	# andere Farbe als der grobe Wizard gerade gesetzt hat.
	var archetypes := CharacterCreationService.APPEARANCE_ARCHETYPES
	for preset_id in archetypes.keys():
		var expected_color: Color = (archetypes[preset_id] as Dictionary)["color"]
		var look := CharacterLook.from_archetype(preset_id)
		var shirt_color := CharacterLook.color_of("shirt", String(look["shirt"]))
		assert_eq(shirt_color, expected_color, "Shirt-Farbe für Archetyp '%s' weicht von APPEARANCE_ARCHETYPES ab." % preset_id)

func test_step_cycles_forward_and_wraps() -> void:
	var look := CharacterLook.default_look()
	var ids := CharacterLook.option_ids("hair_style")
	var start_idx := ids.find(look["hair_style"])

	var stepped := CharacterLook.step(look, "hair_style", 1)

	assert_eq(stepped["hair_style"], ids[(start_idx + 1) % ids.size()])

func test_step_cycles_backward_and_wraps_below_zero() -> void:
	var look := CharacterLook.sanitize({"hair_style": CharacterLook.option_ids("hair_style")[0]})

	var stepped := CharacterLook.step(look, "hair_style", -1)

	assert_eq(stepped["hair_style"], CharacterLook.option_ids("hair_style")[-1])

func test_step_does_not_mutate_the_input_look() -> void:
	var look := CharacterLook.default_look()
	var before := look.duplicate()

	CharacterLook.step(look, "hair_style", 1)

	assert_eq(look, before, "step() muss einen neuen Look zurückgeben, nicht den übergebenen mutieren.")

func test_step_on_unknown_field_returns_sanitized_look_unchanged() -> void:
	var look := CharacterLook.default_look()

	var stepped := CharacterLook.step(look, "not_a_real_field", 1)

	assert_eq(stepped, CharacterLook.sanitize(look))

func test_label_of_returns_id_as_fallback_for_unknown_option() -> void:
	assert_eq(CharacterLook.label_of("skin", "nonexistent"), "nonexistent")

func test_color_of_falls_back_to_default_option_color_for_unknown_id() -> void:
	var default_color := CharacterLook.color_of("skin", String(CharacterLook.DEFAULTS["skin"]))
	assert_eq(CharacterLook.color_of("skin", "nonexistent"), default_color)

func test_height_scale_and_limb_scale_are_one_for_normal_medium() -> void:
	assert_eq(CharacterLook.height_scale("medium"), 1.0)
	assert_eq(CharacterLook.torso_width("normal"), 1.0)
	assert_eq(CharacterLook.limb_scale("normal"), 1.0)

func test_height_scale_unknown_id_falls_back_to_one() -> void:
	assert_eq(CharacterLook.height_scale("nonexistent"), 1.0)

func test_all_color_fields_have_a_color_on_every_option() -> void:
	# skin/hair_color/eye_color/shirt/pants werden über color_of() direkt
	# gerendert -- fehlt eine Farbe, würde CharacterPartBuilder auf Magenta
	# zurückfallen (Debug-Farbe), was ein stiller Content-Fehler wäre.
	for field in ["skin", "hair_color", "eye_color", "shirt", "pants"]:
		for entry in (CharacterLook.CATALOG[field] as Array):
			# "none" (nackt/barfuß) ist bei Oberteil/Hose bewusst farblos.
			if String((entry as Dictionary)["id"]) == "none":
				continue
			assert_true((entry as Dictionary).has("color"), "%s/%s hat keine 'color'." % [field, (entry as Dictionary)["id"]])

# ─────────────────────────────────────────────
# Erweiterter Katalog (Bart, Ohren, Brille, Hut, Schnitt, Gürtel, Schuhe, ...)
# ─────────────────────────────────────────────

func test_every_field_has_catalog_and_default() -> void:
	for field in CharacterLook.FIELDS:
		var key: String = String((field as Dictionary)["key"])
		assert_true(CharacterLook.CATALOG.has(key), "CATALOG fehlt '%s'." % key)
		assert_true(CharacterLook.DEFAULTS.has(key), "DEFAULTS fehlt '%s'." % key)

func test_catalog_ids_are_unique_per_field() -> void:
	for key in CharacterLook.CATALOG.keys():
		var ids := CharacterLook.option_ids(String(key))
		var seen := {}
		for id in ids:
			assert_false(seen.has(id), "Doppelte ID '%s' in '%s'." % [id, key])
			seen[id] = true

func test_new_color_fields_have_colors_on_every_option_that_is_not_none() -> void:
	for field in ["hat_color", "belt", "shoes"]:
		for entry in (CharacterLook.CATALOG[field] as Array):
			if (entry as Dictionary)["id"] == "none":
				continue
			assert_true((entry as Dictionary).has("color"), "%s/%s hat keine 'color'." % [field, (entry as Dictionary)["id"]])

func test_old_save_without_new_fields_gets_defaults() -> void:
	var old_save := {"skin": "dark", "hair_style": "long", "shirt": "wald"}
	var look := CharacterLook.sanitize(old_save)
	assert_eq(look["skin"], "dark")
	assert_eq(look["beard"], "none")
	assert_eq(look["hat"], "none")
	assert_eq(look["shirt_style"], "tshirt")

func test_random_look_is_always_valid() -> void:
	for i in 40:
		var look := CharacterLook.random_look()
		assert_eq(look, CharacterLook.sanitize(look))

func test_random_look_is_deterministic_for_same_seed() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	assert_eq(CharacterLook.random_look(a), CharacterLook.random_look(b))

func test_from_seed_is_stable_and_differs_between_names() -> void:
	assert_eq(CharacterLook.from_seed("Anna"), CharacterLook.from_seed("Anna"))
	assert_ne(CharacterLook.from_seed("Anna"), CharacterLook.from_seed("Berta"))

func test_random_look_usually_has_no_glasses() -> void:
	var none_count := 0
	for i in 100:
		if CharacterLook.random_look()["glasses"] == "none":
			none_count += 1
	assert_true(none_count > 55, "Brillen sollen die Ausnahme sein (none=%d/100)." % none_count)
