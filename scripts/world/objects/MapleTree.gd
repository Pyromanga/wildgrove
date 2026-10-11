extends HarvestableEntity
class_name MapleTree

## MapleTree — Fällbarer Ahorn (höheres Level, mehr XP als Eiche).

func _get_entity_type_id() -> String:
	return "maple_tree"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "chop"
	d.label        = "Ahorn fällen"
	d.duration     = 5.0
	d.xp_type      = "woodcutting"
	d.xp_amount    = 60
	d.loot_table   = preload("res://data/loot_tables/loot_maple_tree.tres")
	d.yield_stat_id = "gathering_yield_wood"
	d.speed_stat_id = "gathering_speed_wood"
	d.inspect_text = "Ein alter Ahorn. Sein Stamm ist breit und knorrig — das Holz ist hart und wertvoll."
	return d

## Wachstumsstadium siehe OakTree._tree_growth_suffix()-Kommentar / TreeGrowthStage.gd.
func _tree_growth_suffix() -> String:
	var day_count: int = _ctx.get_world().day_count if is_instance_valid(_ctx) and is_instance_valid(_ctx.get_world()) else 0
	return TreeGrowthStage.suffix_for_tree(global_position, _spawn_config.get("planted_day", -1), day_count, 2)

func _build_visuals() -> void:
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_simple_tree(self, "maple" + _tree_growth_suffix())
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — MapleTree Placeholder.", "maple_tree")
		_add_placeholder_cylinder(0.20, 2.0, Color(0.45, 0.22, 0.08))
