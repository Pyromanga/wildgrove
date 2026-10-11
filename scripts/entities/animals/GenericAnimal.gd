extends AnimalBase
class_name GenericAnimal

## GenericAnimal — EINE AnimalBase-Unterklasse für ALLE Tierarten aus AnimalSpeciesDB.
##
## Wunsch "nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen": vorher brauchte
## jede Tierart eine eigene .gd-Datei (siehe Deer.gd/Boar.gd/... — die bleiben als kuratierte
## Handarbeit-Tiere bestehen, siehe WorldEntityRegistry-Kommentar). Für "massiv viele" wäre
## das nicht mehr nachhaltig (40+ Dateien, die sich nur in ein paar Zahlen/Enum-Werten
## unterscheiden). GenericAnimal baut stattdessen seine Statistiken zur Laufzeit aus
## AnimalSpeciesDB.SPECIES[species_id] zusammen — eine neue Tierart entsteht dann rein über
## einen Daten-Eintrag (siehe tools/animal_species/generate_animal_species_db.py), nicht über
## eine neue Code-Datei.
##
## WOHER KENNT EINE INSTANZ IHRE species_id? EntityOrchestrator.spawn_entity() setzt VOR
## add_child() (und damit vor _ready()/_on_ready_extended()) das Meta "entity_type" = type_id und
## vergibt den Node-Namen "<type_id>_<x>_<y>_<z>". Das Meta ist die exakte Registry-/DB-ID und
## funktioniert auch für IDs mit "_" ("wolf_spider"); der Namens-Präfix bis zum ersten "_" ist nur
## noch der letzte Fallback (Tests, die den Namen von Hand setzen). Vorher war der Namens-Präfix
## der EINZIGE Weg — "wolf_spider" wurde dadurch zu "wolf" und sah aus wie ein Hund.
## Für Tests/direkte Instanziierung (kein spawn_entity(), Name bleibt der Default-
## Klassenname): set_species_id() VOR add_child() aufrufen, siehe dort.
const LOG_CAT_GENERIC := "GenericAnimal"

## Nur gesetzt, wenn set_species_id() explizit aufgerufen wurde (siehe Klassenkommentar,
## Testpfad) — hat Vorrang vor der aus dem Node-Namen abgeleiteten ID.
var _explicit_species_id: String = ""
var _species_id: String = ""
var _display_name: String = "Tier"
var _inspect_text: String = "Ein Tier."

## Für Tests/manuellen Einsatz OHNE EntityOrchestrator.spawn_entity() (dort bleibt der
## Node-Name sonst der generische Klassenname "GenericAnimal", aus dem sich keine species_id
## ableiten lässt). MUSS vor add_child()/_ready() aufgerufen werden.
func set_species_id(species_id: String) -> void:
	_explicit_species_id = species_id

func get_species_id() -> String:
	return _species_id

## Reihenfolge: explizit gesetzt > Meta "entity_type" (vom EntityOrchestrator VOR add_child()
## gesetzt, also schon in _ready() lesbar — die Spawn-Config dagegen erst in on_spawn(), danach)
## > Node-Name-Präfix.
## BUGFIX ("Vogelspinne sah aus wie ein Hund"): früher NUR der Namens-Präfix bis zum ersten "_".
## Für "wolf_spider" ergab das "wolf" (also ein Wolf = Hund), für "garden_spider" "garden"
## (unbekannt → Standard-Vierbeiner), "mountain_goat" → "mountain", "grass_snake" → "grass" …
## Das Meta entity_type ist exakt die Registry-/DB-ID und kennt diese Falle nicht.
func _resolve_species_id() -> String:
	if not _explicit_species_id.is_empty():
		return _explicit_species_id
	var spawn_type_id: String = String(get_meta("entity_type", ""))
	if not spawn_type_id.is_empty() and not AnimalSpeciesDB.get_definition(spawn_type_id).is_empty():
		return spawn_type_id
	return name.split("_")[0]

func _on_ready_extended() -> void:
	_species_id = _resolve_species_id()
	var def: Dictionary = AnimalSpeciesDB.get_definition(_species_id)
	if def.is_empty():
		AppLogger.log_warn(
			"GenericAnimal: unbekannte species_id '%s' (aus Node-Name '%s' abgeleitet) — falle auf AnimalBase-Defaults zurück."
			% [_species_id, name],
			LOG_CAT_GENERIC
		)
		return

	_display_name  = def.get("display_name", "Tier")
	_inspect_text  = def.get("inspect_text", "Ein Tier.")
	name           = _display_name
	_color         = def.get("color", _color)
	_body_size     = def.get("body_size", _body_size)
	_speed         = def.get("speed", _speed)
	_flee_radius   = def.get("flee_radius", _flee_radius)
	_idle_time     = def.get("idle_time", _idle_time)
	_wander_range  = def.get("wander_range", _wander_range)
	_ear_style      = def.get("ear_style", _ear_style)
	_tail_style     = def.get("tail_style", _tail_style)
	_snout_style    = def.get("snout_style", _snout_style)
	_headgear_style = def.get("headgear_style", _headgear_style)
	_tail_scale     = def.get("tail_scale", _tail_scale)
	_body_plan      = def.get("body_plan", _body_plan)
	_wing_style     = def.get("wing_style", _wing_style)
	_back_style     = def.get("back_style", _back_style)
	_body_shape     = def.get("body_shape", _body_shape)
	_leg_style      = def.get("leg_style", _leg_style)
	_pattern_style  = def.get("pattern_style", _pattern_style)
	_pattern_color  = def.get("pattern_color", _pattern_color)
	_accent_style   = def.get("accent_style", _accent_style)
	_aquatic        = def.get("aquatic", _aquatic)

func get_inspect_text() -> String:
	return _inspect_text
