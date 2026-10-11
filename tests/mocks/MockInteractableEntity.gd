# res://tests/mocks/MockInteractableEntity.gd
extends Node3D
class_name MockInteractableEntity

## Minimaler Node3D-Test-Double mit _on_interacted()-Hook für ADR-020-Tests
## (WorldService.resolve_and_dispatch_interaction() / NetworkBridge._rpc_request_
## entity_interaction()). Zeichnet jeden Aufruf auf statt echter Gameplay-Wirkung —
## Tests prüfen WER/WANN aufgerufen wurde, nicht was ein konkreter Entity-Typ
## damit tut (das prüfen die jeweiligen Entity-eigenen Tests, z.B. AnimalBase).
##
## Bewusst ohne on_spawn()/on_despawn(): EntityOrchestrator behandelt beide als
## optional (has_method()-Guard) — dieselbe Begründung wie MockHarvestable.gd.

var interacted_calls: Array = []  # [[action_id, peer_id], ...]

func _on_interacted(action_id: String, peer_id: int) -> void:
	interacted_calls.append([action_id, peer_id])

## Baut eine echte InteractableComponent als Kind auf — setzt dabei automatisch
## das "interactable_component"-Meta auf self (InteractableComponent._ready()),
## damit WorldService._max_interaction_range_for() etwas Echtes zum Auslesen hat.
func attach_interactable_component(detection_radius: float, action_id: String = "test_action") -> InteractableComponent:
	var data := InteractableData.new()
	data.id    = action_id
	data.label = "Test-Interaktion"
	var comp := InteractableComponent.new()
	comp.data = data
	comp.detection_radius = detection_radius
	add_child(comp)
	return comp
