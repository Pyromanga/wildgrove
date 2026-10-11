class_name EnemyAttack
extends RefCounted

## EnemyAttack — Interaktions-Setup für EnemyNPC.
##
## VERANTWORTUNG:
##   setup_interactable() → baut InteractableData + InteractableComponent

const LOG_CAT := "EnemyAttack"

## label/inspect_text: BUGFIX (Skelette zeigten "Ein Goblin..."-Text) —
## setup_interactable() hatte den Inspect-Text fest verdrahtet statt ihn vom
## konkreten Gegnertyp zu übernehmen. Jetzt optional parametrisiert; Default
## bleibt "Goblin" für Rückwärtskompatibilität mit Aufrufern ohne Angabe.
static func setup_interactable(parent: Node3D, enemy_label: String = "Goblin") -> void:
	var d := InteractableData.new()
	d.id           = "attack_enemy"
	d.label        = "Angreifen"
	d.duration     = 0.7
	d.xp_type      = "combat"
	d.xp_amount    = 5
	d.inspect_text = "Ein %s. Feindselig und gefährlich." % enemy_label
	var comp := InteractableComponent.new()
	comp.name = "AttackInteractable"
	comp.data = d
	parent.add_child(comp)
	# BUG-FIX: InteractableComponent._handle_completion() wurde von einem
	# direkten parent._on_interacted()-Aufruf auf das 'interacted'-Signal
	# umgestellt (siehe AnimalBase/HarvestableEntity) — hier fehlte der
	# entsprechende .connect(). Dadurch lief die Angriffs-Interaktion optisch
	# durch (XP, Popup), aber EnemyNPC._on_interacted() — und damit der
	# eigentliche Schaden — wurde nie ausgelöst.
	if parent.has_method("_on_interacted"):
		comp.interacted.connect(parent._on_interacted)
