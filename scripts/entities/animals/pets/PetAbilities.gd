class_name PetAbilities
extends RefCounted

## PetAbilities — Zentrale, statische Definition der Pet-Fähigkeiten.
##
## Fähigkeiten sind reine String-IDs (Konstanten unten), gespeichert als
## Array[String] in PetComponent._abilities / config["abilities"] /
## get_save_state()["abilities"]. Ein Pet kann mehrere Fähigkeiten gleichzeitig
## besitzen (z.B. Eber: Bergbau + Graben) — PetComponent spawnt dafür pro
## Fähigkeit eine eigene PetAbilityComponent-Instanz (siehe dort).
##
## Diese Klasse hält zwei Tabellen:
##   1. GATHERING/WOODCUTTING/MINING_TYPES — welche HarvestableEntity-Typ-IDs
##      (siehe WorldEntityRegistry.KNOWN_PROP_TYPES) zu welcher Sammel-Fähigkeit
##      gehören. Bewusst als eigene, statische Liste geführt (gleiche Konvention
##      wie WorldEntityRegistry.KNOWN_PROP_TYPES) statt über die Node-Gruppen
##      "trees"/"plants"/"ores" zu filtern — diese Gruppen enthalten auch
##      Sonderfälle (wild_beehive, charcoal_kiln), die kein Pet einfach
##      "abbauen" soll, nur weil sie in derselben Gruppe registriert sind.
##   2. DEFAULT_ABILITIES_BY_SPECIES — welche Fähigkeiten ein frisch gefangenes
##      Tier standardmäßig bekommt, geschlüsselt über den GDScript-Klassennamen
##      der jeweiligen AnimalBase-Unterklasse (Boar, Fox, ...). Reines
##      Balancing/Flavor, leicht anpassbar — hat keinen Einfluss auf
##      Save-Kompatibilität, da ein bereits gezähmtes Pet seine tatsächlichen
##      Fähigkeiten selbst persistiert (siehe PetComponent.get_save_state()).

const GATHERING   := "gathering"
const MINING      := "mining"
const WOODCUTTING := "woodcutting"
const COMBAT      := "combat"
const DIGGING     := "digging"

const ALL: Array[String] = [GATHERING, MINING, WOODCUTTING, COMBAT, DIGGING]

## Entity-Typ-IDs (WorldEntityRegistry.KNOWN_PROP_TYPES) je Sammel-Fähigkeit.
## Neue Weltobjekt-Typen müssen hier manuell ergänzt werden, sonst ignorieren
## Pets sie einfach (kein Crash, kein Fehler-Log — gleiche Fallback-Haltung
## wie WorldEntityRegistry.KNOWN_PROP_TYPES selbst).
const GATHERING_TYPES: Array[String] = ["fern", "mushroom_cluster", "cactus", "ice_crystal"]
const WOODCUTTING_TYPES: Array[String] = ["oak_tree", "willow_tree", "maple_tree", "pine_tree", "fallen_tree"]
const MINING_TYPES: Array[String] = ["rock_boulder", "iron_ore", "copper_ore", "sulfur_crust", "meteorite", "fulgurite"]

## Default-Fähigkeiten pro Tierart (Klassenname der AnimalBase-Unterklasse,
## siehe AnimalCatcher.catch_animal()). Unbekannte/zukünftige Arten (z.B. neue
## Tiere ohne Eintrag hier) fallen auf DEFAULT_FALLBACK zurück.
const DEFAULT_ABILITIES_BY_SPECIES: Dictionary = {
	"Boar":     [MINING, DIGGING],
	"Fox":      [COMBAT],
	"Sheep":    [GATHERING],
	"Deer":     [GATHERING],
	"Rabbit":   [DIGGING],
	"Squirrel": [WOODCUTTING, GATHERING],
	"bear":     [COMBAT, DIGGING],
	# Wunsch "nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen": GenericAnimal-
	# Arten (AnimalSpeciesDB) liefern ihre echte species_id ("wolf", "trout", ...) statt eines
	# gemeinsamen Klassennamens (siehe AnimalCatcher.catch_animal()), deshalb können auch sie
	# hier individuell kuratiert werden — bewusst nur eine kleine, flavourvolle Auswahl statt
	# aller 39+ Arten, der Rest fällt auf DEFAULT_FALLBACK zurück (kein Crash, kein Fehler).
	"wolf":     [COMBAT],
	"coyote":   [COMBAT],
	"badger":   [DIGGING, MINING],
	"otter":    [GATHERING],
	# Reittiere: keine Fähigkeiten, sie warten eng beim Besitzer aufs Aufsteigen (MountDefinitions).
	"horse":    [],
	"donkey":   [],
	"beetle":   [DIGGING],
	"ant":      [DIGGING],
}
const DEFAULT_FALLBACK: Array[String] = [GATHERING]

## Gibt die Default-Fähigkeiten für eine gefangene Tierart zurück. Kopiert die
## Liste explizit — niemals die Konstanten-Referenz direkt weitergeben, sonst
## könnte ein Aufrufer (append() auf das Ergebnis) versehentlich die globale
## Konstante für ALLE künftigen Tiere derselben Art mutieren.
static func default_for_species(species_class_name: String) -> Array[String]:
	var found: Variant = DEFAULT_ABILITIES_BY_SPECIES.get(species_class_name, DEFAULT_FALLBACK)
	var result: Array[String] = []
	for a in found:
		result.append(String(a))
	return result

## Für Sammel-Fähigkeiten (gathering/woodcutting/mining): welche Typ-IDs
## gehören zu ability_id. Leeres Array für combat/digging (die laufen über
## Node-Gruppen bzw. direkte Terrain-Edits, nicht über HarvestableEntity-Typ-IDs
## — siehe PetAbilityComponent._process_combat()/_process_digging()).
static func harvest_type_ids_for(ability_id: String) -> Array[String]:
	match ability_id:
		GATHERING:   return GATHERING_TYPES
		WOODCUTTING: return WOODCUTTING_TYPES
		MINING:      return MINING_TYPES
		_:           return []

static func is_harvest_ability(ability_id: String) -> bool:
	return ability_id == GATHERING or ability_id == WOODCUTTING or ability_id == MINING

static func is_known(ability_id: String) -> bool:
	return ability_id in ALL

## Normalisiert eine rohe Config-/Save-Liste zu Array[String] — verwirft
## unbekannte IDs (z.B. Tippfehler in einem manuell editierten Save oder ein
## Feature-Rollback) statt sie stillschweigend als Fähigkeit zu akzeptieren,
## für die keine PetAbilityComponent je etwas tut.
static func sanitize(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for v in raw:
			var s := String(v)
			if is_known(s) and not result.has(s):
				result.append(s)
	return result
