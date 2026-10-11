class_name PlayerPickpocket
extends RefCounted

## PlayerPickpocket — Interaktions-Setup für Pickpocket-Versuche (ADR-039)
## an einen anderen Player-Node. Koexistiert mit "attack_player",
## "trade_request" und "thank_player" auf demselben Node (siehe Player.gd
## _ready()).
##
## DREI FESTE AKTIONEN STATT AUSWAHL-UI: anders als ADR-038s Scrolls (die
## über eine "Item auswählen"-UI im Inventar-Panel angewendet werden, siehe
## InventoryUIController._on_scroll_selected()) gibt es hier bewusst DREI
## separate InteractableComponents — eine pro Kristall-Stufe
## ("pickpocket_weak"/"pickpocket_normal"/"pickpocket_strong"). Grund: die
## Kristall-Auswahl UND das Ziel (ein anderer Spieler) sind hier zwei
## unabhängige Dinge, die es bei den Scrolls nicht gab (dort war das Ziel
## immer ein Item im EIGENEN Inventar, in derselben Liste wie das Scroll
## selbst). Alle drei Aktionen erscheinen zusammen mit attack/trade/thank im
## bestehenden Kontextmenü (ContextMenuController) — welche davon tatsächlich
## ausführbar ist (Kristall vorhanden? Cooldown abgelaufen? Diebes-Zone?),
## entscheidet ausschließlich PickpocketService serverseitig
## (Absicht-statt-Wert, ADR-004) — die Aktion bleibt im Menü sichtbar, auch
## wenn der Versuch dahinter fehlschlagen wird (kein serverseitiger
## Sichtbarkeits-Vorab-Check, analog wie attack_player unabhängig von
## ausgerüsteter Waffe sichtbar bleibt).
##
## Autoritäts-Routing: identisch zu attack_player/trade_request/thank_player.

const LOG_CAT := "PlayerPickpocket"

const _TIER_CONFIG := [
	{"action_id": "pickpocket_weak",   "label": "Taschendiebstahl (schwach)", "comp_name": "PickpocketWeakInteractable"},
	{"action_id": "pickpocket_normal", "label": "Taschendiebstahl",           "comp_name": "PickpocketNormalInteractable"},
	{"action_id": "pickpocket_strong", "label": "Taschendiebstahl (stark)",   "comp_name": "PickpocketStrongInteractable"},
]

static func setup_interactable(parent: Node3D, ctx: IEntityContext = null) -> void:
	if not parent.has_method("_on_interacted"):
		AppLogger.log_error("setup_interactable(): parent hat keine _on_interacted()-Methode.", LOG_CAT)
		return
	for tier_config in _TIER_CONFIG:
		var d := InteractableData.new()
		d.id           = tier_config["action_id"]
		d.label        = tier_config["label"]
		d.duration     = 0.5
		# Kein xp_type/xp_amount hier — die Diebstahl-XP wird von
		# PickpocketService selbst über SkillSystem.request_add_xp() vergeben
		# (bei Erfolg UND Fehlschlag, unterschiedliche Beträge — passt nicht
		# in das feste xp_type/xp_amount-Schema von InteractableData/
		# InteractionResolver, das nur EINEN festen Betrag kennt).
		d.inspect_text = "Ein anderer Spieler."
		var comp := InteractableComponent.new()
		comp.name = tier_config["comp_name"]
		comp.data = d
		parent.add_child(comp)
		# BUGFIX (2026-09-16, "Player2Player-Interaktion funktioniert nicht"):
		# siehe PlayerAttack.setup_interactable()-Kommentar — inject_context() fehlte.
		if is_instance_valid(ctx):
			comp.inject_context(ctx)
		comp.interacted.connect(parent._on_interacted)
