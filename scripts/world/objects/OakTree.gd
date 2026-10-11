extends HarvestableEntity
class_name OakTree

## OakTree — Fällbarer Baum (Woodcutting-Interaktion).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.

func _get_entity_type_id() -> String:
	return "oak_tree"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "chop"
	d.label        = "Eiche fällen"
	d.duration     = 3.0
	d.xp_type      = "woodcutting"
	d.xp_amount    = 25
	d.loot_table   = preload("res://data/loot_tables/loot_oak_tree.tres")
	d.yield_stat_id = "gathering_yield_wood"
	d.speed_stat_id = "gathering_speed_wood"
	d.inspect_text = "Eine mächtige Eiche. Der Stamm ist mindestens 50 Jahre alt — das Holz riecht nach Harz und feuchter Erde."
	return d

## Wachstumsstadium (Wunsch "Bäume in verschiedenen Stadien" + Folge-Wunsch "über Spieltage
## hinweg wachsen"): siehe TreeGrowthStage.suffix_for_tree()-Kommentar — ein nachgewachsener
## Baum (planted_day gesetzt, siehe _spawn_config) altert wirklich mit der Weltzeit, ein
## originaler Weltbaum bekommt weiterhin nur statische Positions-Varietät. Überschreibt
## HarvestableEntity._tree_growth_suffix(), damit _on_day_advanced() (dort) diesen Baum bei
## jedem Tageswechsel neu bewertet, nicht nur einmalig bei _build_visuals().
func _tree_growth_suffix() -> String:
	var day_count: int = _ctx.get_world().day_count if is_instance_valid(_ctx) and is_instance_valid(_ctx.get_world()) else 0
	return TreeGrowthStage.suffix_for_tree(global_position, _spawn_config.get("planted_day", -1), day_count)

func _build_visuals() -> void:
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		# "" (MATURE) hängt an "oak" nichts an, Factory3D findet also weiterhin "tree_oak".
		factory.create_simple_tree(self, "oak" + _tree_growth_suffix())
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — OakTree Placeholder-Visual.", "oak_tree")
		_add_placeholder_cylinder(0.15, 2.0, Color(0.4, 0.25, 0.1))
