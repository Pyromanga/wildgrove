class_name PetBattleSpecies
extends RefCounted

## PetBattleSpecies — einheitlicher Zugriff auf JEDE Tierart (handgebaute Tiere + AnimalSpeciesDB):
## Anzeigename, Bauplan, Größe, Tempo und das komplette Aussehen als Pet-Config. Gebraucht für
## die Gegner im Pet-Kampf (es gibt dort keinen Tier-Node) und für das Belohnungs-Pet.
##
## Datenbank-Arten: direkt aus AnimalSpeciesDB. Handgebaute Arten (Reh, Hase, ...): deren Aussehen
## steckt in der jeweiligen .gd — dafür wird eine Instanz kurz erzeugt (NICHT in den Baum gehängt),
## _on_ready_extended() aufgerufen und die Felder gelesen, genau wie ZooMeasure. Ergebnis wird
## gecacht (die Arten ändern sich zur Laufzeit nicht).

const ANIMAL_DIR := "res://scripts/entities/animals/"

## Handgebaute Tiere; Dateiname = type_id.capitalize() (siehe WorldEntityRegistry).
const CURATED_IDS: Array[String] = ["deer", "rabbit", "boar", "fox", "squirrel", "sheep", "bee", "spider", "snake", "bear", "fish"]
const CURATED_NAMES_DE: Dictionary = {
	"deer": "Reh", "rabbit": "Kaninchen", "boar": "Wildschwein", "fox": "Fuchs",
	"squirrel": "Eichhörnchen", "sheep": "Schaf", "bee": "Biene", "spider": "Spinne",
	"snake": "Schlange", "bear": "Bär", "fish": "Fisch",
}

## Felder, aus denen ein Pet sein Aussehen bekommt (Schlüssel = on_spawn()-Config von PetComponent;
## dieselben Namen tragen AnimalSpeciesDB-Einträge und die "_"-Felder von AnimalBase).
const APPEARANCE_KEYS: Array[String] = [
	"color", "body_size", "speed", "ear_style", "tail_style", "snout_style", "headgear_style",
	"tail_scale", "body_plan", "wing_style", "back_style", "body_shape", "leg_style",
	"pattern_style", "pattern_color", "accent_style",
]

static var _cache: Dictionary = {}

## Alle Arten (handgebaute zuerst, dann die Datenbank alphabetisch).
static func all_ids() -> Array[String]:
	var ids: Array[String] = CURATED_IDS.duplicate()
	var db_ids: Array = AnimalSpeciesDB.SPECIES.keys()
	db_ids.sort()
	for id in db_ids:
		ids.append(String(id))
	return ids

static func exists(species_id: String) -> bool:
	var id: String = species_id.to_lower()
	return CURATED_IDS.has(id) or AnimalSpeciesDB.SPECIES.has(id)

## Profil einer Art: {species_id, display_name, body_plan, body_size, speed, catch_name,
## appearance (Config-Felder, siehe APPEARANCE_KEYS)} — leer bei unbekannter Art.
static func profile(species_id: String) -> Dictionary:
	var id: String = species_id.to_lower()
	if _cache.has(id):
		return _cache[id] as Dictionary
	var result: Dictionary = _build_profile(id)
	if not result.is_empty():
		_cache[id] = result
	return result

static func display_name(species_id: String) -> String:
	var p: Dictionary = profile(species_id)
	return String(p.get("display_name", species_id))

static func _build_profile(id: String) -> Dictionary:
	if AnimalSpeciesDB.SPECIES.has(id):
		var def: Dictionary = AnimalSpeciesDB.get_definition(id)
		var appearance: Dictionary = {}
		for key in APPEARANCE_KEYS:
			if def.has(key):
				appearance[key] = def[key]
		return {
			"species_id": id,
			"display_name": String(def.get("display_name", id.capitalize())),
			"body_plan": int(def.get("body_plan", AnimalVisualProfile.BodyPlan.QUADRUPED)),
			"body_size": def.get("body_size", Vector3(0.3, 0.4, 0.3)) as Vector3,
			"speed": float(def.get("speed", 4.0)),
			"catch_name": id,
			"appearance": appearance,
		}
	if CURATED_IDS.has(id):
		return _build_curated_profile(id)
	return {}

static func _build_curated_profile(id: String) -> Dictionary:
	var script: Script = load(ANIMAL_DIR + id.capitalize() + ".gd") as Script
	if script == null:
		return {}
	var animal: AnimalBase = script.new() as AnimalBase
	if animal == null:
		return {}
	animal._on_ready_extended()
	var appearance: Dictionary = {}
	for key in APPEARANCE_KEYS:
		appearance[key] = animal.get("_" + key)
	var result := {
		"species_id": id,
		"display_name": String(CURATED_NAMES_DE.get(id, id.capitalize())),
		"body_plan": animal._body_plan,
		"body_size": animal._body_size,
		"speed": animal._speed,
		# Beim Fangen speichert AnimalCatcher den Klassennamen ("Deer") als species_id — gleich
		# halten, damit PetAbilities.default_for_species() dieselben Fähigkeiten liefert.
		"catch_name": String(script.get_global_name()),
		"appearance": appearance,
	}
	animal.free()
	return result
