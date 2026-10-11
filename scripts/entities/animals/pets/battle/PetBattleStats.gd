class_name PetBattleStats
extends RefCounted

## PetBattleStats — Kampfwerte (HP/Angriff/Verteidigung/Tempo) eines Tiers aus Körpergröße, Lauf-
## Tempo, Typ und Level. Reine Rechnung, keine Nodes.
##
## Warum aus bestehenden Daten abgeleitet statt eigener Tabelle pro Art: es gibt 70+ Arten
## (AnimalSpeciesDB + handgebaute) und es kommen laufend neue dazu — jede Art hat bereits
## body_size und speed. Große Tiere haben mehr HP/Angriff/Verteidigung, schnelle Tiere mehr Tempo,
## und der Typ gibt einen kleinen Bonus (Raubtier: Angriff, Huftier: HP/Verteidigung, Nager/Insekt:
## Tempo, Wasser: HP, Gift: Angriff). Balancing an EINEM Ort: die Konstanten unten.
##
## Level-Formel wie bei Pokémon (vereinfacht): stat = 2·Basis·Level/100 + 5, HP zusätzlich +Level+10.

## Körpergröße (Kubikwurzel des Volumens in m): darauf wird 0..1 normiert.
const SIZE_MIN: float = 0.06   # Ameise
const SIZE_MAX: float = 1.0    # Bär / Giraffe

const BASE_HP_MIN: float = 35.0
const BASE_HP_SPAN: float = 65.0
const BASE_ATK_MIN: float = 35.0
const BASE_ATK_SPAN: float = 45.0
const BASE_DEF_MIN: float = 30.0
const BASE_DEF_SPAN: float = 40.0
const BASE_SPD_MIN: float = 25.0
const BASE_SPD_PER_SPEED: float = 9.0
const BASE_SPD_MAX: float = 110.0

## Typ-Boni auf die Basiswerte: {hp, atk, def, spd}.
const TYPE_BONUS: Dictionary = {
	PetBattleTypes.Type.PREDATOR: {"atk": 15.0},
	PetBattleTypes.Type.HOOFED:   {"hp": 10.0, "def": 12.0},
	PetBattleTypes.Type.RODENT:   {"spd": 10.0},
	PetBattleTypes.Type.INSECT:   {"spd": 15.0, "hp": -5.0},
	PetBattleTypes.Type.VENOM:    {"atk": 10.0},
	PetBattleTypes.Type.AQUA:     {"hp": 12.0},
}

## 0..1: wie groß ist das Tier (Kubikwurzel des Körpervolumens, auf SIZE_MIN..SIZE_MAX normiert).
static func size_score(body_size: Vector3) -> float:
	var volume: float = maxf(absf(body_size.x * body_size.y * body_size.z), 0.000001)
	var edge: float = pow(volume, 1.0 / 3.0)
	return clampf((edge - SIZE_MIN) / (SIZE_MAX - SIZE_MIN), 0.0, 1.0)

## Basiswerte {hp, atk, def, spd} (unabhängig vom Level).
static func base_stats(body_size: Vector3, speed: float, type_id: int) -> Dictionary:
	var s: float = size_score(body_size)
	var bonus: Dictionary = TYPE_BONUS.get(type_id, {}) as Dictionary
	return {
		"hp":  BASE_HP_MIN + BASE_HP_SPAN * s + float(bonus.get("hp", 0.0)),
		"atk": BASE_ATK_MIN + BASE_ATK_SPAN * s + float(bonus.get("atk", 0.0)),
		"def": BASE_DEF_MIN + BASE_DEF_SPAN * s + float(bonus.get("def", 0.0)),
		"spd": minf(BASE_SPD_MIN + BASE_SPD_PER_SPEED * maxf(speed, 0.0) + float(bonus.get("spd", 0.0)), BASE_SPD_MAX),
	}

## Kampfwerte auf einem Level (1..100): {max_hp, atk, def, spd} als int.
static func compute(body_size: Vector3, speed: float, type_id: int, level: int) -> Dictionary:
	var lv: int = clampi(level, 1, PetLeveling.MAX_LEVEL)
	var base: Dictionary = base_stats(body_size, speed, type_id)
	return {
		"max_hp": int(2.0 * float(base["hp"]) * float(lv) / 100.0) + lv + 10,
		"atk":    int(2.0 * float(base["atk"]) * float(lv) / 100.0) + 5,
		"def":    int(2.0 * float(base["def"]) * float(lv) / 100.0) + 5,
		"spd":    int(2.0 * float(base["spd"]) * float(lv) / 100.0) + 5,
	}
