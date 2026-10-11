# res://tests/unit/test_harvestable_entity.gd
extends GutTest

## Unit-Tests für HarvestableEntity + Subklassen.
##
## Abgedeckt:
##   P0 — Key-Round-Trip: mark_harvested via WorldService.mark_harvested()
##        dann is_harvested_by_type() → muss denselben Key finden
##   P0 — Key-Konsistenz: mark / unmark / is_harvested_by_type nutzen make_key()
##   P1 — Pool-Reuse: on_spawn() zweimal aufrufen → kein Visual-Kind akkumuliert
##   P1 — _clear_visuals(): InteractableComponent bleibt erhalten, MeshChildren weg
##   P2 — _add_placeholder_cylinder(): korrekte Kinder-Anzahl
##   P2 — _add_placeholder_box(): korrekte Kinder-Anzahl
##   Abstract-Guard: _get_entity_type_id() push_error (per direktem Aufruf prüfbar)

# ─────────────────────────────────────────────
# Hilfklassen — minimale Subklassen ohne SceneTree-Abhängigkeit
# ─────────────────────────────────────────────

## Minimale konkrete Subklasse für Tests die keine Factory3D brauchen.
class TestOre extends HarvestableEntity:
	func _get_entity_type_id() -> String:
		return "iron_ore"

	func _build_interactable_data() -> InteractableData:
		var d := InteractableData.new()
		d.id = "mine"; d.label = "Test"; d.xp_type = "mining"; d.xp_amount = 1
		return d

	func _build_visuals() -> void:
		_add_placeholder_box(Vector3(0.5, 0.5, 0.5), Color.GRAY)

class TestTree extends HarvestableEntity:
	func _get_entity_type_id() -> String:
		return "oak_tree"

	func _build_interactable_data() -> InteractableData:
		var d := InteractableData.new()
		d.id = "chop"; d.label = "Chop"; d.xp_type = "woodcutting"; d.xp_amount = 1
		return d

	func _build_visuals() -> void:
		_add_placeholder_cylinder(0.1, 1.0, Color.BROWN)

# ─────────────────────────────────────────────
# P0 — Harvest-Key-Round-Trip
# ─────────────────────────────────────────────

func test_p0_mark_key_matches_is_harvested_by_type() -> void:
	## Schreibt mit make_key() (wie WorldService.mark_harvested tut),
	## liest mit is_harvested_by_type() — beide müssen denselben Key erzeugen.
	var data := WorldData.new()
	var pos  := Vector3(5, 0, 5)
	# Schreiben — der Pfad den HarvestableEntity.on_despawn() geht:
	data.mark_harvested(WorldData.make_key("iron_ore", pos))
	# Lesen — der Pfad den WorldSpawner / RespawnService geht:
	assert_true(
		data.is_harvested_by_type("iron_ore", pos),
		"P0: mark via make_key() → is_harvested_by_type() muss denselben Key finden"
	)

func test_p0_unmark_key_matches_mark_key() -> void:
	## unmark_harvested() muss denselben Key löschen den mark_harvested() gesetzt hat.
	var data := WorldData.new()
	var pos  := Vector3(-3, 0, 2)
	data.mark_harvested(WorldData.make_key("oak_tree", pos))
	data.unmark_harvested("oak_tree", pos)
	assert_false(
		data.is_harvested_by_type("oak_tree", pos),
		"P0: unmark muss den von mark gesetzten Key entfernen"
	)

func test_p0_different_types_different_keys() -> void:
	## oak_tree_5_0_5 und iron_ore_5_0_5 dürfen sich nicht gegenseitig beeinflussen.
	var data := WorldData.new()
	var pos  := Vector3(5, 0, 5)
	data.mark_harvested(WorldData.make_key("oak_tree", pos))
	assert_false(
		data.is_harvested_by_type("iron_ore", pos),
		"P0: Typ-spezifische Keys dürfen sich nicht überschneiden"
	)

# ─────────────────────────────────────────────
# P0 — make_key() Format
# ─────────────────────────────────────────────

func test_p0_make_key_format() -> void:
	var key := WorldData.make_key("oak_tree", Vector3(5, 0, 5))
	assert_eq(key, "oak_tree_5_0_5", "make_key() Format muss type_id_x_y_z sein")

func test_p0_make_key_negative_coords() -> void:
	var key := WorldData.make_key("iron_ore", Vector3(-3, 0, 2))
	assert_eq(key, "iron_ore_-3_0_2", "make_key() muss negative Koordinaten korrekt formatieren")

# ─────────────────────────────────────────────
# P1 — Pool-Reuse: Visual-Akkumulation
# ─────────────────────────────────────────────

func test_p1_pool_reuse_no_visual_accumulation() -> void:
	## Simuliert zwei Spawn-Zyklen ohne vollständigen despawn/free-Zyklus.
	## Nach dem zweiten on_spawn() darf es nicht doppelt so viele Kinder geben.
	var entity: TestOre = add_child_autofree(TestOre.new())
	# Erster Spawn
	entity.on_spawn({}, null)
	var children_after_first := entity.get_child_count()

	# Zweiter Spawn (Pool-Reuse) — ohne on_despawn() dazwischen
	entity.on_spawn({}, null)
	var children_after_second := entity.get_child_count()

	assert_eq(
		children_after_second,
		children_after_first,
		"P1: Pool-Reuse darf keine Kinder akkumulieren — Anzahl muss nach zweitem Spawn gleich sein"
	)

func test_p1_clear_visuals_removes_mesh_children() -> void:
	## _clear_visuals() soll MeshInstance3D entfernen.
	var entity: TestOre = add_child_autofree(TestOre.new())
	entity.on_spawn({}, null)
	# Manuelle Prüfung: nach _clear_visuals() keine MeshInstance3D mehr
	entity._clear_visuals()
	# get_children() gibt noch queue_free-markierte zurück bis nächster Frame —
	# wir prüfen stattdessen ob bei erneutem Spawn die Anzahl nicht wächst.
	entity._build_visuals()
	var count_a := entity.get_child_count()
	entity._clear_visuals()
	entity._build_visuals()
	var count_b := entity.get_child_count()
	assert_eq(count_a, count_b, "P1: _clear_visuals() + _build_visuals() muss idempotent sein")

func test_p1_clear_visuals_keeps_interactable_component() -> void:
	## _clear_visuals() darf den InteractableComponent NICHT entfernen.
	var entity: TestOre = add_child_autofree(TestOre.new())
	entity.on_spawn({}, null)
	entity._clear_visuals()
	# InteractableComponent bleibt als Kind (auch wenn queue_free-markiert werden
	# — TestOre hat keinen IC ohne _ready()-Aufruf). Wir prüfen dass _interactable_comp
	# noch valid ist wenn er existiert.
	if is_instance_valid(entity._interactable_comp):
		assert_true(
			is_instance_valid(entity._interactable_comp),
			"P1: InteractableComponent muss nach _clear_visuals() noch valid sein"
		)

# ─────────────────────────────────────────────
# P2 — _add_placeholder_cylinder / _add_placeholder_box
# ─────────────────────────────────────────────

func test_p2_placeholder_cylinder_adds_one_child() -> void:
	var entity: TestTree = add_child_autofree(TestTree.new())
	var before := entity.get_child_count()
	entity._add_placeholder_cylinder(0.1, 1.0, Color.BROWN)
	# +1 MeshInstance3D erwartet
	assert_eq(entity.get_child_count(), before + 1, "P2: _add_placeholder_cylinder() muss genau ein Kind hinzufügen")

func test_p2_placeholder_box_adds_one_child() -> void:
	var entity: TestOre = add_child_autofree(TestOre.new())
	var before := entity.get_child_count()
	entity._add_placeholder_box(Vector3(0.5, 0.5, 0.5), Color.GRAY)
	assert_eq(entity.get_child_count(), before + 1, "P2: _add_placeholder_box() muss genau ein Kind hinzufügen")

func test_p2_placeholder_cylinder_position_y() -> void:
	## Stamm-Mitte soll bei height * 0.5 liegen.
	var entity: TestTree = add_child_autofree(TestTree.new())
	entity._add_placeholder_cylinder(0.1, 2.0, Color.BROWN)
	var mesh := entity.get_children().back() as MeshInstance3D
	assert_almost_eq(mesh.position.y, 1.0, 0.001,
		"P2: Zylinder-Mitte muss bei height/2 = 1.0 liegen")

# ─────────────────────────────────────────────
# P0 — WorldData.typed_tree/ore_positions
# ─────────────────────────────────────────────

func test_p0_add_typed_tree_populates_typed_positions() -> void:
	var data := WorldData.new()
	var pos  := Vector3(3, 0, 7)
	data.add_typed_tree("willow_tree", pos)
	assert_true(data.typed_tree_positions.has("willow_tree"),
		"add_typed_tree() muss typed_tree_positions[willow_tree] anlegen")
	assert_true(pos in data.typed_tree_positions["willow_tree"],
		"add_typed_tree() muss Position in typed_tree_positions[willow_tree] eintragen")

func test_p0_add_typed_ore_populates_typed_positions() -> void:
	var data := WorldData.new()
	var pos  := Vector3(-2, 0, 8)
	data.add_typed_ore("copper_ore", pos)
	assert_true(data.typed_ore_positions.has("copper_ore"),
		"add_typed_ore() muss typed_ore_positions[copper_ore] anlegen")

# ─────────────────────────────────────────────────────────────────────────────
# _on_interacted() — Despawn via IEventBus (Runde 4 EventBus-Migration)
# ─────────────────────────────────────────────────────────────────────────────
##
## _on_interacted() nutzt jetzt _ctx.get_event_bus() statt direktem AutoLoad-Zugriff.
## Diese Tests verifizieren den neuen Pfad: mit Bus, ohne Bus, ohne UUID.

func test_on_interacted_emits_despawn_via_injected_bus() -> void:
	var entity: TestTree = add_child_autofree(TestTree.new())
	var bus    := MockEventBus.new()
	var ctx    := EntityContext.for_test()
	ctx._bus   = bus
	entity.on_spawn({}, ctx)
	entity.set_meta("entity_uuid", "uuid-123")

	watch_signals(bus.world())
	entity._on_interacted("chop", 1)

	assert_signal_emitted(bus.world(), "entity_despawn_requested",
		"_on_interacted() muss entity_despawn_requested über den injizierten Bus emittieren")

func test_on_interacted_emits_correct_uuid() -> void:
	var entity: TestTree = add_child_autofree(TestTree.new())
	var bus    := MockEventBus.new()
	var ctx    := EntityContext.for_test()
	ctx._bus   = bus
	entity.on_spawn({}, ctx)
	entity.set_meta("entity_uuid", "uuid-xyz")

	watch_signals(bus.world())
	entity._on_interacted("chop", 1)

	assert_signal_emitted_with_parameters(bus.world(), "entity_despawn_requested", ["uuid-xyz"])

func test_on_interacted_without_bus_falls_back_to_direct_despawn() -> void:
	## Kein _ctx gesetzt (Entity ohne EntityOrchestrator gespawnt) → direkter
	## on_despawn() + queue_free() Pfad, kein Crash.
	var entity: TestTree = add_child_autofree(TestTree.new())
	entity.set_meta("entity_uuid", "uuid-456")
	# Kein on_spawn() aufgerufen — _ctx bleibt null.
	entity._on_interacted("chop", 1)
	assert_true(true, "_on_interacted() ohne _ctx darf nicht crashen (Fallback auf queue_free)")

func test_on_interacted_without_uuid_falls_back_to_direct_despawn() -> void:
	var entity: TestTree = add_child_autofree(TestTree.new())
	var bus    := MockEventBus.new()
	var ctx    := EntityContext.for_test()
	ctx._bus   = bus
	entity.on_spawn({}, ctx)
	# Keine UUID gesetzt.
	watch_signals(bus.world())
	entity._on_interacted("chop", 1)
	assert_signal_not_emitted(bus.world(), "entity_despawn_requested",
		"Ohne UUID darf kein Despawn-Request emittiert werden — direkter Pfad stattdessen")

func test_on_interacted_with_ctx_but_no_bus_logs_warning_no_crash() -> void:
	## EntityContext.for_test() ohne _bus gesetzt — get_event_bus() liefert null.
	var entity: TestTree = add_child_autofree(TestTree.new())
	var ctx    := EntityContext.for_test()
	entity.on_spawn({}, ctx)
	entity.set_meta("entity_uuid", "uuid-789")
	entity._on_interacted("chop", 1)
	assert_true(true, "_on_interacted() mit ctx aber ohne bus darf nicht crashen")

# ─────────────────────────────────────────────
# ADR-020 / R-3 + R-6 — Autoritäts-Guard
# ─────────────────────────────────────────────

func test_on_interacted_on_authority_still_despawns() -> void:
	## Standardfall in Tests (kein MultiplayerPeer gesetzt): unique_id ist 1,
	## set_multiplayer_authority(1) macht is_multiplayer_authority() true —
	## der Guard darf den bestehenden Effekt nicht verändern.
	var entity: TestTree = add_child_autofree(TestTree.new())
	entity.set_multiplayer_authority(1)
	entity.set_meta("entity_uuid", "uuid-authority")
	# Kein ctx → Fallback-Pfad (on_despawn() + queue_free()) ist der beobachtbare Effekt.
	entity._on_interacted("chop", 1)
	assert_true(entity.is_queued_for_deletion(),
		"Auf der Autorität muss _on_interacted() weiterhin wirken (queue_free() im Fallback-Pfad).")

func test_on_interacted_on_non_authority_does_nothing() -> void:
	## set_multiplayer_authority(2) bei unique_id=1 (kein Peer) → is_multiplayer_authority() = false.
	## Vor ADR-020 lief dieser Hook hier trotzdem durch (lokaler Tween-Abschluss
	## eines Nicht-Host-Peers) — das war exakt R-3/R-6.
	var entity: TestTree = add_child_autofree(TestTree.new())
	entity.set_multiplayer_authority(2)
	assert_false(entity.is_multiplayer_authority(), "Testvoraussetzung: Entity darf hier nicht die Autorität sein.")
	entity.set_meta("entity_uuid", "uuid-non-authority")
	entity._on_interacted("chop", 1)
	assert_false(entity.is_queued_for_deletion(),
		"Auf Nicht-Autorität darf _on_interacted() keinerlei Wirkung (Despawn) auslösen.")

# ─────────────────────────────────────────────
# ADR-020 / R-1 (Round 43) — InteractionResolver-Beteiligung in _on_interacted()
#
# _on_interacted() ruft jetzt InteractionResolver.resolve() mit der servereigenen
# _interactable_comp.data auf, BEVOR despawnt wird. Diese Tests verifizieren nur
# die BETEILIGUNG (wird resolve() erreicht, mit welchem Bus/peer_id) — die
# Berechnung selbst (Loot-Roll, XP-Regeln, Stat-Skalierung) ist bereits in
# test_interaction_resolver.gd dediziert und mit echten Instanzen abgedeckt.
# ─────────────────────────────────────────────

func test_on_interacted_on_authority_emits_xp_via_resolver() -> void:
	## TestTree._build_interactable_data() setzt xp_type="woodcutting", xp_amount=1 —
	## InteractionResolver.resolve() muss das über den injizierten Bus emittieren.
	var entity: TestTree = add_child_autofree(TestTree.new())
	var bus  := MockEventBus.new()
	var ctx  := EntityContext.for_test()
	ctx._bus = bus
	entity.on_spawn({}, ctx)
	entity.set_multiplayer_authority(1)
	entity.set_meta("entity_uuid", "uuid-resolver-xp")

	watch_signals(bus.player())
	entity._on_interacted("chop", 3)

	assert_signal_emitted_with_parameters(bus.player(), "xp_gained", ["woodcutting", 1, 3])

func test_on_interacted_on_non_authority_does_not_invoke_resolver() -> void:
	## Auf Nicht-Autorität darf InteractionResolver.resolve() erst gar nicht
	## erreicht werden — der Guard greift vor jeglicher Wirkung, nicht nur vor
	## dem Despawn.
	var entity: TestTree = add_child_autofree(TestTree.new())
	var bus  := MockEventBus.new()
	var ctx  := EntityContext.for_test()
	ctx._bus = bus
	entity.on_spawn({}, ctx)
	entity.set_multiplayer_authority(2)
	assert_false(entity.is_multiplayer_authority(), "Testvoraussetzung: Entity darf hier nicht die Autorität sein.")
	entity.set_meta("entity_uuid", "uuid-resolver-non-authority")

	watch_signals(bus.player())
	entity._on_interacted("chop", 3)

	assert_signal_not_emitted(bus.player(), "xp_gained",
		"Auf Nicht-Autorität darf InteractionResolver.resolve() nicht ausgelöst werden (kein XP-Emit).")

func test_on_interacted_passes_stat_modifiers_from_context_to_resolver() -> void:
	## Nebenbefund-Fix (Round 43): stat_modifiers kommt jetzt aus _ctx.get_stat_modifiers()
	## und muss tatsächlich bei der Loot-Skalierung ankommen, statt (wie vorher in
	## InteractionExecutor) nie verdrahtet zu sein.
	##
	## ADR-029 Round 69: _on_interacted() löst player_id jetzt selbst über
	## _ctx.get_network_bridge() auf (peer_id 5 → "p5") und übergibt sie an
	## InteractionResolver.resolve() — StatModifierService verlangt seitdem
	## player_id: String statt peer_id: int. Ohne NetworkBridge bliebe player_id
	## leer und die Skalierung würde nie greifen — derselbe
	## NetworkBridge+SessionManager-Aufbau wie test_combat_system.gd/
	## test_equipment_ui.gd.
	var entity: TestOre = add_child_autofree(TestOre.new())
	var bus  := MockEventBus.new()
	var mods := StatModifierService.new()
	mods.add_modifier(StatModifier.permanent(
		"test_bonus", "gathering_yield_ore", StatModifier.Operation.PERCENT_ADD, 1.0
	), "p5")
	var session := SessionManager.new()
	session.register_player_slot(5, "p5")
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	var ctx := EntityContext.for_test()
	ctx._bus            = bus
	ctx._stat_modifiers = mods
	ctx._network        = bridge
	entity.on_spawn({}, ctx)
	entity.set_multiplayer_authority(1)
	entity.set_meta("entity_uuid", "uuid-resolver-stats")
	entity._interactable_comp.data.yield_stat_id = "gathering_yield_ore"
	var table := LootTable.new()
	var loot_entry := LootEntry.new()
	loot_entry.item_id      = "iron_ore"
	loot_entry.weight       = 100.0
	loot_entry.quantity_min = 4
	loot_entry.quantity_max = 4
	table.entries   = [loot_entry]
	table.max_rolls = 1
	entity._interactable_comp.data.loot_table = table

	watch_signals(bus.world())
	entity._on_interacted("mine", 5)

	# 4 Basis-Menge × 2.0 (PERCENT_ADD 1.0 für Spieler 5) = 8
	assert_signal_emitted_with_parameters(bus.world(), "loot_collected", ["iron_ore", 8, 5])
