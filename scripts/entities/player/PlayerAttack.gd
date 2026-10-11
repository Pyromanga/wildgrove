class_name PlayerAttack
extends RefCounted

## PlayerAttack — Interaktions-Setup für PvP-Angriffe auf einen Player-Node.
##
## Exaktes Gegenstück zu EnemyAttack.setup_interactable() (PvE, Spieler →
## Gegner) — jetzt spiegelbildlich Spieler → Spieler. Nutzt denselben
## InteractableComponent/InteractionSensor-Mechanismus: sobald diese
## Interaktion an einem Player-Node hängt UND der Node in Gruppe
## "interactable" ist, taucht er für andere Spieler als normales Angriffsziel
## auf (siehe InteractionSensor.get_closest() — kennt keinen Unterschied
## zwischen Gegner und Spieler, nur die Gruppen-Zugehörigkeit zählt).
##
## Das eigentliche Gate (darf dieser Angriff überhaupt Schaden anrichten?)
## liegt NICHT hier, sondern in Player._on_interacted() →
## CombatSystem.resolve_pvp_hit() → PvPService.is_pvp_active()/
## is_vulnerable_in_safe_zone() (ADR-032). Diese Klasse baut nur die
## Interaktions-Andockstelle, exakt wie EnemyAttack es für PvE tut.

const LOG_CAT := "PlayerAttack"

static func setup_interactable(parent: Node3D, ctx: IEntityContext = null) -> void:
	var d := InteractableData.new()
	d.id           = "attack_player"
	d.label        = "Angreifen"
	d.duration     = 0.7
	# Bewusst KEIN xp_type/xp_amount — anders als attack_enemy gibt es für
	# PvP-Treffer keine Interaktions-XP (kein InteractionResolver-Aufruf
	# unten in Player._on_interacted(), siehe dortiger Kommentar).
	d.inspect_text = "Ein anderer Spieler."
	var comp := InteractableComponent.new()
	comp.name = "AttackInteractable"
	comp.data = d
	parent.add_child(comp)
	# BUGFIX (2026-09-16, "Player2Player-Interaktion funktioniert nicht"):
	# inject_context() fehlte hier komplett — anders als bei
	# HarvestableEntity/EnemyNPC/AnimalBase (die es in ihrem eigenen
	# on_spawn() aufrufen) gab es für die vier Spieler-zu-Spieler-
	# Interactables (Attack/Trade/Thank/Pickpocket) nie einen Kontext,
	# InteractableComponent._handle_completion() brach deshalb IMMER mit
	# "kein WorldService im Context" ab — Angriffe/Handel/Danken/Taschen-
	# diebstahl erreichten die Autorität nie.
	if is_instance_valid(ctx):
		comp.inject_context(ctx)
	if parent.has_method("_on_interacted"):
		comp.interacted.connect(parent._on_interacted)
	else:
		AppLogger.log_error("setup_interactable(): parent hat keine _on_interacted()-Methode.", LOG_CAT)
