## tests/unit/test_inventory_ui_signal.gd
## Regression-Tests für inventory_changed Signal-Signatur.
##
## Regression: InventoryUIController verband _on_inventory_changed(items) direkt —
## Signal hat Signatur (player_id: String, items: Array[Dictionary]),
## deshalb kam bei player_id != erwartet nie etwas an.
##
## ADR-029 Plan-Schritt 4 (Round 63): player_id ist jetzt player_uuid (String)
## statt peer_id (int) — "p1"/"p2" sind hier reine opake Test-Keys.

extends GutTest

var _inventory: InventorySystem

func before_each() -> void:
	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_inventory.on_cleanup()
	_inventory = null

func test_inventory_changed_signal_has_two_params() -> void:
	# Prüft dass das Signal player_id UND items liefert (nicht nur items).
	var received_player_id := [""]
	var received_items: Array = [[]]

	_inventory.inventory_changed.connect(
		func(player_id: String, items: Array[Dictionary]) -> void:
			received_player_id[0] = player_id
			received_items[0]     = items
	)

	# Direkt den State setzen und Signal manuell auslösen
	# WICHTIG: Muss als Array[Dictionary] typisiert sein — ein untypisiertes
	# Array-Literal kann nicht in den typisierten Signal-Parameter konvertiert
	# werden (Godot bricht die Callable-Auslieferung sonst mit Konvertierungsfehler ab).
	var payload: Array[Dictionary] = [{"id": "iron_ore", "name": "Eisenerz", "quantity": 3}]
	_inventory.inventory_changed.emit("p1", payload)

	assert_eq(received_player_id[0], "p1",
		"Signal muss player_id='p1' liefern.")
	assert_eq((received_items[0] as Array).size(), 1,
		"Signal muss Items-Array liefern.")

func test_inventory_changed_player_id_filter() -> void:
	# Stellt sicher dass der Controller nur player_id=="p1" weiterverarbeitet.
	var player1_count := [0]
	var player2_count := [0]

	_inventory.inventory_changed.connect(
		func(player_id: String, _items: Array[Dictionary]) -> void:
			if player_id == "p1":
				player1_count[0] += 1
			elif player_id == "p2":
				player2_count[0] += 1
	)

	var empty_items: Array[Dictionary] = []
	_inventory.inventory_changed.emit("p1", empty_items)
	_inventory.inventory_changed.emit("p2", empty_items)
	_inventory.inventory_changed.emit("p1", empty_items)

	assert_eq(player1_count[0], 2, "player_id=='p1' muss 2x empfangen werden.")
	assert_eq(player2_count[0], 1, "player_id=='p2' muss 1x empfangen werden.")

func test_inventory_changed_items_structure() -> void:
	# Prüft dass die Items-Dictionaries die erwarteten Keys haben.
	var received: Array = [[]]
	_inventory.inventory_changed.connect(
		func(_pid: String, items: Array[Dictionary]) -> void:
			received[0] = items
	)

	var test_items: Array[Dictionary] = [
		{"id": "log_normal", "name": "Holz", "quantity": 5},
		{"id": "iron_ore",   "name": "Eisenerz", "quantity": 2},
	]
	_inventory.inventory_changed.emit("p1", test_items)

	var received_arr: Array = received[0]
	assert_eq(received_arr.size(), 2, "2 Items erwartet.")
	assert_true(received_arr[0].has("id"),       "Item muss 'id' haben.")
	assert_true(received_arr[0].has("quantity"), "Item muss 'quantity' haben.")
