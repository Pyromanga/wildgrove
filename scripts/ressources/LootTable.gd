class_name LootTable
extends Resource

## LootTable — Datengetriebene Drop-Tabelle für Gathering-Objekte.
##
## NEU (Session 4): Ersetzt das flache `drops: Dictionary` in InteractableData.
##   VORHER: drops = { "log_oak": 2 } — feste Menge, keine Wahrscheinlichkeit
##   NACHHER: Array[LootEntry] mit weight, min/max quantity, rarity
##
## Verwendung: InteractableData.loot_table verweist auf eine LootTable.tres.
##   OakTree.tres → loot_table = res://data/loot/loot_oak_tree.tres
##
## Rollen eines Drops:
##   1. Roll: Für jeden Eintrag würfeln ob er droppt (Chance = weight / total_weight)
##   2. Quantity: zufällig zwischen quantity_min und quantity_max
##   3. max_rolls begrenzt Gesamtanzahl der gedropten Einträge

@export var max_rolls:    int = 3  ## Maximale Anzahl verschiedener Items pro Drop
@export var entries: Array[LootEntry] = []


## Rollt die LootTable und gibt ein Dictionary { item_id: quantity } zurück.
func roll() -> Dictionary:
	if entries.is_empty():
		return {}

	var result: Dictionary = {}
	var total_weight: float = 0.0
	for e in entries:
		total_weight += max(e.weight, 0.0)

	if total_weight <= 0.0:
		return {}

	var rolls_done := 0
	for entry in entries:
		if rolls_done >= max_rolls:
			break
		var roll_val := randf() * total_weight
		if roll_val <= entry.weight:
			var qty := randi_range(entry.quantity_min, entry.quantity_max)
			if qty > 0:
				result[entry.item_id] = result.get(entry.item_id, 0) + qty
				rolls_done += 1

	return result


## Gibt alle garantierten Drops zurück (weight >= total_weight).
func get_guaranteed_drops() -> Array[String]:
	var total_weight: float = 0.0
	for e in entries:
		total_weight += e.weight
	var guaranteed: Array[String] = []
	for e in entries:
		if e.weight >= total_weight:
			guaranteed.append(e.item_id)
	return guaranteed
