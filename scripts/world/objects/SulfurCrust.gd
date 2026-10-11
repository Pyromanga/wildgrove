extends HarvestableEntity
class_name SulfurCrust

## SulfurCrust — Gelbe Schwefelkruste am Fels (Skill "alchemy" / Alchemie).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Schwefel war eine Kernzutat der Alchemisten. Ihr Traum vom
## Goldmachen scheiterte, doch ihre Versuche verfeinerten Labormethoden (z. B.
## Destillation) — Vorläufer der Chemie. Spawnt im Gebirge und im Sumpf (BiomeRegistry).
## Respawn: siehe WorldService.configure().
##
## Der Bildungstext lebt in data/skills/alchemy.tres.

func _get_entity_type_id() -> String:
	return "sulfur_crust"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_sulfur_crust"
	d.label        = "Schwefel abkratzen"
	d.duration     = 2.5
	d.xp_type      = "alchemy"
	d.xp_amount    = 20
	d.loot_table   = preload("res://data/loot_tables/loot_sulfur_crust.tres")
	d.inspect_text = "Eine gelbe Kruste am Fels, von Alchemisten heiß begehrt. Wusstest du? Ihre Versuche verfeinerten Labormethoden wie die Destillation – Vorläufer der Chemie."
	return d

func _build_visuals() -> void:
	# Flache Kruste (Placeholder) — halb im Boden, wie die Erz-Blöcke.
	_add_placeholder_box(Vector3(0.9, 0.18, 0.9), Color(1.0, 0.97, 0.85), "sulfur")
	AppLogger.log_debug("SulfurCrust Placeholder-Box erstellt.", "sulfur_crust")
