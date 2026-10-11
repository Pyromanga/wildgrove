extends StaticBody3D
class_name GraveyardGravestone

## GraveyardGravestone — natürlich generiertes Friedhof-Grab.
##
## WICHTIGE ABGRENZUNG (Wunsch "Spieler-Gräber sollen keine Skelette
## spawnen — Terraria nutzt zwei Objekte dafür"): dieser Entity-Typ
## ("graveyard_gravestone") ist bewusst ein KOMPLETT ANDERER Typ als:
##   - "gravestone" (Gravestone.gd) — Spieler-Tod-Loot (ADR-037), spawnt nie
##     Skelette, wird von DeathLootService gespawnt, nicht von hier.
##   - der dekorative Bau-Grabstein (BuildPieceDefinition PropShape
##     GRAVESTONE_STELE/GRAVESTONE_SLAB) — reine Deko, Spieler platziert ihn
##     jederzeit frei, spawnt ebenfalls nie Skelette.
## Nur DIESER dritte Typ hier UND der quest-freigeschaltete Spawner-Bau-
## Grabstein (siehe BuildPiece.gd / BuildPieceDefinition.requires_quest_id)
## melden sich beim AmbientSpawnService an. Drei Objekte statt zwei, weil
## wir zusätzlich zur Terraria-Trennung (natürlich vs. Spieler-Deko) noch
## einen dritten, bewusst FREIGESCHALTETEN Spieler-Spawner-Typ wollen (siehe
## Quest "quest_talia_graveyard_watch").
##
## Spawnt gruppenweise über ChunkEntitySpawner._spawn_graveyard() (mehrere
## Instanzen bilden zusammen einen kleinen "Friedhof" statt eines einzelnen
## Grabs — siehe dortiger Kommentar).
##
## Rein passiv/nicht interagierbar (kein InteractableComponent wie
## Gravestone.gd — nichts zu plündern). Die einzige Aufgabe ist, sich bei
## AmbientSpawnService an-/abzumelden; alles Weitere (Timing, Population-
## Cap, tatsächliches Spawnen) übernimmt der Dienst zentral.

const LOG_CAT := "GraveyardGravestone"

var _ctx: IEntityContext = null
var _ambient_spawner: AmbientSpawnService = null

func _ready() -> void:
	# Gleicher Namens-Bugfix wie Gravestone.gd/AnimalBase — siehe dortiger
	# Kommentar (deterministischer, positionsbasierter Name vom Orchestrator
	# darf nicht durch einen pro-Prozess-unterschiedlichen Default ersetzt werden).
	if name == get_class() or name.begins_with("@"):
		name = "GraveyardGravestone_%d" % (get_instance_id() % 9999)
	set_multiplayer_authority(1)
	add_to_group("graveyard")
	_build_visuals()
	_build_collision()

func on_spawn(_config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	_ambient_spawner = ctx.get_ambient_spawner() if is_instance_valid(ctx) else null

	# Nur die Autorität führt Buchhaltung über Spawn-Punkte — auf Clients
	# existiert dieses Grab nur als repliziertes Darstellungsobjekt (identisches
	# Autoritätsmuster zu Gravestone._schedule_despawn()).
	if is_multiplayer_authority() and is_instance_valid(_ambient_spawner):
		var uuid: String = get_meta("entity_uuid", "")
		if uuid.is_empty():
			AppLogger.log_warn("on_spawn(): keine entity_uuid — Anmeldung bei AmbientSpawnService übersprungen.", LOG_CAT)
		else:
			_ambient_spawner.register_point(uuid, global_position, "skeleton")

func on_despawn() -> void:
	if is_instance_valid(_ambient_spawner):
		var uuid: String = get_meta("entity_uuid", "")
		if not uuid.is_empty():
			_ambient_spawner.unregister_point(uuid)

# ─────────────────────────────────────────────
# Visuals — leicht variierter Platzhalter, geometrisch identisch zu
# Gravestone.gd (gleiche Bauteil-Silhouette, aber grau-verwittert statt
# frisch, und ohne "Grab"-Label — kein interagierbarer Loot-Container).
# ─────────────────────────────────────────────

func _build_visuals() -> void:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.42, 0.43, 0.40)  # verwittertes Grau-Grün statt frischem Grau
	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.55, 0.85, 0.14)
	var stone_mi := MeshInstance3D.new()
	stone_mi.mesh = stone_mesh
	stone_mi.material_override = stone_mat
	stone_mi.position.y = 0.42
	add_child(stone_mi)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := BoxShape3D.new()
	sh.size = Vector3(0.55, 0.85, 0.14)
	col.shape = sh
	col.position.y = 0.42
	add_child(col)
