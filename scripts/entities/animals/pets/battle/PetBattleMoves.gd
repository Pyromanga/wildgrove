class_name PetBattleMoves
extends RefCounted

## PetBattleMoves — Attacken der Pet-Kämpfe (rein statische Datentabelle, keine Nodes).
##
## Jedes Pet bekommt je nach TYP vier Attacken (Pokémon-Prinzip, aber ohne Lernlisten pro Art):
##   1. Rempler    (Normal, schwach, immer verfügbar)
##   2. Typ-Basis  (Level 1)     — Stärke 55
##   3. Hilfsattacke (Level 3)   — Status: Angriff/Verteidigung/Tempo rauf bzw. runter
##   4. Typ-Finale (Level 5)     — Stärke 85, ungenauer
## Das Tier-Level (PetLeveling, 1–100) schaltet sie frei — ein frisch gefangenes Pet kämpft also mit
## zwei Attacken, ein erfahrenes mit allen vier.
##
## Move-Dictionary: id, name, type (PetBattleTypes.Type), power (0 = Status), accuracy (0–100),
## poison (Wahrscheinlichkeit 0–1, vergiftet das Ziel), stat ("atk"/"def"/"spd"), stages (±),
## target ("self"/"enemy" — nur Status).

const LEVEL_UTILITY: int = 3
const LEVEL_FINISHER: int = 5

const MOVES: Dictionary = {
	"rempler":         {"name": "Rempler",         "type": PetBattleTypes.Type.NORMAL,   "power": 40, "accuracy": 100},
	# Raubtier
	"biss":            {"name": "Biss",            "type": PetBattleTypes.Type.PREDATOR, "power": 55, "accuracy": 95},
	"zerfetzen":       {"name": "Zerfetzen",       "type": PetBattleTypes.Type.PREDATOR, "power": 85, "accuracy": 80},
	# Huftier
	"tritt":           {"name": "Tritt",           "type": PetBattleTypes.Type.HOOFED,   "power": 55, "accuracy": 95},
	"sturmlauf":       {"name": "Sturmlauf",       "type": PetBattleTypes.Type.HOOFED,   "power": 85, "accuracy": 80},
	# Nager
	"nagen":           {"name": "Nagen",           "type": PetBattleTypes.Type.RODENT,   "power": 55, "accuracy": 95},
	"flitzer":         {"name": "Flitzer",         "type": PetBattleTypes.Type.RODENT,   "power": 85, "accuracy": 80},
	# Insekt
	"stich":           {"name": "Stich",           "type": PetBattleTypes.Type.INSECT,   "power": 55, "accuracy": 95},
	"schwarm":         {"name": "Schwarmangriff",  "type": PetBattleTypes.Type.INSECT,   "power": 85, "accuracy": 80},
	# Gift (vergiftet mit Wahrscheinlichkeit)
	"giftbiss":        {"name": "Giftbiss",        "type": PetBattleTypes.Type.VENOM,    "power": 55, "accuracy": 95, "poison": 0.30},
	"giftspritzer":    {"name": "Giftspritzer",    "type": PetBattleTypes.Type.VENOM,    "power": 80, "accuracy": 85, "poison": 0.50},
	# Wasser
	"wasserstrahl":    {"name": "Wasserstrahl",    "type": PetBattleTypes.Type.AQUA,     "power": 55, "accuracy": 95},
	"flutwelle":       {"name": "Flutwelle",       "type": PetBattleTypes.Type.AQUA,     "power": 85, "accuracy": 80},
	# Hilfsattacken (Status)
	"einschuechtern":  {"name": "Einschüchtern",   "type": PetBattleTypes.Type.NORMAL,   "power": 0, "accuracy": 100, "stat": "atk", "stages": -1, "target": "enemy"},
	"einigeln":        {"name": "Einigeln",        "type": PetBattleTypes.Type.NORMAL,   "power": 0, "accuracy": 100, "stat": "def", "stages":  1, "target": "self"},
	"aufbaeumen":      {"name": "Aufbäumen",       "type": PetBattleTypes.Type.NORMAL,   "power": 0, "accuracy": 100, "stat": "atk", "stages":  1, "target": "self"},
	"antritt":         {"name": "Antritt",         "type": PetBattleTypes.Type.NORMAL,   "power": 0, "accuracy": 100, "stat": "spd", "stages":  1, "target": "self"},
}

## [Basis, Finale, Hilfsattacke] je Typ.
const MOVESET_BY_TYPE: Dictionary = {
	PetBattleTypes.Type.PREDATOR: ["biss", "zerfetzen", "einschuechtern"],
	PetBattleTypes.Type.HOOFED:   ["tritt", "sturmlauf", "einigeln"],
	PetBattleTypes.Type.RODENT:   ["nagen", "flitzer", "antritt"],
	PetBattleTypes.Type.INSECT:   ["stich", "schwarm", "aufbaeumen"],
	PetBattleTypes.Type.VENOM:    ["giftbiss", "giftspritzer", "einschuechtern"],
	PetBattleTypes.Type.AQUA:     ["wasserstrahl", "flutwelle", "einigeln"],
}

## Attacken-IDs, die ein Pet von diesem Typ auf diesem Level hat (Reihenfolge = Anzeige-Reihenfolge).
static func moves_for(type_id: int, level: int) -> Array[String]:
	var result: Array[String] = ["rempler"]
	var entry: Array = MOVESET_BY_TYPE.get(type_id, [])
	if entry.size() < 3:
		return result
	result.append(String(entry[0]))
	if level >= LEVEL_UTILITY:
		result.append(String(entry[2]))
	if level >= LEVEL_FINISHER:
		result.append(String(entry[1]))
	return result

static func get_move(move_id: String) -> Dictionary:
	return MOVES.get(move_id, {}) as Dictionary

static func is_attack(move: Dictionary) -> bool:
	return int(move.get("power", 0)) > 0

static func name_of(move_id: String) -> String:
	return String(get_move(move_id).get("name", move_id))
