class_name InteractableAction
extends RefCounted

var id: String
var label: String
var duration: float = 0.0
var xp_type: String = "none"
var xp_amount: int = 0
var inspect_text: String = ""
var loot_table: LootTable = null
var yield_stat_id: String = ""
var speed_stat_id: String = ""
var on_complete: Callable

## Wer diese Aktion ausgeführt hat/ausführt — peer_id des Spielers (ADR-015).
## Default 1 (Solo/Host) für bestehende Konstruktions-Stellen, die dies noch
## nicht setzen. Gesetzt von Player.get_context_actions() auf _owner_peer_id (ADR-025)
## des anfragenden Spielers — NICHT vom IEntityContext des Interactables selbst,
## dessen owner_peer_id etwas anderes ist (wem das Objekt "gehört", z.B. 1 für
## Weltobjekte, unabhängig davon, welcher Spieler gerade damit interagiert).
var peer_id: int = 1

func _init(p_id: String, p_label: String) -> void:
	id = p_id
	label = p_label
