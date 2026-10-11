# res://tests/unit/test_player_attack.gd
extends GutTest

## Unit-Tests für PlayerAttack.setup_interactable() — PvP-Gegenstück zu
## EnemyAttack.setup_interactable() (siehe test_enemy_attack.gd, identisches
## Test-Setup-Muster).
##
## Abgedeckt:
##   - Component wird als "AttackInteractable" angehängt
##   - InteractableData-Felder wie im Code hart codiert — INKLUSIVE der
##     Tatsache, dass xp_type/xp_amount NICHT gesetzt werden und deshalb bei
##     InteractableData's eigenen Resource-Defaults bleiben ("none"/10), nicht
##     bei 0. Der Klassenkommentar sagt "bewusst kein XP", das gilt aber nur
##     weil Player._on_interacted() diese Felder nie ausliest — data.xp_amount
##     ist tatsächlich 10, nur wird's nirgends konsumiert. Dieser Test fixiert
##     das reale Datenfeld, ohne über den (hier nicht geprüften) Downstream-
##     Code zu urteilen.
##   - interacted-Signal: verbunden wenn Parent _on_interacted() hat, sonst
##     nicht (identisches Muster zu EnemyAttack, hier zusätzlich mit
##     explizitem log_error()-Zweig im Code — kein Crash beim Fehlen)


class MockParentWithHook extends Node3D:
	var on_interacted_calls: Array = []
	func _on_interacted(action_id: String, peer_id: int) -> void:
		on_interacted_calls.append([action_id, peer_id])


func test_adds_component_named_attack_interactable() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	PlayerAttack.setup_interactable(parent)
	var comp := parent.get_node_or_null("AttackInteractable")
	assert_not_null(comp)
	assert_true(comp is InteractableComponent)

func test_interactable_data_fields_are_correct() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	PlayerAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	assert_eq(comp.data.id, "attack_player")
	assert_eq(comp.data.label, "Angreifen")
	assert_almost_eq(comp.data.duration, 0.7, 0.0001)
	assert_eq(comp.data.inspect_text, "Ein anderer Spieler.")

func test_interactable_data_xp_fields_stay_at_resource_defaults() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	PlayerAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	assert_eq(comp.data.xp_type, "none", "Wird von PlayerAttack nicht gesetzt -> InteractableData-Default.")
	assert_eq(comp.data.xp_amount, 10, "InteractableData-Default ist 10, nicht 0 — nur ungenutzt, nicht neutralisiert.")

func test_connects_interacted_signal_when_parent_has_hook() -> void:
	var parent := MockParentWithHook.new()
	add_child_autofree(parent)
	PlayerAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	comp.interacted.emit("attack_player", 3)
	assert_eq(parent.on_interacted_calls, [["attack_player", 3]])

func test_does_not_connect_when_parent_lacks_hook() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	PlayerAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	assert_eq(comp.interacted.get_connections().size(), 0)

func test_setup_is_independent_across_multiple_parents() -> void:
	var parent_a := MockParentWithHook.new()
	add_child_autofree(parent_a)
	var parent_b := Node3D.new()
	add_child_autofree(parent_b)

	PlayerAttack.setup_interactable(parent_a)
	PlayerAttack.setup_interactable(parent_b)

	var comp_b: InteractableComponent = parent_b.get_node("AttackInteractable")
	comp_b.interacted.emit("attack_player", 1)
	assert_eq(parent_a.on_interacted_calls, [])
