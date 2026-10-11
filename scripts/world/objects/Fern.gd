extends HarvestableEntity
class_name Fern

## Fern — Erntbares Unterholz-Grün (Foraging-Interaktion, gleicher Skill wie
## Cactus/IceCrystal/MushroomCluster).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## "fern" war der letzte verbleibende Prefab-ohne-Entity-Typ aus der
## Round-75/76-Liste (siehe WorldEntityRegistry-Klassenkommentar) — stand
## bereits in drei prop_chances (forest 0.20, dense_forest 0.30, swamp 0.08),
## ohne registrierten Entity-Typ überall stillschweigend gefiltert. Mit
## diesem Skript + Registrierung in WorldEntityRegistry.register_all()/
## KNOWN_PROP_TYPES spawnt Fern jetzt dort tatsächlich.
##
## Anfrage: Fern soll in JEDEM Biom außer Eis (winter) und Wüste (desert)
## spawnen — zusätzlich zu forest/dense_forest/swamp daher neu in
## meadow/mountain/dead_forest ergänzt (siehe BiomeRegistry.gd). winter und
## desert bewusst ausgenommen (thematisch passt kein Farn in Schnee/Sand,
## Factory3D.create_fern() hat auch keine entsprechende Prefab-Variante).
##
## Visual-Arbeit war bereits fertig (Factory3D.create_fern(), Prefab "fern"
## im MeshCache) — gleiches Muster wie Cactus/PineTree/RockBoulder, nur ohne
## Aufrufer.

func _get_entity_type_id() -> String:
	return "fern"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id            = "harvest_fern"
	d.label         = "Farn sammeln"
	d.duration      = 1.5
	d.xp_type       = "foraging"
	d.xp_amount     = 8
	d.loot_table    = preload("res://data/loot_tables/loot_fern.tres")
	d.yield_stat_id = "gathering_yield_foraging"
	d.inspect_text  = "Ein büscheliges Farnkraut. Die Blätter lassen sich zu Fasern verarbeiten."
	return d

func _build_visuals() -> void:
	# Factory3D.create_fern() liefert das gecachte Prefab (MeshCache "fern")
	# — gleiches Muster wie Cactus/PineTree._build_visuals().
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_fern(self)
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — Fern Placeholder-Visual.", "fern")
		_add_placeholder_box(Vector3(0.35, 0.4, 0.35), Color(0.20, 0.45, 0.15))
