extends HarvestableEntity
class_name CopperOre

## CopperOre — Abbaubarer Kupfererzblock (Mining-Interaktion, niedriger Level als Eisen).
## Erster Beweis dass HarvestableEntity mit zwei Erztypen korrekt funktioniert.

func _get_entity_type_id() -> String:
	return "copper_ore"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "mine_copper"
	d.label        = "Kupfererz abbauen"
	d.duration     = 3.0
	d.xp_type      = "mining"
	d.speed_stat_id = "gathering_speed_ore"
	d.xp_amount    = 20
	d.loot_table   = preload("res://data/loot_tables/loot_copper_ore.tres")
	d.inspect_text = "Ein Kupfererzblock. Die grünlichen Oxidationsspuren verraten reiche Kupfervorkommen."
	return d

func _build_visuals() -> void:
	_add_placeholder_box(Vector3(0.75, 0.75, 0.75), Color(0.85, 0.9, 0.85), "ore_copper")
	AppLogger.log_debug("CopperOre BoxMesh 0.75m erstellt.", "copper_ore")
