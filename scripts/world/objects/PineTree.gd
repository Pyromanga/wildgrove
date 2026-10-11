extends HarvestableEntity
class_name PineTree

## PineTree — Fällbarer Winter-Baum (Woodcutting-Interaktion), analog OakTree.
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Round 77 — schließt die zweite Hälfte der "weiterhin offen"-Liste aus
## TODO-offene-probleme.md (Round 75/76): winter.prop_chances enthält
## "pine_tree" bereits seit Round 74, WorldEntityRegistry.KNOWN_PROP_TYPES
## bisher ohne "pine_tree" → ChunkEntitySpawner hat den Eintrag bisher
## stillschweigend gefiltert. Mit diesem Skript + Registrierung spawnt
## PineTree jetzt im Winter-Biom — keine weitere Änderung an
## ChunkEntitySpawner/BiomeRegistry nötig.
##
## Visual-Arbeit war (wie bei Cactus, Round 76) bereits fertig in Factory3D:
## create_pine_tree(parent, snow: bool) existiert samt Test in
## test_factory3d_nature.gd, nur bisher ohne Aufrufer. snow=true, da
## PineTree ausschließlich im Winter-Biom spawnt (snow_coverage = 1.0).

func _get_entity_type_id() -> String:
	return "pine_tree"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id            = "chop_pine"
	d.label         = "Tanne fällen"
	d.duration      = 3.0
	d.xp_type       = "woodcutting"
	d.xp_amount     = 25
	d.loot_table    = preload("res://data/loot_tables/loot_pine_tree.tres")
	d.yield_stat_id = "gathering_yield_wood"
	d.speed_stat_id = "gathering_speed_wood"
	d.inspect_text  = "Eine schneebedeckte Tanne. Das Holz ist harzig und eignet sich gut zum Verarbeiten."
	return d

## Wachstumsstadium siehe OakTree._tree_growth_suffix()-Kommentar / TreeGrowthStage.gd.
func _tree_growth_suffix() -> String:
	var day_count: int = _ctx.get_world().day_count if is_instance_valid(_ctx) and is_instance_valid(_ctx.get_world()) else 0
	return TreeGrowthStage.suffix_for_tree(global_position, _spawn_config.get("planted_day", -1), day_count, 3)

func _build_visuals() -> void:
	# Factory3D.create_pine_tree(self, true) liefert das gecachte
	# Schnee-Prefab — gleiches Muster wie Cactus._build_visuals().
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_pine_tree(self, true, _tree_growth_suffix())
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — PineTree Placeholder-Visual.", "pine_tree")
		_add_placeholder_cylinder(0.16, 2.2, Color(0.85, 0.90, 0.95))
