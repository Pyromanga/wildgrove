class_name ZooPlacer
extends RefCounted

## ZooPlacer — stellt am Spawn für JEDE Tierart einen Glaskasten mit Namensschild auf und setzt
## das Tier lebendig (aber still, "captive") hinein.
##
## Aufgerufen von WorldSpawner.spawn_all() auf jedem Peer (Entities entstehen pro Peer lokal und
## deterministisch — gleiche Reihenfolge, gleiche Maße, gleiche Positionen; kein Netzwerkcode nötig,
## genau wie bei den NPCs/Ackerbeeten dort).
##
## Größe der Kästen: aus der echten Modell-Bounding-Box (ZooMeasure → ZooLayout.inner_size()),
## nicht aus gepflegten Zahlen — "groß genug für das Tier" gilt damit automatisch auch für jede
## künftig hinzugefügte Tierart. Anordnung: ZooLayout.pack(). Gelände: jeder Kasten bekommt einen
## Sockel, der bis zum tiefsten Punkt seiner Grundfläche reicht (und über den Wasserspiegel).
##
## Nicht gegen die echte Godot-Laufzeit verifiziert (keine Binary in der Sandbox) — Layout-/Maß-
## Arithmetik ist per Unit-Test abgedeckt (test_zoo_layout.gd), Geometrie/Spawn per test_glass_case.gd.

const LOG_CAT := "ZooPlacer"
## Mindesthöhe der Kastenoberfläche über dem Wasserspiegel (liegt der Spawn am Wasser).
const WATER_CLEARANCE: float = 0.25
## Höhenschritte, an denen das Gelände unter einem Kasten abgetastet wird.
const MAX_FOUNDATION: float = 12.0
## Wo im Fischbecken die Fischmitte sitzt (Anteil der Innenhöhe).
const FISH_HEIGHT_FRACTION: float = 0.4

## Sortierung: erst Bauplan (Säugetiere, Insekten, Spinnen, Schlangen, Fische), dann nach
## Modellgröße aufsteigend, dann Name — nebeneinander stehen so ähnliche Tiere in ähnlicher Größe.
static func _sort_entries(entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["body_plan"]) != int(b["body_plan"]):
			return int(a["body_plan"]) < int(b["body_plan"])
		var sa: float = (a["aabb"] as AABB).size.length()
		var sb: float = (b["aabb"] as AABB).size.length()
		if not is_equal_approx(sa, sb):
			return sa < sb
		return String(a["display_name"]) < String(b["display_name"])
	)

## Platziert den Zoo. Gibt die Anzahl aufgestellter Kästen zurück.
static func place(orchestrator: EntityOrchestrator, terrain: TerrainField) -> int:
	var entries: Array = []
	for type_id: String in ZooMeasure.all_type_ids():
		var info: Dictionary = ZooMeasure.measure(type_id)
		if info.is_empty():
			AppLogger.log_warn("Zoo: Tierart '%s' nicht messbar — übersprungen." % type_id, LOG_CAT)
			continue
		entries.append(info)
	_sort_entries(entries)

	var inners: Array[Vector3] = []
	var footprints: Array[Vector2] = []
	for info: Dictionary in entries:
		var inner: Vector3 = ZooLayout.inner_size(info["aabb"] as AABB, bool(info["aquatic"]))
		inners.append(inner)
		footprints.append(ZooLayout.footprint(inner))
	var packed: Dictionary = ZooLayout.pack(footprints)
	var centers: Array = packed["centers"]

	var placed := 0
	for i in range(entries.size()):
		var info: Dictionary = entries[i]
		var inner: Vector3 = inners[i]
		var local_center: Vector2 = centers[i]
		var cx: float = ZooLayout.ZOO_RECT.position.x + local_center.x
		var cz: float = ZooLayout.ZOO_RECT.position.y + local_center.y
		var ground := _ground_profile(terrain, cx, cz, footprints[i])
		var base_y: float = ground["base_y"]
		var aquatic: bool = bool(info["aquatic"])

		orchestrator.spawn_entity("glass_case", Vector3(cx, base_y, cz), {
			"inner": inner,
			"label": String(info["display_name"]),
			"water": aquatic,
			"foundation": ground["foundation"],
		})

		var box: AABB = info["aabb"]
		var center: Vector3 = box.get_center()
		var animal_y: float
		if aquatic:
			animal_y = base_y + GlassCase.FLOOR_TOP + inner.y * FISH_HEIGHT_FRACTION - center.y
		else:
			animal_y = base_y + GlassCase.FLOOR_TOP - box.position.y
		var animal_pos := Vector3(cx - center.x, animal_y, cz - center.z)
		orchestrator.spawn_entity(String(info["type_id"]), animal_pos, {"captive": true})
		placed += 1

	AppLogger.log_info(
		"Zoo aufgestellt: %d Glaskästen (%.0f × %.0f m)." % [placed, (packed["size"] as Vector2).x, (packed["size"] as Vector2).y],
		LOG_CAT
	)
	return placed

## Bodenhöhe (base_y = Oberkante des Geländes, auf der der Kasten steht) und Sockeltiefe.
## base_y = höchster Punkt unter der Grundfläche, mindestens knapp über dem Wasser; die Sockeltiefe
## überbrückt den Abstand bis zum tiefsten Punkt (kein Spalt unter dem Kasten an Hängen).
static func _ground_profile(terrain: TerrainField, cx: float, cz: float, fp: Vector2) -> Dictionary:
	if not is_instance_valid(terrain):
		return {"base_y": 0.0, "foundation": 0.8}
	var hx: float = fp.x * 0.5
	var hz: float = fp.y * 0.5
	var hi: float = -INF
	var lo: float = INF
	for dx in [-hx, 0.0, hx]:
		for dz in [-hz, 0.0, hz]:
			var h: float = terrain.get_height_at(cx + dx, cz + dz)
			hi = maxf(hi, h)
			lo = minf(lo, h)
	var water: float = terrain.get_water_level_at(cx, cz)
	var base_y: float = maxf(hi, water + WATER_CLEARANCE)
	var foundation: float = clampf(base_y - lo + 0.4, 0.8, MAX_FOUNDATION)
	return {"base_y": base_y, "foundation": foundation}
