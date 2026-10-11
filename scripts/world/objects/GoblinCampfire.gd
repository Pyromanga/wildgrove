extends StaticBody3D
class_name GoblinCampfire

## GoblinCampfire — natürlich generiertes Goblin-Lagerfeuer.
##
## Direkter Schwester-Typ zu GraveyardGravestone.gd (siehe dortiger
## Klassenkommentar für die volle Begründung des Musters) — Wunsch "Analog
## für Goblins/Lagerfeuer bauen": EXAKT dieselbe Rolle wie ein natürlicher
## Friedhof-Grabstein, nur mit spawn_type_id "goblin" statt "skeleton" und
## OHNE Cluster-Bildung (ein Lagerfeuer ist ein einzelnes Lager, kein
## Gräberfeld — kein Analogon zu ChunkEntitySpawner._spawn_graveyard()
## nötig, "goblin_campfire" läuft über den normalen Einzel-Prop-Pfad in
## _spawn_props()).
##
## Rein passiv/nicht interagierbar (kein InteractableComponent — nichts zu
## plündern, reine Weltdeko + Spawn-Marker). Die einzige Aufgabe ist, sich
## bei AmbientSpawnService an-/abzumelden; alles Weitere (Timing,
## Population-Cap, tatsächliches Spawnen) übernimmt der Dienst zentral,
## GENAU WIE bei GraveyardGravestone — beide Klassen unterscheiden sich nur
## in Geometrie und dem an register_point() übergebenen spawn_type_id.

const LOG_CAT := "GoblinCampfire"

var _ctx: IEntityContext = null
var _ambient_spawner: AmbientSpawnService = null

func _ready() -> void:
	# Gleicher Namens-Bugfix wie GraveyardGravestone.gd/Gravestone.gd — siehe
	# dortiger Kommentar.
	if name == get_class() or name.begins_with("@"):
		name = "GoblinCampfire_%d" % (get_instance_id() % 9999)
	set_multiplayer_authority(1)
	add_to_group("goblin_camp")
	_build_visuals()
	_build_collision()

func on_spawn(_config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	_ambient_spawner = ctx.get_ambient_spawner() if is_instance_valid(ctx) else null

	# Nur die Autorität führt Buchhaltung über Spawn-Punkte — auf Clients
	# existiert dieses Lager nur als repliziertes Darstellungsobjekt
	# (identisches Autoritätsmuster zu GraveyardGravestone.on_spawn()).
	if is_multiplayer_authority() and is_instance_valid(_ambient_spawner):
		var uuid: String = get_meta("entity_uuid", "")
		if uuid.is_empty():
			AppLogger.log_warn("on_spawn(): keine entity_uuid — Anmeldung bei AmbientSpawnService übersprungen.", LOG_CAT)
		else:
			_ambient_spawner.register_point(uuid, global_position, "goblin")

func on_despawn() -> void:
	if is_instance_valid(_ambient_spawner):
		var uuid: String = get_meta("entity_uuid", "")
		if not uuid.is_empty():
			_ambient_spawner.unregister_point(uuid)

# ─────────────────────────────────────────────
# Visuals — schlichter Lagerfeuer-Platzhalter: Steinring + Holzstapel +
# emissive "Glut"-Fläche (kein echtes Partikelfeuer nötig für einen reinen
# Weltmarker, siehe Kind.TARGET-Requisiten-Kommentare in
## BuildPieceDefinition.gd für dasselbe Sparsamkeitsprinzip bei Weltprops).
# ─────────────────────────────────────────────

func _build_visuals() -> void:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.35, 0.33, 0.30)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.35
	ring_mesh.outer_radius = 0.5
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring_mesh
	ring_mi.material_override = stone_mat
	ring_mi.position.y = 0.08
	ring_mi.rotation.x = PI * 0.5
	add_child(ring_mi)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.30, 0.18, 0.09)
	var wood_mesh := BoxMesh.new()
	wood_mesh.size = Vector3(0.5, 0.25, 0.12)
	for i in range(3):
		var wood_mi := MeshInstance3D.new()
		wood_mi.mesh = wood_mesh
		wood_mi.material_override = wood_mat
		wood_mi.position.y = 0.15
		wood_mi.rotation.y = i * (PI / 3.0)
		add_child(wood_mi)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.95, 0.45, 0.12)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.95, 0.45, 0.12)
	glow_mat.emission_energy_multiplier = 1.5
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.16
	glow_mesh.height = 0.28
	var glow_mi := MeshInstance3D.new()
	glow_mi.mesh = glow_mesh
	glow_mi.material_override = glow_mat
	glow_mi.position.y = 0.22
	add_child(glow_mi)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := CylinderShape3D.new()
	sh.radius = 0.55
	sh.height = 0.4
	col.shape = sh
	col.position.y = 0.2
	add_child(col)
