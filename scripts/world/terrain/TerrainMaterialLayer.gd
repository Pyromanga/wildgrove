class_name TerrainMaterialLayer
extends RefCounted

## TerrainMaterialLayer — dünn besetzte Schicht für ABGELEGTES Bodenmaterial,
## als Geschwister-Schicht zu TerrainEditLayer (2026-09-26, "Sand aus der
## Wüste in einem Wald-Biom ablegen und es bleibt Sand").
##
## WARUM EINE EIGENE SCHICHT: TerrainField.get_material_at() beantwortet "was
## für Boden ist hier" genau wie get_height_at() "wie hoch ist es hier" — rein
## prozedural (Biom-Oberflächenmaterial, siehe BiomeDefinition.surface_material)
## SOLANGE kein Spieler etwas Bestimmtes hier abgelegt hat. Legt ein Spieler
## Sand in einem Wald-Biom ab, überschreibt das die natürliche Antwort an GENAU
## diesem Gitterpunkt, dauerhaft (Save/Load) — exakt dasselbe Delta-Prinzip wie
## bei TerrainEditLayer, nur mit einem String (Material-Item-ID) statt einem
## Float (Höhen-Delta) als Wert.
##
## DASSELBE GITTER wie TerrainEditLayer (SPACING/world_to_lattice/lattice_to_world
## dort wiederverwendet, nicht dupliziert) — ein abgelegtes Material sitzt
## immer an einem Punkt, der auch als Höhen-Gitterpunkt existiert (Ablegen
## verändert grundsätzlich auch die Höhe, siehe WorldService.request_terrain_edit()).
##
## Reine Datenklasse: kein Node, kein Service, keine Engine-Abhängigkeit.

## { Vector2i (Gitterindex): String (Material-Item-ID) }
var _overrides: Dictionary = {}

func is_empty() -> bool:
	return _overrides.is_empty()

func get_override_count() -> int:
	return _overrides.size()

## "" = kein Override an diesem Gitterpunkt (natürliches Material gilt).
func get_override_at_lattice(p: Vector2i) -> String:
	return String(_overrides.get(p, ""))

## Wie oben, aber ab einer Weltposition (rundet auf den nächsten Gitterpunkt —
## Material ist diskret/kategorisch, anders als die Höhe macht Interpolation
## zwischen zwei Materialien keinen Sinn).
func get_override_at(world_x: float, world_z: float) -> String:
	if _overrides.is_empty():
		return ""
	return get_override_at_lattice(TerrainEditLayer.world_to_lattice(world_x, world_z))

## Setzt/löscht den Override an einem Gitterpunkt. material_id = "" löscht ihn
## (Punkt fällt zurück auf das natürliche Material).
func set_override(p: Vector2i, material_id: String) -> void:
	if material_id.is_empty():
		_overrides.erase(p)
	else:
		_overrides[p] = material_id

func clear_override(p: Vector2i) -> void:
	_overrides.erase(p)

## Löscht die Overrides an allen übergebenen Gitterpunkten (z.B. nach einem
## Grabvorgang, der das dort abgelegte Material entfernt hat — siehe
## WorldService.request_terrain_edit()).
func clear_overrides(points: Array[Vector2i]) -> void:
	for p in points:
		_overrides.erase(p)

## Setzt denselben Override an allen übergebenen Gitterpunkten (z.B. nach
## einem Aufschütten-Vorgang mit einem bestimmten Material).
func set_overrides(points: Array[Vector2i], material_id: String) -> void:
	for p in points:
		set_override(p, material_id)

func clear() -> void:
	_overrides.clear()

# ─────────────────────────────────────────────
# Persistenz
# ─────────────────────────────────────────────

## Array von {"x": int, "z": int, "m": String} — analog zu DigFindRegistry.to_save()
## (Dictionary-Records statt PackedFloat32Array wie TerrainEditLayer, weil hier
## ein String-Feld dabei ist).
func to_save() -> Array:
	var out: Array = []
	for p: Vector2i in _overrides.keys():
		out.append({"x": p.x, "z": p.y, "m": String(_overrides[p])})
	return out

## Lädt aus to_save()-Format. Ungültige/unvollständige Einträge werden übersprungen
## statt zu crashen — ein kaputter Save darf die Welt nicht killen.
func load_save(raw: Variant) -> void:
	_overrides.clear()
	if not raw is Array:
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		if not (rec.has("x") and rec.has("z") and rec.has("m")):
			continue
		var x: Variant = rec["x"]
		var z: Variant = rec["z"]
		var m: Variant = rec["m"]
		if not (x is float or x is int) or not (z is float or z is int) or not (m is String):
			continue
		if String(m).is_empty():
			continue
		set_override(Vector2i(int(x), int(z)), String(m))
