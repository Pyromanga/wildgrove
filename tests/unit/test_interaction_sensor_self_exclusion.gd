# res://tests/unit/test_interaction_sensor_self_exclusion.gd
extends GutTest

## Regressionstest für den Solo-Spiel-Bug (2026-09-13): der Spieler konnte
## nichts abbauen, keine Quests annehmen und sich nicht gegen NPCs wehren,
## weil InteractionSensor.get_closest() den eigenen Spieler-Node (an dem er
## als Kind hängt) als nächstes Ziel zurückgab — Distanz ~0m schlägt jedes
## echte Interactable (Baum, Erz, Quest-NPC, Gegner).
##
## Ursache: Player.on_spawn() trägt JEDEN Player-Node (auch den lokalen,
## eigenen im Solo-Spiel) über PlayerAttack/PlayerTrade/PlayerThank/
## PlayerPickpocket.setup_interactable() in die Gruppe "interactable" ein
## (gedacht für PvP mit ANDEREN Spielern). Der Sensor hängt als Kind direkt
## am eigenen Body und überlappt sich daher immer mit sich selbst.
##
## Fix: get_closest() schließt get_parent() (den eigenen Besitzer-Node)
## explizit aus — sowohl im Body- als auch im Area-Zweig.

func _make_sensor_on_owner(owner_in_interactable_group: bool) -> Dictionary:
	var owner_body := StaticBody3D.new()
	owner_body.name = "OwnerPlayer"
	if owner_in_interactable_group:
		owner_body.add_to_group("interactable")
	add_child_autofree(owner_body)

	var owner_shape := CollisionShape3D.new()
	var owner_box := BoxShape3D.new()
	owner_box.size = Vector3(0.9, 1.8, 0.9)
	owner_shape.shape = owner_box
	owner_body.add_child(owner_shape)

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

func _make_target(pos: Vector3) -> StaticBody3D:
	var target := StaticBody3D.new()
	target.name = "Target"
	target.add_to_group("interactable")
	target.global_position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 1.8, 0.9)
	shape.shape = box
	target.add_child(shape)
	add_child_autofree(target)
	return target

func test_get_closest_excludes_own_owner_even_though_owner_is_interactable() -> void:
	var setup := _make_sensor_on_owner(true)
	var sensor: InteractionSensor = setup["sensor"]
	var owner_body: Node3D = setup["owner"]

	var target := _make_target(Vector3(1.0, 0, 0))  # innerhalb der 2.5m Reichweite

	# Mehrere Physik-Frames abwarten, damit Area3D-Overlaps tatsächlich erfasst werden.
	for i in range(4):
		await get_tree().physics_frame

	var closest := sensor.get_closest()

	assert_ne(closest, owner_body,
		"BUG-REGRESSION: Sensor darf niemals den eigenen Besitzer-Node als Ziel liefern.")
	assert_eq(closest, target,
		"Sensor muss das echte, andere interactable Ziel finden statt sich selbst.")

func test_get_closest_returns_null_when_only_owner_overlaps() -> void:
	## Kein anderes Ziel in Reichweite → get_closest() muss null liefern,
	## NICHT den eigenen Besitzer (auch wenn der zufällig in "interactable" ist).
	var setup := _make_sensor_on_owner(true)
	var sensor: InteractionSensor = setup["sensor"]

	for i in range(4):
		await get_tree().physics_frame

	var closest := sensor.get_closest()
	assert_null(closest,
		"Ohne echtes externes Ziel darf get_closest() nicht auf den eigenen Besitzer zurückfallen.")
