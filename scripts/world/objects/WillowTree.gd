extends HarvestableEntity
class_name WillowTree

## WillowTree — Fällbare Weide (niedrigeres Level, schneller als Eiche).
## Erster Beweis dass HarvestableEntity mit zwei Baumtypen korrekt funktioniert.

func _get_entity_type_id() -> String:
	return "willow_tree"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "chop"
	d.label        = "Weide fällen"
	d.duration     = 2.0
	d.xp_type      = "woodcutting"
	d.xp_amount    = 15
	d.loot_table   = preload("res://data/loot_tables/loot_willow_tree.tres")
	d.yield_stat_id = "gathering_yield_wood"
	d.speed_stat_id = "gathering_speed_wood"
	d.inspect_text = "Eine schlanke Weide. Die herabhängenden Äste streifen den Boden — das Holz ist weich und leicht zu fällen."
	return d

## Wachstumsstadium siehe OakTree._tree_growth_suffix()-Kommentar / TreeGrowthStage.gd. salt=1
## (statt 0 wie Oak) wirkt nur im statischen (planted_day == -1) Fall — damit Weide an einer
## Position nicht zufällig exakt dasselbe Stadium wie eine Eiche an derselben Zellmitte bekäme.
func _tree_growth_suffix() -> String:
	var day_count: int = _ctx.get_world().day_count if is_instance_valid(_ctx) and is_instance_valid(_ctx.get_world()) else 0
	return TreeGrowthStage.suffix_for_tree(global_position, _spawn_config.get("planted_day", -1), day_count, 1)

func _build_visuals() -> void:
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_simple_tree(self, "willow" + _tree_growth_suffix())
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — WillowTree Placeholder.", "willow_tree")
		_add_placeholder_cylinder(0.10, 2.5, Color(0.35, 0.28, 0.12))
