# res://tests/unit/test_enemy_attack.gd
extends GutTest

## Unit-Tests für EnemyAttack.setup_interactable() (statische Factory-Funktion).
##
## Präzedenz für "InteractableComponent real via add_child() instanziieren"
## bereits etabliert in test_harvestable_entity.gd/test_quest_npc.gd — gleiches
## Muster hier: echter Parent-Node in der SceneTree, echte InteractableComponent
## (kein Stub), da _ready() hier unkritisch ist (kein IEntityContext nötig für
## das, was getestet wird).
##
## Abgedeckt:
##   - Component wird als Kind "AttackInteractable" angehängt, ist eine echte
##     InteractableComponent
##   - InteractableData-Felder exakt wie im Code hart codiert
##   - Der im Klassenkommentar dokumentierte Bug-Fix: interacted-Signal wird
##     verbunden WENN der Parent _on_interacted() hat, NICHT verbunden wenn nicht
##   - setup_interactable() kann mehrfach mit unterschiedlichen Parents
##     aufgerufen werden, ohne sich gegenseitig zu beeinflussen


class MockParentWithHook extends Node3D:
	var on_interacted_calls: Array = []  ## [[action_id, peer_id], ...]
	func _on_interacted(action_id: String, peer_id: int) -> void:
		on_interacted_calls.append([action_id, peer_id])


func test_adds_component_named_attack_interactable() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	EnemyAttack.setup_interactable(parent)
	var comp := parent.get_node_or_null("AttackInteractable")
	assert_not_null(comp)
	assert_true(comp is InteractableComponent)

func test_interactable_data_fields_are_correct() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	EnemyAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	assert_eq(comp.data.id, "attack_enemy")
	assert_eq(comp.data.label, "Angreifen")
	assert_almost_eq(comp.data.duration, 0.7, 0.0001)
	assert_eq(comp.data.xp_type, "combat")
	assert_eq(comp.data.xp_amount, 5)
	assert_eq(comp.data.inspect_text, "Ein Goblin. Feindselig und gefährlich.")

func test_connects_interacted_signal_when_parent_has_hook() -> void:
	var parent := MockParentWithHook.new()
	add_child_autofree(parent)
	EnemyAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	comp.interacted.emit("attack_enemy", 7)
	assert_eq(parent.on_interacted_calls, [["attack_enemy", 7]])

func test_does_not_connect_when_parent_lacks_hook() -> void:
	# Regressionstest für genau den im Klassenkommentar beschriebenen Bug:
	# fehlendes .connect() lief optisch durch, ohne dass der Schaden je
	# ausgelöst wurde. Kein Crash beim Fehlen ist nicht genug — es darf
	# schlicht KEINE Verbindung existieren.
	var parent := Node3D.new()  # hat keine _on_interacted()-Methode
	add_child_autofree(parent)
	EnemyAttack.setup_interactable(parent)
	var comp: InteractableComponent = parent.get_node("AttackInteractable")
	assert_eq(comp.interacted.get_connections().size(), 0)

func test_setup_is_independent_across_multiple_parents() -> void:
	var parent_a := MockParentWithHook.new()
	add_child_autofree(parent_a)
	var parent_b := Node3D.new()
	add_child_autofree(parent_b)

	EnemyAttack.setup_interactable(parent_a)
	EnemyAttack.setup_interactable(parent_b)

	var comp_b: InteractableComponent = parent_b.get_node("AttackInteractable")
	comp_b.interacted.emit("attack_enemy", 1)
	assert_eq(parent_a.on_interacted_calls, [], "parent_b's Interaktion darf parent_a nicht beeinflussen.")
