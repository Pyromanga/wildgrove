class_name PlayerTrade
extends RefCounted

## PlayerTrade — Interaktions-Setup für Handelsanfragen an einen anderen
## Player-Node. ADR-035, exaktes Gegenstück zu PlayerAttack.setup_interactable()
## (PvP: Spieler → Spieler-Angriff) — nutzt denselben InteractableComponent/
## InteractionSensor-Mechanismus wie dort: sobald diese Interaktion an einem
## Player-Node hängt und der Node in Gruppe "interactable" ist, taucht er für
## andere Spieler als Handelsziel auf, GENAU wie als Angriffsziel — beide
## Interactables koexistieren auf demselben Player-Node (siehe Player.gd
## _ready(), das jetzt sowohl PlayerAttack.setup_interactable() als auch
## PlayerTrade.setup_interactable() aufruft; InteractableComponent unterstützt
## mehrere Instanzen pro Node, siehe InteractionSensor.get_closest()/
## Player.get_context_actions() — jede sammelt ihre eigenen Aktionen).
##
## Autoritäts-Routing: identisch zu attack_player. Der lokale Klick des
## anfragenden Spielers führt bei Nicht-Autorität zu keiner Wirkung, wird aber
## automatisch von InteractableComponent._handle_completion() per RPC an die
## Autorität weitergereicht (WorldService.request_entity_interaction()) — dort
## läuft Player._on_interacted() erneut, diesmal mit echter Wirkung
## (TradeService.on_invite_confirmed()). Siehe Player._on_interacted() und
## TradeService.gd-Klassenkommentar für die volle Begründung.

const LOG_CAT := "PlayerTrade"

static func setup_interactable(parent: Node3D, ctx: IEntityContext = null) -> void:
	var d := InteractableData.new()
	d.id           = "trade_request"
	d.label        = "Handel anbieten"
	d.duration     = 0.5
	# Kein xp_type/xp_amount — wie attack_player kein Interaktions-XP für
	# eine Spieler-zu-Spieler-Aktion.
	d.inspect_text = "Ein anderer Spieler."
	var comp := InteractableComponent.new()
	comp.name = "TradeInteractable"
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
