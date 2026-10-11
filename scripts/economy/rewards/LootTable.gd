class_name LootTable
extends Resource

## LootTable — Datengetriebene Drop-Tabelle für Gathering-Objekte.
##
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

## Gold-Drop (separat von entries — Gold ist kein Item, siehe ADR-033).
## gold_min == gold_max == 0 → kein Gold-Drop (Default, z.B. Gathering-Objekte).
@export var gold_min: int = 0
@export var gold_max: int = 0

## Würfelt den Gold-Drop dieser Tabelle. Gibt 0 zurück wenn kein Gold-Drop
## konfiguriert ist (gold_max <= 0) — Aufrufer müssen daher IMMER auf 0 prüfen
## statt blind CurrencyService.request_add_gold() aufzurufen.
func roll_gold() -> int:
	if gold_max <= 0 or gold_max < gold_min:
		return 0
	return randi_range(gold_min, gold_max)

## Rollt die LootTable und gibt ein Dictionary { item_id: quantity } zurück.
## yield_multiplier: skaliert die gewürfelte Menge (z.B. 1.10 für +10% durch
## Quest-Reward-Stat-Modifier). Default 1.0 = keine Skalierung, bestehende
## Aufrufer bleiben unverändert.
func roll(yield_multiplier: float = 1.0) -> Dictionary:
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
			var base_qty := randi_range(entry.quantity_min, entry.quantity_max)
			var qty := int(round(base_qty * yield_multiplier))
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
