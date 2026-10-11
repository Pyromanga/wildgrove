# res://tests/unit/test_mounts.gd
extends GutTest

## Tests fürs Reiten: MountDefinitions, PlayerMount (Regeln + Zustand), PetComponent (Reittier-Felder,
## Save-Round-Trip), MountController.find_nearest_mountable, Fähigkeits-Defaults, Wildesel-Spezies.

func _pet(species: String, pos := Vector3.ZERO, owner_peer := 1) -> PetComponent:
	var pet := PetComponent.new()
	pet._species_id = species
	pet._owner_peer_id = owner_peer
	add_child_autofree(pet)   # im Baum, sonst meldet global_position Engine-Fehler (GUT: "Unexpected Errors")
	pet.global_position = pos
	return pet

# ── Definitionen ────────────────────────────────

func test_mount_species_are_faster_than_walking() -> void:
	for id in MountDefinitions.DEFINITIONS.keys():
		assert_gt(MountDefinitions.speed_mult_for(id), 1.0, "%s muss schneller als Laufen sein" % id)
		assert_gt(MountDefinitions.seat_height_for(id), 0.0)
		assert_ne(MountDefinitions.label_for(id), "")

func test_horse_is_faster_than_donkey() -> void:
	assert_gt(MountDefinitions.speed_mult_for("horse"), MountDefinitions.speed_mult_for("donkey"))

func test_unknown_species_is_neutral() -> void:
	assert_false(MountDefinitions.is_mountable("wolf"))
	assert_eq(MountDefinitions.speed_mult_for("wolf"), 1.0)
	assert_eq(MountDefinitions.seat_height_for(""), 0.0)

func test_all_mount_species_exist_in_species_db() -> void:
	for id in MountDefinitions.DEFINITIONS.keys():
		assert_true(AnimalSpeciesDB.SPECIES.has(id), "%s fehlt in AnimalSpeciesDB" % id)
		assert_false(String(id).contains("_"), "species_id darf kein '_' enthalten (Node-Name-Präfix)")

func test_mount_species_have_no_default_abilities() -> void:
	assert_eq(PetAbilities.default_for_species("horse"), [] as Array[String])
	assert_eq(PetAbilities.default_for_species("donkey"), [] as Array[String])

# ── can_mount ───────────────────────────────────

func test_can_mount_ok_in_range() -> void:
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, _pet("horse", Vector3(2, 0, 0)), false), "")

func test_can_mount_rejections() -> void:
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, null, false), "no_pet")
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, _pet("horse"), true), "already_mounted")
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, _pet("wolf"), false), "not_mountable")
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, _pet("horse", Vector3.ZERO, 2), false), "not_owner")
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, _pet("horse", Vector3(9, 0, 0)), false), "too_far")
	var taken := _pet("horse")
	taken.set_ridden(true)
	assert_eq(PlayerMount.can_mount(Vector3.ZERO, 1, taken, false), "taken")

# ── PlayerMount-Zustand ─────────────────────────

func test_mount_and_dismount_state() -> void:
	var m := PlayerMount.new()
	var pet := _pet("horse")
	pet.collision_layer = 4
	pet.collision_mask = 3
	assert_false(m.is_mounted())
	assert_eq(m.speed_multiplier(), 1.0)
	m.mount(pet)
	assert_true(m.is_mounted())
	assert_true(pet.is_ridden())
	assert_eq(pet.collision_layer, 0)
	assert_almost_eq(m.speed_multiplier(), MountDefinitions.speed_mult_for("horse"), 0.0001)
	assert_almost_eq(m.seat_height(), MountDefinitions.seat_height_for("horse"), 0.0001)
	m.dismount()
	assert_false(m.is_mounted())
	assert_false(pet.is_ridden())
	assert_eq(pet.collision_layer, 4, "Kollision wird beim Absteigen wiederhergestellt")
	assert_eq(pet.collision_mask, 3)
	assert_eq(m.speed_multiplier(), 1.0)
	assert_eq(m.seat_height(), 0.0)

func test_dismount_without_mount_is_noop() -> void:
	assert_eq(PlayerMount.new().dismount(), Vector3.ZERO)

func test_sync_pet_follows_rider() -> void:
	var m := PlayerMount.new()
	var pet := _pet("donkey")
	m.mount(pet)
	pet.velocity = Vector3(3, 0, 0)
	m.sync_pet(Vector3(5, 1, -2), 1.25)
	assert_eq(pet.global_position, Vector3(5, 1, -2))
	assert_almost_eq(pet.rotation.y, 1.25, 0.0001)
	assert_eq(pet.velocity, Vector3.ZERO)

func test_freed_pet_ends_mount_state() -> void:
	var m := PlayerMount.new()
	var pet := _pet("horse")
	m.mount(pet)
	remove_child(pet)
	pet.free()
	assert_false(m.is_mounted())
	assert_eq(m.speed_multiplier(), 1.0)

func test_ridden_pet_does_not_move_on_its_own() -> void:
	var pet := _pet("horse")
	pet.set_ridden(true)
	pet.velocity = Vector3(1, 0, 0)
	pet._physics_process(0.1)   # Autorität (ohne Peer) → Guard greift vor jeder Bewegung
	assert_eq(pet.velocity, Vector3(1, 0, 0), "Geritten: keine eigene Bewegungslogik")

func test_set_ridden_releases_ability_movement() -> void:
	var pet := _pet("horse")
	var claimer: Node = autofree(Node.new())
	pet.request_movement(claimer, Vector3(10, 0, 0), 1.0)
	pet.set_ridden(true)
	assert_false(pet.is_movement_claimed_by(claimer))

# ── Pet-Felder / Save ───────────────────────────

func test_pet_species_roundtrip_through_save_state() -> void:
	var pet := _pet("horse")
	var state := pet.get_save_state()
	assert_eq(state["species_id"], "horse")
	assert_true(pet.is_mountable())

func test_mountable_pet_gets_follow_speed_on_spawn() -> void:
	var pet := PetComponent.new()
	add_child_autofree(pet)
	pet.on_spawn({"species_id": "horse", "speed": 3.0, "owner_peer_id": 1})
	assert_true(pet._speed >= MountDefinitions.follow_speed_for("horse"))
	assert_eq(pet.get_species_id(), "horse")

func test_old_save_without_species_is_no_mount() -> void:
	var pet := PetComponent.new()
	add_child_autofree(pet)
	pet.on_spawn({"speed": 3.0, "owner_peer_id": 1})
	assert_eq(pet.get_species_id(), "")
	assert_false(pet.is_mountable())

# ── Controller-Auswahl ──────────────────────────

func test_find_nearest_picks_closest_mountable_own_pet() -> void:
	var far := _pet("horse", Vector3(3.5, 0, 0))
	var near := _pet("donkey", Vector3(1, 0, 0))
	var wolf := _pet("wolf", Vector3(0.5, 0, 0))
	var foreign := _pet("horse", Vector3(0.2, 0, 0), 2)
	var found := MountController.find_nearest_mountable(Vector3.ZERO, 1, [far, near, wolf, foreign])
	assert_eq(found, near)

func test_find_nearest_none_in_range() -> void:
	assert_null(MountController.find_nearest_mountable(Vector3.ZERO, 1, [_pet("horse", Vector3(20, 0, 0))]))
	assert_null(MountController.find_nearest_mountable(Vector3.ZERO, 1, []))

func test_find_nearest_skips_ridden() -> void:
	var p := _pet("horse", Vector3(1, 0, 0))
	p.set_ridden(true)
	assert_null(MountController.find_nearest_mountable(Vector3.ZERO, 1, [p]))
