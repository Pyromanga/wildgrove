extends HarvestableEntity
class_name IronOre

## IronOre — Abbaubarer Erzblock (Mining-Interaktion).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.

func _get_entity_type_id() -> String:
	return "iron_ore"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "mine_iron"
	d.label        = "Eisenerz abbauen"
	d.duration     = 4.0
	d.xp_type      = "mining"
	d.speed_stat_id = "gathering_speed_ore"
	d.xp_amount    = 40
	d.loot_table   = preload("res://data/loot_tables/loot_iron_ore.tres")
	d.inspect_text = "Ein Eisenerzblock. Die rötlich-braunen Adern im Stein deuten auf reiche Eisenvorkommen hin."
	return d

func _build_visuals() -> void:
	_add_placeholder_box(Vector3(0.8, 0.8, 0.8), Color(0.9, 0.88, 0.85), "ore_iron")
	AppLogger.log_debug("IronOre BoxMesh 0.8m erstellt.", "iron_ore")
