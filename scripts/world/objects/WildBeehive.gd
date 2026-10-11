extends HarvestableEntity
class_name WildBeehive

## WildBeehive — Wilder Bienenstock (Skill "beekeeping" / Imkerei).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Bienen verständigen sich über den Schwänzeltanz — Richtung und
## Entfernung zu Futterquellen. Spawnt auf Wiese und in Wäldern
## (BiomeRegistry). Respawn: siehe WorldService.configure().
##
## Der Bildungstext lebt in data/skills/beekeeping.tres.

func _get_entity_type_id() -> String:
	return "wild_beehive"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_wild_beehive"
	d.label        = "Honig ernten"
	d.duration     = 3.5
	d.xp_type      = "beekeeping"
	d.xp_amount    = 25
	d.loot_table   = preload("res://data/loot_tables/loot_wild_beehive.tres")
	d.inspect_text = "Ein wilder Bienenstock, es summt wie Strom in den Wurzeln. Wusstest du? Bienen tanzen, um sich gegenseitig den Weg zu Blüten zu zeigen (Schwänzeltanz)."
	return d

func _build_visuals() -> void:
	_add_placeholder_box(Vector3(0.5, 0.65, 0.5), Color(0.95, 0.85, 0.6), "wax")
	AppLogger.log_debug("WildBeehive Placeholder-Box erstellt.", "wild_beehive")
