## tests/unit/test_interactable_multiplayer.gd
## Tests für InteractableComponent + ProximityDetector Multi-Player-Korrektheit (Sprint G-02).
##
## Kernproblem vor dem Fix:
##   _is_player_target() fragte get_first_node_in_group("player") —
##   bei zwei Spielern reagierte die Fortschrittsbar immer auf Spieler 1,
##   auch wenn Spieler 2 interagierte.
##
## Getestete Invarianten:
##   - ProximityDetector.player_entered übergibt den richtigen Node
##   - _is_player_target() gibt true wenn IRGENDEINER der Spieler diese
##     Interactable als Ziel hat
##   - _is_player_target() gibt false wenn kein Spieler diese Interactable anvisiert

extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# Minimal-Mocks
# ─────────────────────────────────────────────────────────────────────────────

## Minimaler Player-Mock: implementiert get_closest_interactable() mit konfigurierbarem Ziel.
class MockPlayer extends Node3D:
	var _target: Node3D = null
	func _init() -> void:
		add_to_group("player")
	func get_closest_interactable() -> Node3D:
		return _target
	func set_target(t: Node3D) -> void:
		_target = t

# ─────────────────────────────────────────────────────────────────────────────
# ProximityDetector — Signal übergibt korrekten Node
# ─────────────────────────────────────────────────────────────────────────────

func test_proximity_detector_player_entered_passes_node() -> void:
	## G-02: player_entered muss den eingetretenen Player-Node übergeben.
	var detector := ProximityDetector.new(3.0)
	add_child_autofree(detector)
	await get_tree().process_frame

	var received_player: Array = [null]
	detector.player_entered.connect(func(p: Node3D) -> void: received_player[0] = p)

	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	add_child_autofree(fake_player)

	# Signal direkt via Innard-Methode auslösen (kein Physics nötig)
	detector._on_body_entered(fake_player)

	assert_eq(received_player[0], fake_player,
		"player_entered muss den eingetretenen Player-Node übergeben.")

func test_proximity_detector_non_player_does_not_emit() -> void:
	var detector := ProximityDetector.new(3.0)
	add_child_autofree(detector)
	await get_tree().process_frame

	var fired := false
	detector.player_entered.connect(func(_p: Node3D) -> void: fired = true)

	var rock := Node3D.new()  # Kein "player"-Gruppen-Mitglied
	detector._on_body_entered(rock)
	rock.queue_free()

	assert_false(fired, "player_entered darf nicht für Nicht-Spieler feuern.")

func test_proximity_detector_player_exited_passes_node() -> void:
	var detector := ProximityDetector.new(3.0)
	add_child_autofree(detector)
	await get_tree().process_frame

	var received: Array = [null]
	detector.player_exited.connect(func(p: Node3D) -> void: received[0] = p)

	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	add_child_autofree(fake_player)
	detector._on_body_exited(fake_player)

	assert_eq(received[0], fake_player,
		"player_exited muss den ausgetretenen Player-Node übergeben.")

# ─────────────────────────────────────────────────────────────────────────────
# _is_player_target() — Multi-Player-Korrektheit
# ─────────────────────────────────────────────────────────────────────────────

## Erzeugt eine minimale InteractableComponent mit gemockter InteractableData.
func _make_component(parent: Node3D) -> InteractableComponent:
	var ic_data       := InteractableData.new()
	ic_data.id        = "test_obj"
	ic_data.label     = "Testobjekt"
	ic_data.duration  = 1.0
	var comp          := InteractableComponent.new()
	comp.data         = ic_data
	parent.add_child(comp)
	return comp

func test_is_player_target_true_when_player1_targets_this() -> void:
	## _is_player_target() muss true sein wenn Spieler 1 diese Interactable anvisiert.
	var parent := Node3D.new()
	add_child_autofree(parent)

	var p1 := MockPlayer.new()
	add_child_autofree(p1)

	var comp := _make_component(parent)
	p1.set_target(parent)

	assert_true(comp._is_player_target(),
		"_is_player_target() muss true sein wenn p1 dieses Objekt anvisiert.")

func test_is_player_target_true_when_player2_targets_this() -> void:
	## G-02 Kerntest: Auch Spieler 2 muss _is_player_target() auf true setzen.
	## Vor dem Fix: get_first_node_in_group() gab immer p1 zurück →
	## p2's Interaktion wurde nie der richtigen Interactable zugeordnet.
	var parent := Node3D.new()
	add_child_autofree(parent)

	var p1 := MockPlayer.new()
	var p2 := MockPlayer.new()
	add_child_autofree(p1)
	add_child_autofree(p2)

	var comp := _make_component(parent)

	# p1 schaut woanders hin, p2 visiert dieses Objekt an
	var other_obj := Node3D.new()
	add_child_autofree(other_obj)
	p1.set_target(other_obj)
	p2.set_target(parent)

	assert_true(comp._is_player_target(),
		"G-02: _is_player_target() muss true sein wenn p2 dieses Objekt anvisiert, auch wenn p1 es nicht tut.")

func test_is_player_target_false_when_no_player_targets_this() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)

	var p1 := MockPlayer.new()
	var p2 := MockPlayer.new()
	add_child_autofree(p1)
	add_child_autofree(p2)

	var other_obj := Node3D.new()
	add_child_autofree(other_obj)

	var comp := _make_component(parent)

	# Beide Spieler schauen auf ein anderes Objekt
	p1.set_target(other_obj)
	p2.set_target(other_obj)

	assert_false(comp._is_player_target(),
		"_is_player_target() muss false sein wenn kein Spieler dieses Objekt anvisiert.")

func test_is_player_target_true_with_no_players_in_scene() -> void:
	## Sicherer Default: Wenn kein Spieler in der Szene, true zurückgeben.
	## Verhindert dass die Bar unsichtbar bleibt in Randfällen (Respawn etc.).
	var parent := Node3D.new()
	add_child_autofree(parent)
	var comp := _make_component(parent)
	# Keine MockPlayer-Nodes hinzugefügt

	assert_true(comp._is_player_target(),
		"Ohne Spieler in der Szene muss _is_player_target() true als sicheren Default liefern.")
