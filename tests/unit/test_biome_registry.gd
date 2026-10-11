## tests/unit/test_biome_registry.gd
## Unit-Tests für BiomeRegistry und BiomeDefinition.
##
## Abdeckung:
##   - Alle 8 Biome registriert (Round 78: "mountain" neu, Round 79: "dead_forest" neu)
##   - Noise-Zuweisung (temp/humid → biome_id)
##   - Biom-Felder (Farben, prop_chances) nicht leer
##   - BiomeDefinition.prop_chances enthält nur gültige String-Keys
##   - get_biome_for() liefert immer eine Definition (nie null)
##   - Grenzbedingungen der Noise-Zuweisung

extends GutTest

# ─────────────────────────────────────────────
# Registrierung
# ─────────────────────────────────────────────

func test_all_eight_biomes_registered() -> void:
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b := BiomeRegistry.get_biome(biome_id)
		assert_not_null(b, "Biom '%s' muss registriert sein" % biome_id)

func test_biome_ids_match_keys() -> void:
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b := BiomeRegistry.get_biome(biome_id)
		assert_eq(b.biome_id, biome_id, "biome_id-Feld muss mit Registry-Key übereinstimmen")

func test_display_names_not_empty() -> void:
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b := BiomeRegistry.get_biome(biome_id)
		assert_ne(b.display_name, "", "display_name darf nicht leer sein")

# ─────────────────────────────────────────────
# Noise-Zuweisung
# ─────────────────────────────────────────────

func test_high_temp_gives_desert() -> void:
	var id := BiomeRegistry.get_biome_id_for(0.7, 0.0)
	assert_eq(id, "desert")

func test_very_cold_gives_winter() -> void:
	var id := BiomeRegistry.get_biome_id_for(-0.6, 0.0)
	assert_eq(id, "winter")

func test_desert_threshold_boundaries() -> void:
	# Knapp über der Schwelle → Wüste, knapp darunter → keine Wüste.
	assert_eq(BiomeRegistry.get_biome_id_for(BiomeRegistry.DESERT_MIN_TEMP + 0.01, 0.0), "desert")
	assert_ne(BiomeRegistry.get_biome_id_for(BiomeRegistry.DESERT_MIN_TEMP - 0.01, 0.0), "desert")

func test_winter_threshold_boundaries() -> void:
	assert_eq(BiomeRegistry.get_biome_id_for(BiomeRegistry.WINTER_MAX_TEMP - 0.01, 0.0), "winter")
	assert_ne(BiomeRegistry.get_biome_id_for(BiomeRegistry.WINTER_MAX_TEMP + 0.01, 0.0), "winter")

func test_warm_and_humid_gives_swamp() -> void:
	var id := BiomeRegistry.get_biome_id_for(0.2, 0.6)
	assert_eq(id, "swamp")

func test_moderate_humid_gives_dense_forest() -> void:
	var id := BiomeRegistry.get_biome_id_for(0.0, 0.4)
	assert_eq(id, "dense_forest")

func test_slight_humid_gives_forest() -> void:
	var id := BiomeRegistry.get_biome_id_for(0.0, 0.1)
	assert_eq(id, "forest")

func test_dry_neutral_gives_meadow() -> void:
	var id := BiomeRegistry.get_biome_id_for(0.0, -0.5)
	assert_eq(id, "meadow")

func test_cold_dry_gives_mountain() -> void:
	# Round 78 — neue Nische zwischen "winter" (temp < WINTER_MAX_TEMP) und der
	# bisherigen meadow-Katchall-Zone (temp WINTER_MAX_TEMP..DESERT_MIN_TEMP, humid <= 0).
	var id := BiomeRegistry.get_biome_id_for(-0.3, -0.5)
	assert_eq(id, "mountain")

func test_mountain_boundary_stays_meadow_when_not_cold_enough() -> void:
	# Grenzfall direkt an der neuen Schwelle (temp = -0.15 selbst zählt
	# noch NICHT als "kalt genug", siehe strikt-kleiner-als in _resolve_id()).
	var id := BiomeRegistry.get_biome_id_for(-0.15, -0.5)
	assert_eq(id, "meadow")

func test_very_dry_gives_dead_forest() -> void:
	# Round 79 — neue Nische innerhalb der bisherigen meadow-Restzone
	# (temp >= -0.15, humid <= 0): besonders trocken (humid < -0.5) wird
	# jetzt "dead_forest" statt "meadow".
	var id := BiomeRegistry.get_biome_id_for(0.0, -0.7)
	assert_eq(id, "dead_forest")

func test_dead_forest_boundary_stays_meadow_when_not_dry_enough() -> void:
	# Grenzfall: humid = -0.5 selbst zählt noch NICHT als "trocken genug"
	# (strikt-kleiner-als in _resolve_id(), identisches Muster zur
	# mountain-Schwelle oben).
	var id := BiomeRegistry.get_biome_id_for(0.0, -0.5)
	assert_eq(id, "meadow")

func test_get_biome_for_never_returns_null() -> void:
	# Grid über alle temp/humid-Kombos
	for ti in range(5):
		for hi in range(5):
			var temp  := -1.0 + ti * 0.5
			var humid := -1.0 + hi * 0.5
			var b := BiomeRegistry.get_biome_for(temp, humid)
			assert_not_null(b, "get_biome_for(%.1f, %.1f) darf nie null liefern" % [temp, humid])

# ─────────────────────────────────────────────
# Biom-Felder
# ─────────────────────────────────────────────

func test_forest_has_oak_tree_prop() -> void:
	var b := BiomeRegistry.get_biome("forest")
	assert_true(b.prop_chances.has("oak_tree"), "forest muss oak_tree-Prop haben")
	assert_gt(b.prop_chances["oak_tree"], 0.0)

func test_desert_has_cactus_prop() -> void:
	var b := BiomeRegistry.get_biome("desert")
	assert_true(b.prop_chances.has("cactus"))
	assert_gt(b.prop_chances["cactus"], 0.0)

func test_winter_has_snow_coverage() -> void:
	var b := BiomeRegistry.get_biome("winter")
	assert_eq(b.snow_coverage, 1.0)

func test_swamp_has_fog_density() -> void:
	var b := BiomeRegistry.get_biome("swamp")
	assert_gt(b.fog_density, 0.0)

func test_mountain_has_rock_boulder_prop() -> void:
	var b := BiomeRegistry.get_biome("mountain")
	assert_true(b.prop_chances.has("rock_boulder"), "mountain muss rock_boulder-Prop haben")
	assert_gt(b.prop_chances["rock_boulder"], 0.0)

func test_dead_forest_has_dominant_fallen_tree_and_sparse_oak() -> void:
	var b := BiomeRegistry.get_biome("dead_forest")
	assert_true(b.prop_chances.has("fallen_tree"), "dead_forest muss fallen_tree-Prop haben")
	assert_true(b.prop_chances.has("oak_tree"), "dead_forest muss (wenige) oak_tree-Props haben")
	assert_gt(b.prop_chances["fallen_tree"], b.prop_chances["oak_tree"],
		"Baumstämme müssen deutlich häufiger sein als lebende Bäume ('paar lebende Bäume & viele Baumstämme')")

func test_prop_chances_all_in_valid_range() -> void:
	for biome_id in ["forest", "dense_forest", "meadow", "desert", "winter", "swamp", "mountain", "dead_forest"]:
		var b := BiomeRegistry.get_biome(biome_id)
		for key in b.prop_chances:
			var chance: float = b.prop_chances[key]
			assert_gte(chance, 0.0, "%s.%s chance muss >= 0" % [biome_id, key])
			assert_lte(chance, 1.0, "%s.%s chance muss <= 1" % [biome_id, key])

func test_meadow_has_structure_types() -> void:
	var b := BiomeRegistry.get_biome("meadow")
	assert_gt(b.structure_types.size(), 0, "Wiese muss Strukturtypen haben")

# ── Bodenmaterial (2026-09-26, "überall nur Erde") ──

func test_desert_surface_material_is_sand() -> void:
	assert_eq(BiomeRegistry.get_biome("desert").surface_material, "sand")

func test_mountain_surface_material_is_gravel() -> void:
	assert_eq(BiomeRegistry.get_biome("mountain").surface_material, "gravel")

func test_forest_surface_material_defaults_to_dirt() -> void:
	assert_eq(BiomeRegistry.get_biome("forest").surface_material, "dirt")
