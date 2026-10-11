# res://tests/unit/test_interaction_sensor_manual_target.gd
extends GutTest

## Regressionstest für die Tap-Zielauswahl (InteractionTargetPicker,
## "auf Bäume klicken wie in RuneScape/Minecraft"): InteractionSensor.get_closest()
## muss ein per set_manual_target() gewähltes Ziel bevorzugen, SOLANGE es
## tatsächlich in Reichweite (Overlap) ist — und automatisch auf die normale
## Distanz-Auswahl zurückfallen, sobald es das nicht mehr ist (Spieler entfernt
## sich, Ziel despawnt) statt ein unerreichbares Ziel weiter zu bevorzugen.

func _make_sensor() -> Dictionary:
	var owner_body := StaticBody3D.new()
	owner_body.name = "OwnerPlayer"
	add_child_autofree(owner_body)

	var sensor := InteractionSensor.new()
	var sensor_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	sensor_shape.shape = sphere
	sensor.add_child(sensor_shape)
	sensor.monitoring = true
	sensor.monitorable = false
	owner_body.add_child(sensor)

	return {"owner": owner_body, "sensor": sensor}

func _make_target(name: String, pos: Vector3) -> StaticBody3D:
	var target := StaticBody3D.new()
	target.name = name
	target.add_to_group("interactable")
	target.global_position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 1.8, 0.9)
	shape.shape = box
	target.add_child(shape)
	add_child_autofree(target)
	return target

func test_manual_target_preferred_over_nearer_candidate_when_in_range() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]

	var near_tree := _make_target("NearTree", Vector3(0.5, 0, 0))
	var far_tree := _make_target("FarTree", Vector3(2.0, 0, 0))

	for i in range(4):
		await get_tree().physics_frame

	# Ohne Tap-Auswahl: normale Distanz-Auswahl liefert das nähere Ziel.
	assert_eq(sensor.get_closest(), near_tree)

	# Spieler tippt explizit auf das weiter entfernte (aber noch in Reichweite
	# befindliche) Ziel — muss ab jetzt bevorzugt werden.
	sensor.set_manual_target(far_tree)
	assert_eq(sensor.get_closest(), far_tree,
		"Tap-gewähltes Ziel muss Vorrang vor der reinen Distanz-Auswahl haben.")

func test_manual_target_falls_back_when_out_of_range() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]

	var near_tree := _make_target("NearTree", Vector3(0.5, 0, 0))
	var far_away := _make_target("FarAway", Vector3(50.0, 0, 0))  # weit außerhalb 2.5m Radius

	for i in range(4):
		await get_tree().physics_frame

	sensor.set_manual_target(far_away)
	assert_eq(sensor.get_closest(), near_tree,
		"Außer Reichweite befindliches Tap-Ziel darf nicht bevorzugt werden — Fallback auf Distanz-Auswahl.")

func test_clear_manual_target_restores_distance_selection() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]

	var near_tree := _make_target("NearTree", Vector3(0.5, 0, 0))
	var far_tree := _make_target("FarTree", Vector3(2.0, 0, 0))

	for i in range(4):
		await get_tree().physics_frame

	sensor.set_manual_target(far_tree)
	assert_eq(sensor.get_closest(), far_tree)

	sensor.clear_manual_target()
	assert_eq(sensor.get_closest(), near_tree,
		"Nach clear_manual_target() muss wieder die normale Distanz-Auswahl gelten.")

# ── has_manual_target() — für InteractionTargetPicker._deselect() (BUGFIX 2026-09-26,
#    "Umrandung soll auch automatisch bei Proximity/Autodetect funktionieren") ─────────

func test_has_manual_target_false_initially() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]
	assert_false(sensor.has_manual_target())

func test_has_manual_target_true_after_set() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]
	# außer Reichweite — has_manual_target() fragt bewusst NICHT nach Reichweite, nur danach
	# ob überhaupt eine Tap-Auswahl gesetzt ist.
	var target := _make_target("Tapped", Vector3(50.0, 0, 0))
	sensor.set_manual_target(target)
	assert_true(sensor.has_manual_target())

func test_has_manual_target_false_after_clear() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]
	var target := _make_target("Tapped", Vector3(0.5, 0, 0))
	sensor.set_manual_target(target)
	sensor.clear_manual_target()
	assert_false(sensor.has_manual_target())

# ── get_all_candidates() — für Player.get_all_nearby_context_actions() (BUGFIX 2026-09-26,
#    "Kontextmenü soll alles anzeigen was in der Nähe ist") ────────────────────────────

func test_get_all_candidates_returns_every_target_in_range() -> void:
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]

	var near_tree := _make_target("NearTree", Vector3(0.5, 0, 0))
	var far_tree := _make_target("FarTree", Vector3(2.0, 0, 0))
	var out_of_range := _make_target("OutOfRange", Vector3(50.0, 0, 0))

	for i in range(4):
		await get_tree().physics_frame

	var all_candidates := sensor.get_all_candidates()
	assert_true(all_candidates.has(near_tree), "Nahes Ziel muss enthalten sein.")
	assert_true(all_candidates.has(far_tree),
		"Weiter entferntes, aber noch in Reichweite befindliches Ziel muss ebenfalls enthalten sein — " +
		"get_closest() liefert nur EINS davon, get_all_candidates() BEIDE.")
	assert_false(all_candidates.has(out_of_range), "Außer Reichweite befindliches Ziel darf nicht enthalten sein.")

func test_deselect_falls_back_to_natural_closest_target() -> void:
	# Voller Ablauf über InteractionTargetPicker: Tap auf ein Ziel, DANEBEN steht (in
	# Reichweite) noch ein zweites, rein automatisch (Autodetect) erkanntes Ziel. "Tap ins
	# Leere" muss die Umrandung auf dieses automatische Ziel zurückfallen lassen statt sie
	# zu löschen — sonst zeigt die Umrandung nach dem Abwählen kurzzeitig NICHTS, obwohl der
	# Interaktions-Button ("!") längst wieder auf das automatische Ziel zeigt.
	var setup := _make_sensor()
	var sensor: InteractionSensor = setup["sensor"]
	var owner: StaticBody3D = setup["owner"]

	var tapped := _make_target("Tapped", Vector3(2.0, 0, 0))
	var ambient := _make_target("Ambient", Vector3(0.5, 0, 0))

	for i in range(4):
		await get_tree().physics_frame

	var bus := MockEventBus.new()
	sensor.inject_bus(bus)

	var picker := InteractionTargetPicker.new()
	add_child_autofree(picker)
	picker.setup(null, sensor, owner)
	picker.inject_bus(bus)

	picker._select(tapped)
	assert_eq(picker._outline.get_target(), tapped)
	assert_true(sensor.has_manual_target())

	picker._deselect()
	assert_false(sensor.has_manual_target(),
		"_deselect() muss die manuelle Auswahl im Sensor aufheben.")
	assert_eq(picker._outline.get_target(), ambient,
		"Ohne manuelle Auswahl muss die Umrandung auf das automatisch nächste Ziel zurückfallen, statt zu verschwinden.")
