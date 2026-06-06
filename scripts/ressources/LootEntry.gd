class_name LootEntry
extends Resource

## LootEntry — Einzelner Eintrag in einer LootTable.
##
## weight:       Relatives Gewicht für den Drop (höher = wahrscheinlicher).
##               Beispiel: common=100, uncommon=30, rare=5
## quantity_min: Minimale Drop-Menge (inklusive).
## quantity_max: Maximale Drop-Menge (inklusive). Gleich min = feste Menge.
## item_id:      Muss einer geladenen ItemDefinition.id entsprechen.

@export var item_id:      String = ""
@export var weight:       float  = 100.0
@export var quantity_min: int    = 1
@export var quantity_max: int    = 1


func get_display() -> String:
	return "%s (w=%.0f, qty=%d-%d)" % [item_id, weight, quantity_min, quantity_max]
