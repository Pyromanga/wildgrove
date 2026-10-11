# res://tests/unit/test_smithing_content.gd
extends GutTest

## Konsistenz-Tests für Schmiede-Content (Rezepte <-> Items <-> Stationen <-> Bauteile).
##
## Warum: Schmieden besteht aus Teilen, die nur über Strings zusammenhängen (SmithingRecipe.station
## <-> BuildPieceDefinition.station_kind <-> DataManifest.* <-> Item-Ids <-> Skill-Id). Fehlt ein
## Glied, bricht nichts laut — das Rezept ist dann einfach nie erreichbar. Genau das war der Stand
## VOR der Integration: Rezepte, Events und Skill existierten, aber kein Bauteil bot die Station
## an. Diese Tests machen solche stillen Lücken laut.
##
## Abgedeckt:
##   - Jedes Rezept ist strukturell gültig, in DataManifest.SMITHING_RECIPES, id == Dateiname
##   - Alle Zutaten/Werkzeuge/Ergebnisse sind registrierte Items (DataManifest.ITEMS)
##   - Jede Rezept-Station wird von mindestens einem Bauteil angeboten (station_kind)
##   - Jedes Stations-Bauteil: Kind.TARGET, gültige Station, passende PropShape, Baukosten
##     referenzieren registrierte Items
##   - Hochofen-Baukosten sind OHNE Schmieden beschaffbar (sonst Henne-Ei: erster Ofen unbaubar)
##   - Kein Bauteil verlangt noch rohes Erz, das ein Rezept zum Barren veredelt (Verzahnung Bauen/Schmelzen)
##   - Skill "smithing" ist registriert; Haus-Vorlage "Schmiede" referenziert nur vorhandene Bauteile

func _manifest_item_ids() -> Dictionary:
	var ids: Dictionary = {}
	for path: String in DataManifest.ITEMS:
		var def := load(path) as ItemDefinition
		if def != null:
			ids[def.id] = true
	return ids

func _recipes() -> Array[SmithingRecipe]:
	var out: Array[SmithingRecipe] = []
	for path: String in DataManifest.SMITHING_RECIPES:
		var r := load(path) as SmithingRecipe
		if r != null:
			out.append(r)
	return out

func _pieces() -> Dictionary:
	var out: Dictionary = {}
	for path: String in DataManifest.BUILD_PIECES:
		var d := load(path) as BuildPieceDefinition
		if d != null:
			out[d.id] = d
	return out

func test_every_recipe_file_is_in_manifest() -> void:
	var dir := DirAccess.open("res://data/smithing_recipes")
	assert_not_null(dir, "data/smithing_recipes fehlt")
	if dir == null:
		return
	var in_manifest: Dictionary = {}
	for path: String in DataManifest.SMITHING_RECIPES:
		in_manifest[path] = true
	for f in dir.get_files():
		if f.ends_with(".tres"):
			assert_true(in_manifest.has("res://data/smithing_recipes/" + f), "%s fehlt in DataManifest.SMITHING_RECIPES" % f)

func test_recipes_are_valid_and_unique() -> void:
	var seen: Dictionary = {}
	for path: String in DataManifest.SMITHING_RECIPES:
		var r := load(path) as SmithingRecipe
		assert_not_null(r, "%s ist kein SmithingRecipe" % path)
		if r == null:
			continue
		assert_eq(r.validation_errors(), [] as Array[String], path)
		assert_false(seen.has(r.id), "doppelte Rezept-ID %s" % r.id)
		seen[r.id] = true
		assert_eq(path.get_file().get_basename(), r.id, "Dateiname != id: %s" % path)

func test_recipe_items_are_registered() -> void:
	var items := _manifest_item_ids()
	for r in _recipes():
		for item_id in r.referenced_item_ids():
			assert_true(items.has(item_id), "Rezept %s: Item '%s' nicht in DataManifest.ITEMS" % [r.id, item_id])

func test_smithing_skill_is_registered() -> void:
	var ids: Array[String] = []
	for path: String in DataManifest.SKILLS:
		var def := load(path) as SkillDefinition
		if def != null:
			ids.append(def.id)
	assert_true(ids.has(SmithingService.SKILL_ID))

func test_every_recipe_station_is_offered_by_a_build_piece() -> void:
	var offered: Dictionary = {}
	for d: BuildPieceDefinition in _pieces().values():
		if d.is_station():
			offered[d.station_kind] = true
	for r in _recipes():
		assert_true(offered.has(r.station), "Rezept %s braucht Station '%s' — kein Bauteil bietet sie an" % [r.id, r.station])

func test_station_pieces_are_well_formed() -> void:
	var items := _manifest_item_ids()
	var found := 0
	for d: BuildPieceDefinition in _pieces().values():
		if not d.is_station():
			continue
		found += 1
		assert_true(SmithingRecipe.STATIONS.has(d.station_kind), "%s: unbekannte Station '%s'" % [d.id, d.station_kind])
		assert_eq(d.kind, BuildPieceDefinition.Kind.TARGET, "%s muss ein TARGET sein" % d.id)
		assert_false(d.cost.is_empty(), "%s ohne Baukosten" % d.id)
		for item_id in d.cost.keys():
			assert_true(items.has(String(item_id)), "%s: Baukosten-Item '%s' unbekannt" % [d.id, item_id])
	assert_gte(found, 2, "Hochofen UND Amboss erwartet")

func test_furnace_and_anvil_shapes() -> void:
	var pieces := _pieces()
	assert_true(pieces.has("furnace"))
	assert_true(pieces.has("anvil"))
	var furnace: BuildPieceDefinition = pieces["furnace"]
	var anvil: BuildPieceDefinition = pieces["anvil"]
	assert_eq(furnace.station_kind, SmithingRecipe.STATION_FURNACE)
	assert_eq(anvil.station_kind, SmithingRecipe.STATION_ANVIL)
	assert_eq(furnace.prop_shape, BuildPieceDefinition.PropShape.FURNACE)
	assert_eq(anvil.prop_shape, BuildPieceDefinition.PropShape.ANVIL)
	assert_true(furnace.has_light(), "Hochofen glüht")
	assert_false(anvil.has_light())

func test_furnace_is_buildable_without_smithing() -> void:
	# Henne-Ei: der Hochofen ist die Voraussetzung für JEDEN Barren. Seine Baukosten dürfen deshalb
	# keinen Gegenstand enthalten, den ein Rezept erzeugt.
	var produced: Dictionary = {}
	for r in _recipes():
		produced[r.output_item_id] = true
	var furnace: BuildPieceDefinition = _pieces().get("furnace")
	assert_not_null(furnace)
	for item_id in furnace.cost.keys():
		assert_false(produced.has(String(item_id)), "Hochofen-Baukosten enthalten '%s', das erst geschmiedet wird" % item_id)

func test_anvil_costs_smithed_iron() -> void:
	# Die gewollte Verzahnung: der Amboss verbraucht einen Barren, den NUR der Hochofen liefert.
	var anvil: BuildPieceDefinition = _pieces().get("anvil")
	assert_not_null(anvil)
	assert_true(anvil.cost.has("iron_ingot"))

func test_no_build_piece_still_costs_raw_ore_that_smelting_refines() -> void:
	var refined_from_ore: Dictionary = {}
	for r in _recipes():
		if r.station == SmithingRecipe.STATION_FURNACE:
			for item_id in r.inputs.keys():
				if String(item_id).ends_with("_ore"):
					refined_from_ore[String(item_id)] = r.output_item_id
	for d: BuildPieceDefinition in _pieces().values():
		for item_id in d.cost.keys():
			assert_false(refined_from_ore.has(String(item_id)),
				"%s kostet rohes '%s' statt '%s' — Bauen und Schmelzen greifen sonst nicht ineinander" % [d.id, item_id, refined_from_ore.get(String(item_id), "")])

func test_smithy_template_references_existing_pieces() -> void:
	var pieces := _pieces()
	var found := false
	for path: String in DataManifest.HOUSE_TEMPLATES:
		var t := load(path) as HouseTemplateDefinition
		if t == null or t.id != "smithy":
			continue
		found = true
		var has_furnace := false
		for entry: Dictionary in t.pieces:
			var pid := String(entry.get("piece_id", ""))
			assert_true(pieces.has(pid), "Schmiede-Vorlage: Bauteil '%s' unbekannt" % pid)
			if pieces.has(pid):
				assert_eq(int(entry.get("kind", -1)), (pieces[pid] as BuildPieceDefinition).kind, "kind-Redundanz stimmt nicht für %s" % pid)
			has_furnace = has_furnace or pid == "furnace"
		assert_true(has_furnace, "die Schmiede-Vorlage muss einen Hochofen enthalten")
	assert_true(found, "Haus-Vorlage 'smithy' fehlt in DataManifest.HOUSE_TEMPLATES")

func test_smithy_template_is_buildable_from_scratch() -> void:
	# Eine Haus-Vorlage wird atomar platziert (alle Materialien auf einmal). Enthielte sie den
	# Amboss, bräuchte sie Barren, die es ohne Hochofen nicht gibt.
	var pieces := _pieces()
	var produced: Dictionary = {}
	for r in _recipes():
		produced[r.output_item_id] = true
	for path: String in DataManifest.HOUSE_TEMPLATES:
		var t := load(path) as HouseTemplateDefinition
		if t == null or t.id != "smithy":
			continue
		var total := t.total_cost(func(pid: String): return pieces.get(pid))
		for item_id in total.keys():
			assert_false(produced.has(String(item_id)), "Schmiede-Vorlage braucht geschmiedetes '%s'" % item_id)
