class_name ZooMeasure
extends RefCounted

## ZooMeasure — ermittelt für jede Tierart Name, Art-ID und die ECHTE Bounding-Box des
## Tiermodells (damit der Glaskasten wirklich "groß genug" ist, auch für Geweih, Hörner,
## Spinnenbeine, lange Schlangen oder spätere neue Arten — ohne dass hier Maße gepflegt werden).
##
## Vorgehen: Tier-Instanz mit .new() erzeugen (NICHT in den Baum hängen), _on_ready_extended()
## aufrufen (setzt Name/Maße/Stile), AnimalBase.build_visual_profile() → AnimalVisualBuilder.build()
## und über alle MeshInstance3D die Boxen vereinigen. Nur auf Basis der Engine-Geometrie
## testbar (GUT), nicht rein arithmetisch — die Arithmetik steckt in ZooLayout.

const ANIMAL_DIR := "res://scripts/entities/animals/"

## Handgebaute Tiere (je eigene .gd, siehe WorldEntityRegistry). Dateiname = type_id.capitalize().
const CURATED_IDS: Array[String] = ["deer", "rabbit", "boar", "fox", "squirrel", "sheep", "bee", "spider", "snake", "bear", "fish"]
## Deren Schildtexte (die Klassen heißen intern englisch, die Schilder sollen deutsch sein).
const CURATED_NAMES_DE := {
	"deer": "Reh", "rabbit": "Kaninchen", "boar": "Wildschwein", "fox": "Fuchs",
	"squirrel": "Eichhörnchen", "sheep": "Schaf", "bee": "Biene", "spider": "Spinne",
	"snake": "Schlange", "bear": "Bär", "fish": "Fisch",
}

## Alle Tierarten, die der Zoo zeigt: kuratierte + alles aus AnimalSpeciesDB.
static func all_type_ids() -> Array[String]:
	var ids: Array[String] = CURATED_IDS.duplicate()
	var db_ids: Array = AnimalSpeciesDB.SPECIES.keys()
	db_ids.sort()
	for id in db_ids:
		ids.append(String(id))
	return ids

## {"type_id", "display_name", "aabb": AABB, "aquatic": bool, "body_plan": int}
## — leer, falls die Art nicht instanziierbar ist.
static func measure(type_id: String) -> Dictionary:
	var animal: AnimalBase = _instantiate(type_id)
	if animal == null:
		return {}
	animal._on_ready_extended()
	var profile: AnimalVisualProfile = animal.build_visual_profile()
	var visuals: Node3D = AnimalVisualBuilder.build(profile)
	var box: AABB = visuals_aabb(visuals)
	var display_name: String = String(CURATED_NAMES_DE.get(type_id, ""))
	if display_name.is_empty() and animal is GenericAnimal:
		display_name = (animal as GenericAnimal)._display_name
	if display_name.is_empty():
		display_name = type_id.capitalize()
	var result := {
		"type_id": type_id,
		"display_name": display_name,
		"aabb": box,
		"aquatic": animal.is_aquatic(),
		"body_plan": profile.body_plan,
	}
	visuals.free()
	animal.free()
	return result

static func _instantiate(type_id: String) -> AnimalBase:
	if CURATED_IDS.has(type_id):
		var script: Script = load(ANIMAL_DIR + type_id.capitalize() + ".gd") as Script
		if script == null:
			return null
		return script.new() as AnimalBase
	if AnimalSpeciesDB.get_definition(type_id).is_empty():
		return null
	var generic := GenericAnimal.new()
	generic.set_species_id(type_id)
	return generic

## Vereinigte Bounding-Box aller Meshes unter `root`, im lokalen Raum von `root`s PARENT
## (die eigene Transform von `root` — z.B. die 180°-Drehung der Schlange — zählt also mit).
static func visuals_aabb(root: Node3D) -> AABB:
	var state := {"box": AABB(), "has": false}
	_accumulate(root, root.transform, state)
	return state["box"] as AABB

static func _accumulate(node: Node, xf: Transform3D, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh != null:
			var box: AABB = xf * mesh_inst.get_aabb()
			if bool(state["has"]):
				state["box"] = (state["box"] as AABB).merge(box)
			else:
				state["box"] = box
				state["has"] = true
	for child in node.get_children():
		if child is Node3D:
			_accumulate(child, xf * (child as Node3D).transform, state)
