## tests/unit/test_professions.gd
## Berufe: ProfessionCatalog, WorkSchedule, WorkAnimator, ProfessionNPC, Tausch, Gebäude-Verdrahtung.
## Läuft headless (Godot 4.3 + GUT).

extends GutTest

const ITEM_DIR := "res://data/items/"

func _item_ids() -> Dictionary:
	var ids: Dictionary = {}
	for path: String in DataManifest.ITEMS:
		var res: Resource = load(path)
		if res != null:
			ids[String(res.get("id"))] = true
	return ids

# ── Katalog ─────────────────────────────────────────────

func test_catalog_has_unique_ids_and_types() -> void:
	var ids: Dictionary = {}
	var types: Dictionary = {}
	for p: Dictionary in ProfessionCatalog.all():
		assert_false(ids.has(p["id"]), "doppelte id %s" % p["id"])
		assert_false(types.has(p["npc_type"]), "doppelter npc_type %s" % p["npc_type"])
		ids[p["id"]] = true
		types[p["npc_type"]] = true
	assert_gte(ids.size(), 14)

func test_every_profession_is_fully_wired() -> void:
	var items := _item_ids()
	for p: Dictionary in ProfessionCatalog.all():
		var id: String = p["id"]
		assert_true(BuildingRecipes.has_type(String(p["building"])), "%s: Gebäude fehlt." % id)
		var slots: Array = BuildingRecipes.npc_slots(String(p["building"]))
		var found := false
		for e: Array in slots:
			if String(e[0]) == String(p["npc_type"]):
				found = true
		assert_true(found, "%s: Gebäude hat keinen Slot für den Beruf." % id)
		assert_true(ResourceLoader.exists(String(p["script"])), "%s: Skript fehlt." % id)
		assert_eq(WorkSchedule.validate(p["shift"]), "", "%s: Tagesablauf ungültig." % id)
		assert_true(WorkAnimator.STYLES.has(String(p["work"])), "%s: unbekannter Arbeitsstil." % id)
		assert_true(NPCProps.PROP_IDS.has(String(p["prop"])), "%s: unbekanntes Requisit." % id)
		assert_true(String(p["fact"]).begins_with("Wusstest du?"), "%s: Fakt braucht 'Wusstest du?'." % id)
		assert_gt((p["lines"] as Array).size(), 2)
		var look: Dictionary = CharacterLook.sanitize(p["look"])
		for key: String in (p["look"] as Dictionary):
			assert_eq(look[key], (p["look"] as Dictionary)[key], "%s: look.%s ist keine gültige ID." % [id, key])
		if p.has("trade"):
			var t: Dictionary = p["trade"]
			for item: String in (t["consumes"] as Dictionary):
				assert_true(items.has(item), "%s: Zutat %s unbekannt." % [id, item])
			for item: String in (t["gives"] as Dictionary):
				assert_true(items.has(item), "%s: Ergebnis %s unbekannt." % [id, item])

func test_one_profession_per_building() -> void:
	var seen: Dictionary = {}
	for p: Dictionary in ProfessionCatalog.all():
		assert_false(seen.has(p["building"]), "Gebäude %s doppelt belegt." % p["building"])
		seen[p["building"]] = true

func test_style_for_name_matches_whole_words_both_genders() -> void:
	assert_eq(ProfessionCatalog.style_for_name("Töpferin Berta")["prop"], "pot")
	assert_eq(ProfessionCatalog.style_for_name("Töpfer Anselm")["prop"], "pot")
	assert_true(ProfessionCatalog.style_for_name("Siedler Anselm").is_empty())
	assert_true(ProfessionCatalog.style_for_name("Töpfermeister Anselm").is_empty())

func test_profession_look_and_prop_reach_npc_look() -> void:
	var spec := NPCLook.resolve("Schmied Gero", Color(0.32, 0.30, 0.30), {"sex": "male"})
	assert_eq(spec["prop"], "hammer")
	assert_eq(spec["look"]["shirt_style"], "vest")

func test_all_profession_props_build() -> void:
	for p: Dictionary in ProfessionCatalog.all():
		var root := Node3D.new()
		add_child_autofree(root)
		NPCVisualBuilder.build(root, "%s Anselm" % p["title_m"], p["body_color"])
		assert_not_null(root.get_node_or_null("Visual"))

# ── Tagesablauf ─────────────────────────────────────────

func test_schedule_states() -> void:
	var shift := {"start": 7.0, "break": [12.0, 13.0], "end": 18.0, "free_until": 21.0}
	assert_eq(WorkSchedule.state_at(9.0, shift), WorkSchedule.State.WORK)
	assert_eq(WorkSchedule.state_at(12.5, shift), WorkSchedule.State.BREAK)
	assert_eq(WorkSchedule.state_at(19.0, shift), WorkSchedule.State.FREE)
	assert_eq(WorkSchedule.state_at(23.0, shift), WorkSchedule.State.SLEEP)
	assert_eq(WorkSchedule.state_at(3.0, shift), WorkSchedule.State.SLEEP)
	assert_eq(WorkSchedule.state_at(7.0, shift), WorkSchedule.State.WORK)

func test_schedule_wraps_midnight() -> void:
	var shift := {"start": 20.0, "end": 4.0, "free_until": 6.0}
	assert_eq(WorkSchedule.state_at(23.0, shift), WorkSchedule.State.WORK)
	assert_eq(WorkSchedule.state_at(2.0, shift), WorkSchedule.State.WORK)
	assert_eq(WorkSchedule.state_at(5.0, shift), WorkSchedule.State.FREE)
	assert_eq(WorkSchedule.state_at(12.0, shift), WorkSchedule.State.SLEEP)

func test_schedule_validate_rejects_bad_break() -> void:
	assert_ne(WorkSchedule.validate({"start": 7.0, "end": 12.0, "free_until": 14.0, "break": [15.0, 16.0]}), "")
	assert_ne(WorkSchedule.validate({"start": 7.0}), "")

func test_every_profession_has_all_states_over_a_day() -> void:
	for p: Dictionary in ProfessionCatalog.all():
		var seen: Dictionary = {}
		for i in range(48):
			seen[WorkSchedule.state_at(float(i) * 0.5, p["shift"])] = true
		assert_true(seen.has(WorkSchedule.State.WORK) and seen.has(WorkSchedule.State.SLEEP), "%s: nie Arbeit oder nie Schlaf." % p["id"])

# ── Arbeitsbewegung ─────────────────────────────────────

func test_pose_is_bounded_and_moves() -> void:
	for style: String in WorkAnimator.STYLES:
		var lo := 99.0
		var hi := -99.0
		for i in range(200):
			var pose: Dictionary = WorkAnimator.pose(style, float(i) * 0.05)
			assert_lt(absf(float(pose["pitch"])), 0.4, style)
			assert_lt(absf(float(pose["roll"])), 0.3, style)
			lo = minf(lo, float(pose["pitch"]) + float(pose["roll"]))
			hi = maxf(hi, float(pose["pitch"]) + float(pose["roll"]))
		assert_gt(hi - lo, 0.01, "%s bewegt sich nicht." % style)
	assert_eq(WorkAnimator.pose("unknown", 1.0)["pitch"], 0.0)

# ── NPC ─────────────────────────────────────────────────

func _make(script_path: String, pos: Vector3 = Vector3(10, 0, 20)) -> ProfessionNPC:
	var npc: ProfessionNPC = load(script_path).new()
	npc.position = pos
	add_child_autofree(npc)
	return npc

func test_npc_gets_profession_name_and_gender() -> void:
	var seen_f := false
	var seen_m := false
	for i in range(40):
		var npc := _make("res://scripts/entities/profession/PotterNPC.gd", Vector3(float(i) * 7.3, 0, float(i) * 3.1))
		if npc.npc_display_name.begins_with("Töpferin "):
			seen_f = true
		elif npc.npc_display_name.begins_with("Töpfer "):
			seen_m = true
	assert_true(seen_f and seen_m, "Beide Titel müssen vorkommen.")

func test_npc_sleeps_at_night_and_works_by_day() -> void:
	var npc := _make("res://scripts/entities/profession/BakerNPC.gd")
	npc.set_hour_override(9.0)
	assert_true(npc.visible)
	assert_eq(npc.get_state(), WorkSchedule.State.WORK)
	assert_true(npc.get_node("WorkAnimator").active)
	npc.set_hour_override(23.0)
	assert_false(npc.visible)
	assert_eq(npc.collision_layer, 0)
	assert_false(npc.get_node("WorkAnimator").active)
	for c in npc.get_children():
		if c is InteractableComponent:
			assert_false((c as InteractableComponent).enabled)
	npc.set_hour_override(12.0 + 0.0)
	npc.set_hour_override(14.0)
	assert_true(npc.visible)
	for c in npc.get_children():
		if c is InteractableComponent:
			assert_true((c as InteractableComponent).enabled)

func test_npc_without_clock_always_works() -> void:
	var npc := _make("res://scripts/entities/profession/MillerNPC.gd")
	assert_eq(npc.get_state(), WorkSchedule.State.WORK)
	assert_true(npc.visible)

func test_inspect_text_mentions_state_and_rotates_to_fact() -> void:
	var npc := _make("res://scripts/entities/profession/GlassmakerNPC.gd")
	npc.set_hour_override(10.0)
	assert_string_contains(npc.build_text(0), "bläst Glas")
	npc.set_hour_override(19.5)
	assert_string_contains(npc.build_text(0), "Feierabend")
	var saw_fact := false
	for step in range(6):
		if npc.build_text(step).contains("Wusstest du?"):
			saw_fact = true
	assert_true(saw_fact)

func test_trade_component_only_for_professions_with_trade() -> void:
	var potter := _make("res://scripts/entities/profession/PotterNPC.gd")
	assert_not_null(potter.get_node_or_null("ProfessionTradeInteractable"))
	var tanner := _make("res://scripts/entities/profession/TannerNPC.gd", Vector3(1, 0, 1))
	assert_null(tanner.get_node_or_null("ProfessionTradeInteractable"))

func test_trade_def_uses_structure_use_contract() -> void:
	var def := ProfessionTrade.make_def(ProfessionCatalog.get_profession("potter")["trade"], "potter")
	assert_true(def.has_use())
	assert_eq(def.use_consumes["dirt"], 4)
	assert_eq(def.use_gives["clay_jug"], 1)

func test_every_npc_type_registers() -> void:
	for p: Dictionary in ProfessionCatalog.all():
		var script: GDScript = load(String(p["script"]))
		assert_not_null(script, p["id"])
		var inst: Object = script.new()
		assert_true(inst is ProfessionNPC)
		assert_eq((inst as ProfessionNPC).get_profession()["id"], p["id"])
		inst.free()
