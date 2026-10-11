class_name PlayerThank
extends RefCounted

## PlayerThank — Interaktions-Setup für die "Danken"-Interaktion (ADR-036,
## Aura/Gesinnung) an einen anderen Player-Node. Exaktes Gegenstück zu
## PlayerTrade.setup_interactable() — nutzt denselben InteractableComponent/
## InteractionSensor-Mechanismus, koexistiert mit "attack_player" und
## "trade_request" auf demselben Node (siehe Player.gd _ready()).
##
## Autoritäts-Routing: identisch zu attack_player/trade_request. Der lokale
## Klick des dankenden Spielers führt bei Nicht-Autorität zu keiner Wirkung,
## wird aber automatisch von InteractableComponent._handle_completion() per
## RPC an die Autorität weitergereicht — dort läuft Player._on_interacted()
## erneut, diesmal mit echter Wirkung (AuraService.on_thank_confirmed()).

const LOG_CAT := "PlayerThank"

static func setup_interactable(parent: Node3D, ctx: IEntityContext = null) -> void:
	var d := InteractableData.new()
	d.id           = "thank_player"
	d.label        = "Danken"
	d.duration     = 0.5
	# Kein xp_type/xp_amount — wie attack_player/trade_request kein
	# Interaktions-XP für eine Spieler-zu-Spieler-Aktion.
	d.inspect_text = "Ein anderer Spieler."
	var comp := InteractableComponent.new()
	comp.name = "ThankInteractable"
	comp.data = d
	parent.add_child(comp)
	# BUGFIX (2026-09-16, "Player2Player-Interaktion funktioniert nicht"):
	# siehe PlayerAttack.setup_interactable()-Kommentar — inject_context() fehlte.
	if is_instance_valid(ctx):
		comp.inject_context(ctx)
	if parent.has_method("_on_interacted"):
		comp.interacted.connect(parent._on_interacted)
	else:
		AppLogger.log_error("setup_interactable(): parent hat keine _on_interacted()-Methode.", LOG_CAT)
