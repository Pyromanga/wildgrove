class_name PetBattleMon
extends RefCounted

## PetBattleMon — ein Kämpfer (eigenes Pet oder Gegner) im Pet-Kampf: Werte, aktuelle HP,
## Statusveränderungen. Reine Datenklasse ohne Nodes → PetBattleEngine ist komplett ohne Engine
## testbar. Erzeugt über create() (Rohwerte, Tests) oder from_profile() (aus Art/Größe/Tempo).

const MAX_STAGE: int = 6

var key: String = ""          ## Eindeutiger Schlüssel im Kampf (UI-Zuordnung, Teilnehmer-Liste).
var display_name: String = ""
var species_id: String = ""
var type_id: int = PetBattleTypes.Type.NORMAL
var level: int = 1
var max_hp: int = 10
var hp: int = 10
var atk: int = 5
var def: int = 5
var spd: int = 5
var moves: Array[String] = []
var stages: Dictionary = {"atk": 0, "def": 0, "spd": 0}
var poisoned: bool = false
## instance_id des echten PetComponent (eigene Pets; 0 bei Gegnern) — damit der Controller nach
## dem Kampf XP an das richtige Pet vergeben kann.
var source_pet_id: int = 0
## Zeichnung im Kampf-Fenster (PetHeadIcon-Dictionary), bei Gegnern aus der Art-Tabelle.
var appearance: Dictionary = {}

static func create(p_name: String, p_type: int, p_level: int, p_stats: Dictionary, p_key: String = "") -> PetBattleMon:
	var m := PetBattleMon.new()
	m.display_name = p_name
	m.key = p_key if not p_key.is_empty() else p_name
	m.type_id = p_type
	m.level = clampi(p_level, 1, PetLeveling.MAX_LEVEL)
	m.max_hp = maxi(1, int(p_stats.get("max_hp", 10)))
	m.hp = m.max_hp
	m.atk = maxi(1, int(p_stats.get("atk", 5)))
	m.def = maxi(1, int(p_stats.get("def", 5)))
	m.spd = maxi(1, int(p_stats.get("spd", 5)))
	m.moves = PetBattleMoves.moves_for(p_type, m.level)
	return m

## Aus den Rohdaten eines Tiers (Art, Bauplan, Größe, Lauf-Tempo) — gleicher Weg für eigene Pets und
## Gegner, damit beide nach denselben Regeln gewertet werden.
static func from_profile(
	p_name: String, p_species_id: String, p_body_plan: int, p_body_size: Vector3, p_speed: float,
	p_level: int, p_key: String = ""
) -> PetBattleMon:
	var t: int = PetBattleTypes.type_for(p_species_id, p_body_plan)
	var m: PetBattleMon = create(p_name, t, p_level, PetBattleStats.compute(p_body_size, p_speed, t, p_level), p_key)
	m.species_id = p_species_id
	return m

func is_fainted() -> bool:
	return hp <= 0

func hp_fraction() -> float:
	return float(hp) / float(maxi(max_hp, 1))

func heal_full() -> void:
	hp = max_hp
	poisoned = false
	stages = {"atk": 0, "def": 0, "spd": 0}

## Faktor einer Statusstufe (−6..+6): (2+s)/2 bei Plus, 2/(2−s) bei Minus — wie bei Pokémon.
static func stage_multiplier(stage: int) -> float:
	var s: int = clampi(stage, -MAX_STAGE, MAX_STAGE)
	if s >= 0:
		return (2.0 + float(s)) / 2.0
	return 2.0 / (2.0 - float(s))

func effective(stat: String) -> float:
	var base: int = atk if stat == "atk" else (def if stat == "def" else spd)
	return float(base) * stage_multiplier(int(stages.get(stat, 0)))

## Verändert eine Statusstufe um `delta`. Rückgabe: die tatsächliche Änderung (0 bei Anschlag).
func change_stage(stat: String, delta: int) -> int:
	var before: int = int(stages.get(stat, 0))
	var after: int = clampi(before + delta, -MAX_STAGE, MAX_STAGE)
	stages[stat] = after
	return after - before

## Zieht Schaden ab (nie unter 0). Rückgabe: tatsächlich abgezogene HP.
func take_damage(amount: int) -> int:
	var dealt: int = clampi(amount, 0, hp)
	hp -= dealt
	return dealt
