class_name WildPlant
extends HarvestableEntity

## WildPlant — Basis aller wild wachsenden Kräuter (herbalism) und Blumen (gardening).
## Subklassen (PlantChamomile …) geben nur _plant_id() zurück; Name, XP, Loot, Fakt und Aussehen
## kommen aus PlantCatalog. Eigener Skriptpfad pro Art, weil EntityOrchestrator/MultiplayerSpawner
## Skriptpfad → type_id auflösen (siehe WorldEntityRegistry.register_all()).
##
## Lifecycle, Despawn und Harvest-State: HarvestableEntity. Nachwachsen: RespawnService
## (WorldService.configure(), Zeit PLANT_RESPAWN_SEC).

## Wilde Pflanzen wachsen zügig nach — sie sind Verbrauchsgut, nicht Meilenstein.
const PLANT_RESPAWN_SEC: float = 240.0

func _plant_id() -> String:
	return ""

func _get_entity_type_id() -> String:
	return PlantCatalog.entity_type(_plant_id())

func _build_interactable_data() -> InteractableData:
	var p: Dictionary = PlantCatalog.get_plant(_plant_id())
	var d := InteractableData.new()
	d.id            = "harvest_%s" % _plant_id()
	d.label         = "%s sammeln" % String(p.get("name", "Pflanze"))
	d.duration      = 1.5
	d.xp_type       = String(p.get("skill", "foraging"))
	d.xp_amount     = int(p.get("xp", 10))
	d.loot_table    = load(PlantCatalog.wild_loot_path(_plant_id())) as LootTable
	d.yield_stat_id = "gathering_yield_foraging"
	d.inspect_text  = PlantCatalog.inspect_text(_plant_id())
	return d

func _build_visuals() -> void:
	var p: Dictionary = PlantCatalog.get_plant(_plant_id())
	if p.is_empty():
		_add_placeholder_box(Vector3(0.2, 0.3, 0.2), Color(0.2, 0.5, 0.2))
		return
	PlantVisualBuilder.build(self, p["look"])
