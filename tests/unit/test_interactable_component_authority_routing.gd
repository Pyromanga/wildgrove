# res://tests/unit/test_interactable_component_authority_routing.gd
extends GutTest

## Unit-Tests für InteractableComponent._handle_completion() — ADR-020.
##
## Vor diesem Fix erreichte der abgeschlossene Interaktions-Hook (_on_interacted)
## auf einem Nicht-Host-Client die Autorität NIE (InteractionExecutor läuft pro
## Peer lokal) — R-1/R-2/R-3/R-6 aus TODO-offene-probleme.md sind exakt diese
## strukturelle Lücke. Diese Tests sichern die Fix-Invarianten am Transport-Punkt:
##
##   - Auf der Autorität: nur der lokale Emit, KEIN zusätzlicher Netzwerk-Call
##   - Auf Nicht-Autorität: lokaler Emit (wirkungslos beim Hook selbst dank dessen
##     eigenem Guard) PLUS Weiterleitung an WorldService.request_entity_interaction()
##   - Ohne entity_uuid / ohne WorldService: kein Crash, sauberer Log-Fallback

## Minimale Parent-Entity mit _on_interacted()-Hook, die selbst die Aufrufe
## zählt — steht hier für "irgendeine Entity" (HarvestableEntity/AnimalBase/
## EnemyNPC teilen sich alle denselben Transport über dieses Signal).
class MockParentEntity extends Node3D:
	var interacted_calls: Array = []
	func _on_interacted(action_id: String, peer_id: int) -> void:
		interacted_calls.append([action_id, peer_id])

class MockWorldService extends WorldService:
	var requested_calls: Array = []  # [[uuid, action_id, peer_id], ...]
	func request_entity_interaction(entity_uuid: String, action_id: String, peer_id: int) -> void:
		requested_calls.append([entity_uuid, action_id, peer_id])

func _make_component() -> Dictionary:
	var parent := MockParentEntity.new()
	add_child_autofree(parent)
	var comp := InteractableComponent.new()
	var data := InteractableData.new()
	data.id    = "chop"
	data.label = "Test"
	comp.data  = data
	parent.add_child(comp)
	return {"parent": parent, "comp": comp}

func test_authority_only_emits_locally_no_network_call() -> void:
	var built  := _make_component()
	var parent: MockParentEntity     = built["parent"]
	var comp:   InteractableComponent = built["comp"]
	parent.set_multiplayer_authority(1)  # kein Peer → unique_id 1 → true

	comp._handle_completion(1)

	assert_eq(parent.interacted_calls.size(), 1, "Lokaler Hook muss über den Emit ausgelöst werden.")
	assert_eq(parent.interacted_calls[0], ["chop", 1])

func test_non_authority_forwards_to_world_service() -> void:
	var built  := _make_component()
	var parent: MockParentEntity     = built["parent"]
	var comp:   InteractableComponent = built["comp"]
	parent.set_multiplayer_authority(2)
	assert_false(parent.is_multiplayer_authority(), "Testvoraussetzung: Parent darf nicht Autorität sein.")
	parent.set_meta("entity_uuid", "uuid-123")

	var world := MockWorldService.new()
	var ctx   := EntityContext.for_test()
	ctx._world = world
	comp.inject_context(ctx)

	comp._handle_completion(5)

	assert_eq(parent.interacted_calls.size(), 1,
		"Lokaler Emit muss weiterhin passieren (dortiger Guard entscheidet über Wirkung, nicht der Transport).")
	assert_eq(world.requested_calls.size(), 1,
		"Nicht-Autorität muss die Interaktion zusätzlich an die Autorität melden.")
	assert_eq(world.requested_calls[0], ["uuid-123", "chop", 5],
		"uuid/action_id/peer_id müssen unverändert weitergereicht werden.")

func test_non_authority_without_uuid_does_not_crash_and_skips_forward() -> void:
	var built  := _make_component()
	var parent: MockParentEntity     = built["parent"]
	var comp:   InteractableComponent = built["comp"]
	parent.set_multiplayer_authority(2)
	# Keine entity_uuid gesetzt.

	var world := MockWorldService.new()
	var ctx   := EntityContext.for_test()
	ctx._world = world
	comp.inject_context(ctx)

	comp._handle_completion(5)

	assert_eq(world.requested_calls.size(), 0, "Ohne UUID darf keine Weiterleitung passieren.")

func test_non_authority_without_world_service_does_not_crash() -> void:
	var built  := _make_component()
	var parent: MockParentEntity     = built["parent"]
	var comp:   InteractableComponent = built["comp"]
	parent.set_multiplayer_authority(2)
	parent.set_meta("entity_uuid", "uuid-456")
	# Kein inject_context() → _ctx bleibt null.

	comp._handle_completion(5)

	assert_true(true, "_handle_completion() ohne _ctx/WorldService darf nicht crashen.")
