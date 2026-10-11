class_name Factory3D
extends RefCounted

## Factory3D — Erzeugt 3D-Weltobjekte über den MeshCache.
##
##   VORHER: extends ServiceNode — lief durch die komplette 8-phasige Boot-Pipeline,
##           hatte eine ghost "data"-Dependency, belegte einen Registrierungsslot.
##   NACHHER: Normale RefCounted-Klasse. Wird einmal in WorldService instantiiert
##            und als öffentliche Variable `factory3d` exponiert.
##
## Zugriff für Entities/Components: IEntityContext.get_factory3d()
##   (WorldService ist sowieso die Voraussetzung für 3D-Entities)
##
## Bar3D extends Node3D (muss im Tree leben für Tweens) — deshalb kein pure static.
##
## Alle create_*()-Methoden gehen ausschließlich über cache (MeshCache) — es gibt
## keinen zweiten Erzeugungspfad. cache muss gesetzt und gebaut sein, bevor die
## erste create_*()-Methode aufgerufen wird (WorldService.warmup_mesh_cache()
## erledigt das vor dem ersten Spawn).

const LOG_CAT := "Factory3D"

## MeshCache — gesetzt von WorldService nach Session-Boot.
var cache: MeshCache = null

## tree_type: "oak" | "willow" | "maple" — wählt die gecachte Szene
## ("tree_<type>" in MeshCache). Unbekannter/leerer Typ fällt auf "oak" zurück
## (Default-Parameter erhält bestehende Aufrufer ohne Typ-Argument lauffähig).
## BUGFIX (2026-09-20, "keine Farbunterschiede bei Baumarten"): vorher immer
## hart "tree_oak", unabhängig vom Aufrufer (Oak/Willow/Maple sahen alle
## identisch aus).
func create_simple_tree(parent: Node3D, tree_type: String = "oak") -> Node3D:
	if not _require_cache():
		return Node3D.new()
	var key := "tree_%s" % tree_type
	if not cache.scenes.has(key):
		key = "tree_oak"
	var node := cache.instantiate_scene(key)
	if parent:
		parent.add_child(node)
	return node

func create_3d_bar(parent: Node3D) -> Bar3D:
	var bar_node := Bar3D.new()
	bar_node.name     = "UI_ProgressBar3D"
	bar_node.position = Vector3(0.0, 2.5, 0.0)
	bar_node.visible  = false

	if _require_cache():
		var bg := MeshInstance3D.new()
		bg.mesh = cache.get_mesh("bar_bg")
		bg.set_surface_override_material(0, cache.get_material(Color(0.15, 0.15, 0.15, 0.8), true))
		bar_node.add_child(bg)

		var fill := MeshInstance3D.new()
		fill.name = "Fill"
		fill.mesh = cache.get_mesh("bar_fg")
		fill.set_surface_override_material(0, cache.get_material(Color(0.10, 0.85, 0.10), true))
		fill.position.z = 0.01
		bar_node.add_child(fill)
		bar_node.setup(fill)

	if parent:
		parent.add_child(bar_node)
	return bar_node

## Tanne (Winter-Biom) — gecachtes Prefab; snow=true liefert die Variante mit Schnee-Kappen.
## `stage_suffix` (Wunsch "Bäume in verschiedenen Stadien darstellen", siehe TreeGrowthStage.gd):
## "" (Default, MATURE) hält den bisherigen Schlüssel unverändert — bestehende Aufrufer/Tests
## ohne Stadium-Wissen (z.B. test_factory3d_nature.gd) bekommen weiterhin genau denselben Baum.
func create_pine_tree(parent: Node3D, snow: bool = false, stage_suffix: String = "") -> Node3D:
	if not _require_cache():
		return Node3D.new()
	var key := ("tree_pine_snow" if snow else "tree_pine") + stage_suffix
	var node := cache.instantiate_scene(key)
	if parent:
		parent.add_child(node)
	return node

## Kaktus (Wüste) — gecachtes Prefab.
func create_cactus(parent: Node3D) -> Node3D:
	if not _require_cache():
		return Node3D.new()
	var node := cache.instantiate_scene("cactus")
	if parent:
		parent.add_child(node)
	return node

## Farn — gecachtes Prefab.
func create_fern(parent: Node3D) -> Node3D:
	if not _require_cache():
		return Node3D.new()
	var node := cache.instantiate_scene("fern")
	if parent:
		parent.add_child(node)
	return node

## Gibt true zurück wenn der MeshCache verfügbar und gebaut ist.
func _cache_ready() -> bool:
	return cache != null and cache.is_built()

## Prüft ob der Cache bereit ist, loggt sonst einen Fehler statt still zu degradieren.
func _require_cache() -> bool:
	if _cache_ready():
		return true
	AppLogger.log_error("Factory3D: MeshCache nicht gesetzt oder nicht gebaut — Objekt kann nicht erzeugt werden.", LOG_CAT)
	return false

# ─────────────────────────────────────────────
# Hilfsklassen
# ─────────────────────────────────────────────

class Bar3D extends Node3D:
	var _fill: MeshInstance3D
	var _max_width: float = 1.1

	func setup(fill_node: MeshInstance3D) -> void:
		_fill = fill_node
		var q_mesh := _fill.mesh as QuadMesh
		if q_mesh:
			_max_width = q_mesh.size.x

	func update(percent: float) -> void:
		if not is_instance_valid(_fill):
			return
		var p: float = clamp(percent, 0.0, 1.0)
		_fill.scale.x    = p
		_fill.position.x = (p - 1.0) * (_max_width / 2.0)

# ─────────────────────────────────────────────
# Welt-Authentizität: Natur-Objekte (alle über MeshCache, Zufall nur in Transform)
# ─────────────────────────────────────────────

## Liegender Baumstamm — gecachtes Log-Mesh, Länge/Radius per Instanz skaliert.
func create_fallen_tree(parent: Node3D, biome_id: String = "forest") -> Node3D:
	if not _require_cache():
		return Node3D.new()

	var root := Node3D.new()
	root.name = "FallenTree"

	var length := randf_range(3.0, 7.0)
	var radius := randf_range(0.22, 0.45)

	var trunk := MeshInstance3D.new()
	trunk.mesh = cache.get_mesh("fallen_log")
	trunk.set_surface_override_material(0, cache.get_textured_material(Color(0.35, 0.22, 0.09), "wood"))
	# fallen_log-Basismesh: bottom_radius 0.25, height 2.4 — hier auf Ziel-Radius/-Länge skaliert
	trunk.scale = Vector3(radius / 0.25, length / 2.4, radius / 0.25)
	trunk.rotation_degrees.z = 90.0
	trunk.position = Vector3(0.0, radius, 0.0)
	root.add_child(trunk)

	if randf() < 0.5:
		var shroom_count := randi_range(1, 3)
		for i in range(shroom_count):
			var shroom := cache.instantiate_scene("mushroom_brown")
			shroom.scale = Vector3(0.4, 0.4, 0.4)
			shroom.position = Vector3(
				randf_range(-length * 0.3, length * 0.3),
				radius * 1.5,
				randf_range(-0.1, 0.1)
			)
			root.add_child(shroom)

	if parent:
		parent.add_child(root)
	return root

## Pilz-Cluster: 1–4 gecachte Pilz-Prefabs, Typ bestimmt Farbe.
func create_mushroom_cluster(parent: Node3D, mushroom_type: String = "brown") -> Node3D:
	if not _require_cache():
		return Node3D.new()

	var root := Node3D.new()
	root.name = "MushroomCluster"

	var count := randi_range(1, 4)
	for i in range(count):
		var shroom := cache.instantiate_scene("mushroom_%s" % mushroom_type)
		shroom.position = Vector3(
			randf_range(-0.4, 0.4),
			0.0,
			randf_range(-0.4, 0.4)
		)
		shroom.scale = Vector3.ONE * randf_range(0.7, 1.3)
		root.add_child(shroom)

	if parent:
		parent.add_child(root)
	return root

## Felsblock — gecachte Einheitskugel, per Instanz non-uniform skaliert und eingefärbt.
func create_rock_boulder(parent: Node3D, biome_id: String = "forest") -> Node3D:
	if not _require_cache():
		return Node3D.new()

	var rock_color: Color
	match biome_id:
		"desert":   rock_color = Color(0.65, 0.50, 0.30)
		"winter":   rock_color = Color(0.70, 0.75, 0.82)
		"mountain": rock_color = Color(0.30, 0.30, 0.32)  # dunkleres Granitgrau statt generischem Default
		_:          rock_color = Color(0.42, 0.42, 0.40)

	var rock := MeshInstance3D.new()
	rock.mesh = cache.get_mesh("rock_unit")
	rock.set_surface_override_material(0, cache.get_textured_material(rock_color, "stone"))

	var radius := randf_range(0.4, 0.9)
	var flatten := randf_range(0.5, 0.8)
	rock.scale = Vector3(radius, radius * flatten, radius)
	rock.scale *= Vector3(randf_range(0.8, 1.2), randf_range(0.6, 1.0), randf_range(0.8, 1.2))
	rock.rotation_degrees.y = randf_range(0, 360)

	if parent:
		parent.add_child(rock)
	return rock
