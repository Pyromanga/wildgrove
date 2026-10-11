class_name PetBattleEncounter
extends RefCounted

## PetBattleEncounter — Gegner-Teams und Belohnungen der Pet-Kämpfe gegen Dorfbewohner. Reine Logik
## (statisch, deterministisch aus einem Seed, keine Nodes) → ohne Engine testbar.
##
## GEGNER: jeder Dorfbewohner hat ein Team aus 1–3 Tieren. Welche, bestimmt der Seed (aus Name/Position
## des Dorfbewohners + Kampf-Runde, siehe VillagerNPC) → auf jedem Peer gleich, ohne etwas zu
## übertragen. Die Level orientieren sich am Durchschnitts-Level des eigenen Kampfteams, damit
## Kämpfe in jeder Spielphase machbar bleiben. Berufe bevorzugen einen Typ (Bauer: Huftiere,
## Wasserträger: Wasser) für etwas Charakter.
##
## BELOHNUNG bei Sieg: ein Pet des Gegners (das stärkste Tier seines Teams, auf dessen Level),
## XP für alle Teilnehmer (Verlierer bekommen etwas Trost-XP) und etwas Gold.

const MIN_TEAM: int = 1
const MAX_TEAM: int = 3
## Wie stark ein Berufs-Typ bevorzugt wird (Wahrscheinlichkeit je Gegner).
const TYPE_BIAS_CHANCE: float = 0.6
## Level-Streuung um das Durchschnitts-Level des Spielerteams: avg + (-2 .. +1).
const LEVEL_SPREAD_LOW: int = -2
const LEVEL_SPREAD_HIGH: int = 1

const XP_PER_ENEMY_LEVEL: int = 8
const XP_LOSS_DIVISOR: int = 4
const GOLD_PER_ENEMY_LEVEL: int = 6

## Gegner-Team: Array von {"species_id": String, "level": int}.
## bias_type: PetBattleTypes.Type oder -1 (kein Berufs-Typ).
static func generate_enemy_team(seed_value: int, avg_level: int, bias_type: int = -1) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var all_ids: Array[String] = PetBattleSpecies.all_ids()
	var biased: Array[String] = []
	if bias_type >= 0:
		for id in all_ids:
			if _type_of(id) == bias_type:
				biased.append(id)
	var size: int = rng.randi_range(MIN_TEAM, MAX_TEAM)
	var team: Array[Dictionary] = []
	for i in range(size):
		var pool: Array[String] = all_ids
		if not biased.is_empty() and rng.randf() < TYPE_BIAS_CHANCE:
			pool = biased
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var level: int = clampi(avg_level + rng.randi_range(LEVEL_SPREAD_LOW, LEVEL_SPREAD_HIGH), 1, PetLeveling.MAX_LEVEL)
		team.append({"species_id": id, "level": level})
	return team

static func _type_of(species_id: String) -> int:
	var p: Dictionary = PetBattleSpecies.profile(species_id)
	if p.is_empty():
		return PetBattleTypes.Type.NORMAL
	return PetBattleTypes.type_for(species_id, int(p["body_plan"]))

## Kampf-Kämpfer eines Gegner-Eintrags ({"species_id", "level"}). null bei unbekannter Art.
static func mon_for_enemy(entry: Dictionary, index: int) -> PetBattleMon:
	var p: Dictionary = PetBattleSpecies.profile(String(entry.get("species_id", "")))
	if p.is_empty():
		return null
	var mon: PetBattleMon = PetBattleMon.from_profile(
		String(p["display_name"]), String(p["species_id"]), int(p["body_plan"]),
		p["body_size"] as Vector3, float(p["speed"]), int(entry.get("level", 1)), "enemy_%d" % index
	)
	mon.appearance = p["appearance"] as Dictionary
	return mon

static func mons_for_enemy_team(team: Array[Dictionary]) -> Array[PetBattleMon]:
	var out: Array[PetBattleMon] = []
	for i in range(team.size()):
		var mon: PetBattleMon = mon_for_enemy(team[i], i)
		if mon != null:
			out.append(mon)
	return out

## Seed für einen Dorfbewohner: stabil pro Dorfbewohner + Kampf-Runde (nach jedem Sieg neues Team).
static func seed_for(villager_key: String, round_index: int) -> int:
	return absi(hash("%s|%d" % [villager_key, round_index]))

# ─────────────────────────────────────────────
# Belohnungen
# ─────────────────────────────────────────────

## XP je beteiligtem Pet. Sieger: Summe der Gegner-Level × XP_PER_ENEMY_LEVEL; Verlierer ein Viertel.
static func xp_for_participant(enemy_levels: Array[int], won: bool) -> int:
	var total: int = 0
	for lv in enemy_levels:
		total += lv * XP_PER_ENEMY_LEVEL
	return total if won else maxi(1, int(float(total) / float(XP_LOSS_DIVISOR)))

static func gold_for_win(enemy_levels: Array[int]) -> int:
	var total: int = 0
	for lv in enemy_levels:
		total += lv * GOLD_PER_ENEMY_LEVEL
	return total

## Das Beute-Pet: der höchstlevelige Gegner (bei Gleichstand der zuletzt aufgeführte).
## Rückgabe: {"species_id", "level"} oder {} bei leerem Team.
static func pick_reward(team: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for entry in team:
		if best.is_empty() or int(entry["level"]) >= int(best["level"]):
			best = entry
	return best

## Config für PetComponent.on_spawn() eines Belohnungs-Pets (gleiche Felder wie AnimalCatcher.catch_animal()).
## Das Pet startet mit genau der XP seines Levels (Level 5 → XP-Schwelle von Level 5).
static func reward_pet_config(reward: Dictionary, owner_peer_id: int, owner_player_id: String) -> Dictionary:
	var p: Dictionary = PetBattleSpecies.profile(String(reward.get("species_id", "")))
	if p.is_empty():
		return {}
	var config: Dictionary = (p["appearance"] as Dictionary).duplicate()
	config["name"] = "Zahmes " + String(p["display_name"])
	# Wie beim Fangen etwas langsamer als das wilde Tier (AnimalCatcher: speed × 0,85).
	config["speed"] = float(p["speed"]) * 0.85
	config["species_id"] = String(p["catch_name"])
	config["owner_peer_id"] = owner_peer_id
	config["owner_player_id"] = owner_player_id
	config["abilities"] = PetAbilities.default_for_species(String(p["catch_name"]))
	config["xp"] = PetLeveling.xp_required_for_level(int(reward.get("level", 1)))
	return config
