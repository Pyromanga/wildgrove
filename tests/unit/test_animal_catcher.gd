# res://tests/unit/test_animal_catcher.gd
extends GutTest

## Unit-Tests für AnimalCatcher.catch_animal() — ADR-015 Phase 4/5.
##
## Vor Phase 5 riet catch_animal() den owner_peer_id über
## animal.get_multiplayer().get_unique_id() — eine Näherung, weil die
## Interaktion selbst keine Spieler-Identität trug. Seit Phase 4/5 kommt
## peer_id echt aus der Interaktion (InteractionExecutor → interacted-Signal
## → AnimalBase._on_interacted()) und wird hier nur noch entgegengenommen,
## nicht mehr geraten.
##
## Abgedeckt:
##   - catch_animal() gibt peer_id als owner_peer_id an spawn_entity() weiter
##   - catch_animal() gibt peer_id auch im config-Dictionary weiter
##   - catch_animal() ohne SceneTree-Membership: sauberer Abbruch (null), kein Crash

class MockWorldService extends WorldService:
	var last_type_id:  String     = ""
	var last_position: Vector3    = Vector3.ZERO
	var last_config:   Dictionary = {}
	var last_peer_id:  int        = -1
	var _pet_to_return: PetComponent = null

	func spawn_entity(type_id: String, position: Vector3, config: Dictionary = {}, peer_id: int = 1) -> Node3D:
		last_type_id  = type_id
		last_position = position
		last_config   = config
		last_peer_id  = peer_id
		return _pet_to_return

func _make_animal() -> AnimalBase:
	var animal := AnimalBase.new()
	add_child_autofree(animal)
	return animal

func test_catch_animal_forwards_peer_id_as_spawn_peer_id() -> void:
	var animal := _make_animal()
	var world  := MockWorldService.new()
	world._pet_to_return = PetComponent.new()
	var ctx := EntityContext.for_test()
	ctx._world = world
	animal.on_spawn({}, ctx)

	AnimalCatcher.catch_animal(animal, 3)

	assert_eq(world.last_peer_id, 3,
		"catch_animal() muss den echten peer_id als peer_id an spawn_entity() weitergeben")

func test_catch_animal_puts_peer_id_in_config_as_owner_peer_id() -> void:
	var animal := _make_animal()
	var world  := MockWorldService.new()
	world._pet_to_return = PetComponent.new()
	var ctx := EntityContext.for_test()
	ctx._world = world
	animal.on_spawn({}, ctx)

	AnimalCatcher.catch_animal(animal, 5)

	assert_eq(world.last_config.get("owner_peer_id"), 5,
		"config.owner_peer_id muss dem übergebenen peer_id entsprechen, nicht geraten sein")

func test_catch_animal_different_peer_ids_produce_different_owners() -> void:
	## Kernbeweis für Phase 5: zwei unterschiedliche Fänger dürfen nicht auf
	## denselben (geratenen) owner_peer_id kollabieren.
	var animal_a := _make_animal()
	var animal_b := _make_animal()
	var world    := MockWorldService.new()
	world._pet_to_return = PetComponent.new()
	var ctx := EntityContext.for_test()
	ctx._world = world
	animal_a.on_spawn({}, ctx)
	animal_b.on_spawn({}, ctx)

	AnimalCatcher.catch_animal(animal_a, 1)
	var owner_a: int = world.last_peer_id
	AnimalCatcher.catch_animal(animal_b, 2)
	var owner_b: int = world.last_peer_id

	assert_ne(owner_a, owner_b,
		"Zwei unterschiedliche Fänger (peer_id 1 vs 2) müssen unterschiedliche owner_peer_id ergeben")

func test_catch_animal_not_in_tree_returns_null_no_crash() -> void:
	var animal := AnimalBase.new()  # absichtlich NICHT im SceneTree
	var result := AnimalCatcher.catch_animal(animal, 1)
	assert_null(result, "catch_animal() muss bei Despawn-Race (nicht im Tree) null liefern, nicht crashen")
	animal.free()

# ─────────────────────────────────────────────
# ADR-020 / R-3 — Autoritäts-Guard in _on_interacted()
# ─────────────────────────────────────────────

func test_on_interacted_catch_animal_on_authority_invokes_catcher() -> void:
	var animal := _make_animal()
	animal.set_multiplayer_authority(1)  # unique_id ohne Peer ist 1 → true
	var world  := MockWorldService.new()
	world._pet_to_return = PetComponent.new()
	var ctx := EntityContext.for_test()
	ctx._world = world
	animal.on_spawn({}, ctx)

	animal._on_interacted("catch_animal", 7)

	assert_eq(world.last_peer_id, 7,
		"Auf der Autorität muss _on_interacted('catch_animal') weiterhin AnimalCatcher.catch_animal() auslösen.")

func test_on_interacted_catch_animal_on_non_authority_does_nothing() -> void:
	## Vor ADR-020 lief catch_animal() hier auf JEDEM Peer, der lokal zuerst den
	## Tween beendete — auf Tier 2/3 wäre das ein zweites, konkurrierendes Pet-
	## Spawn-Ereignis für dieselbe Interaktion gewesen, sobald der Request auch
	## die echte Autorität erreicht (R-3).
	var animal := _make_animal()
	animal.set_multiplayer_authority(2)
	assert_false(animal.is_multiplayer_authority(), "Testvoraussetzung: Entity darf hier nicht die Autorität sein.")
	var world  := MockWorldService.new()
	world._pet_to_return = PetComponent.new()
	var ctx := EntityContext.for_test()
	ctx._world = world
	animal.on_spawn({}, ctx)

	animal._on_interacted("catch_animal", 7)

	assert_eq(world.last_peer_id, -1,
		"Auf Nicht-Autorität darf _on_interacted('catch_animal') AnimalCatcher.catch_animal() NICHT auslösen.")
