extends HarvestableEntity
class_name RockBoulder

## RockBoulder — Abbaubarer Felsblock (Mining-Interaktion).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Rekonstruiert: WorldEntityRegistry.register_all()/KNOWN_PROP_TYPES sowie
## DataManifest.ITEMS referenzierten "rock_boulder" bzw. "Stone.tres" bereits
## mit dem Kommentar "RockBoulder-Drop Item (Round 78)" / "neues Biom
## 'mountain'" — die zugehörige Runde 78 (die dieses Skript, das Stone-Item,
## die Loot-Tabelle sowie den "mountain"-Fall in
## Factory3D.create_rock_boulder() eingeführt haben muss) wurde nie
## ausgeliefert. Nachgezogen im gleichen Muster wie Cactus/PineTree/
## IceCrystal/MushroomCluster/FallenTree — Visual-Arbeit (Factory3D.
## create_rock_boulder(), inkl. "desert"/"winter"-Farbfälle) war bereits
## vorhanden, nur ohne Aufrufer. "mountain"-Farbfall in Factory3D + Test in
## test_factory3d_nature.gd hier ergänzt (siehe dortiger Kommentar).

func _get_entity_type_id() -> String:
	return "rock_boulder"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "mine_rock_boulder"
	d.label        = "Felsblock abbauen"
	d.duration     = 3.5
	d.xp_type      = "mining"
	d.speed_stat_id = "gathering_speed_ore"
	d.xp_amount    = 25
	d.loot_table   = preload("res://data/loot_tables/loot_rock_boulder.tres")
	d.inspect_text = "Ein massiver Felsblock. Mit dem richtigen Werkzeug lassen sich brauchbare Steinbrocken herausschlagen."
	return d

func _build_visuals() -> void:
	# Factory3D.create_rock_boulder(parent, biome_id) übernimmt die
	# Biom-Einfärbung (desert/winter/mountain/Default) — gleiches
	# Fallback-Pattern wie Cactus/PineTree. RockBoulder kennt sein eigenes
	# Biom nicht (gleiche strukturelle Lücke wie bei jedem anderen
	# HarvestableEntity, siehe FallenTree._build_visuals()-Kommentar) — bis
	# dahin fest "mountain" übergeben, da es dort am häufigsten spawnt.
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_rock_boulder(self, "mountain")
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — RockBoulder Placeholder-Visual.", "rock_boulder")
		_add_placeholder_box(Vector3(0.8, 0.6, 0.8), Color(0.42, 0.42, 0.40))
