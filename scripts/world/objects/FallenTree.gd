extends HarvestableEntity
class_name FallenTree

## FallenTree — Liegender, abbaubarer Baumstamm (Woodcutting-Interaktion,
## niedrigerer Ertrag als ein stehender Baum, dafür schneller).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Round 79 — Anfrage "Toter Wald: wenige lebende Bäume & viele Baumstämme".
## "fallen_tree" stand bereits in mehreren prop_chances (forest, dense_forest,
## winter, swamp), aber ohne registrierten Entity-Typ → wurde überall
## stillschweigend gefiltert. Mit diesem Skript spawnt es jetzt in ALLEN
## bestehenden Biomen, nicht nur im neuen "dead_forest" (siehe
## BiomeRegistry.gd — dort mit Abstand am höchsten gewichtet).
##
## Drop bewusst "log_normal" (bereits existierendes generisches Holz-Item,
## data/items/LogNormal.tres) statt eines neuen "log_rotten"/Ähnlichem —
## kein Content-Bedarf für eine eigene Holzsorte hier, nur weniger Menge
## als bei einem frisch gefällten Baum (siehe loot_fallen_tree.tres).

func _get_entity_type_id() -> String:
	return "fallen_tree"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id            = "gather_fallen_tree"
	d.label         = "Baumstamm zerlegen"
	d.duration      = 2.0
	d.xp_type       = "woodcutting"
	d.xp_amount     = 15
	d.loot_table    = preload("res://data/loot_tables/loot_fallen_tree.tres")
	d.yield_stat_id = "gathering_yield_wood"
	d.speed_stat_id = "gathering_speed_wood"
	d.inspect_text  = "Ein umgestürzter, halb morscher Baumstamm. Aus dem noch brauchbaren Holz lässt sich einiges herausholen."
	return d

func _build_visuals() -> void:
	# Factory3D.create_fallen_tree(parent, biome_id) — biome_id-Parameter
	# ist im aktuellen Factory3D-Code (Stand Round 79) ungenutzt (keine
	# Farbverzweigung wie bei create_rock_boulder()), daher hier ein fester
	# Default statt einer echten Biom-Auflösung — funktional identisch,
	# egal welcher Wert übergeben wird. Nicht mitgefixt (kein Teil dieser
	# Anfrage, siehe Kommentar dort falls das mal auffällt).
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_fallen_tree(self, "forest")
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — FallenTree Placeholder-Visual.", "fallen_tree")
		_add_placeholder_cylinder(0.3, 4.0, Color(0.35, 0.22, 0.09))
