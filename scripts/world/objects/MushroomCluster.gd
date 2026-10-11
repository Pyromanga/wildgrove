extends HarvestableEntity
class_name MushroomCluster

## MushroomCluster — Erntbarer Pilz-Cluster (Foraging-Interaktion, gleicher
## Skill wie Cactus/IceCrystal).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Round 79 — Anfrage "Wald: Pilze & viel Baum spawn". "mushroom_cluster"
## stand bereits in mehreren prop_chances (forest 0.08, dense_forest 0.12,
## swamp 0.15), aber ohne registrierten Entity-Typ (siehe
## WorldEntityRegistry.KNOWN_PROP_TYPES-Kommentar) → wurde überall
## stillschweigend gefiltert. Mit diesem Skript spawnt es jetzt in allen
## drei bereits bestehenden Biomen, nicht nur im Wald.
##
## Visual-Arbeit war bereits fertig (Factory3D.create_mushroom_cluster(),
## drei Farbvarianten "brown"/"red"/"orange", siehe MeshCache.gd), nur ohne
## Aufrufer — gleiches Muster wie Cactus/PineTree/RockBoulder. Typ wird hier
## random gewählt (kein Aufrufer hat das bisher getan) für optische Vielfalt
## im Wald statt immer derselben Braun-Variante.

const MUSHROOM_TYPES: Array[String] = ["brown", "red", "orange"]

func _get_entity_type_id() -> String:
	return "mushroom_cluster"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id            = "harvest_mushroom_cluster"
	d.label         = "Pilze sammeln"
	d.duration      = 2.0
	d.xp_type       = "foraging"
	d.xp_amount     = 12
	d.loot_table    = preload("res://data/loot_tables/loot_mushroom_cluster.tres")
	d.yield_stat_id = "gathering_yield_foraging"
	d.inspect_text  = "Ein Büschel wilder Pilze am Boden. Manche Sorten sind essbar, manche nur zu Färbemitteln zu verarbeiten."
	return d

func _build_visuals() -> void:
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		var mushroom_type: String = MUSHROOM_TYPES[randi() % MUSHROOM_TYPES.size()]
		factory.create_mushroom_cluster(self, mushroom_type)
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — MushroomCluster Placeholder-Visual.", "mushroom_cluster")
		_add_placeholder_cylinder(0.12, 0.25, Color(0.50, 0.30, 0.10))
