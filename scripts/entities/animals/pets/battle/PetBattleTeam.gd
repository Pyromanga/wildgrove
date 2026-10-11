class_name PetBattleTeam
extends RefCounted

## PetBattleTeam — Kampfteam-Auswahl (höchstens PetBattleEngine.MAX_TEAM = 10 Pets) und der Weg von
## echten PetComponent-Nodes zu PetBattleMon-Kämpfern. Statisch, ohne eigenen Zustand — die "Wahrheit"
## über die Teamzugehörigkeit liegt im Pet selbst (PetComponent.is_in_battle_team(), im Save).

## Pets des Kampfteams (in Eingabe-Reihenfolge), höchstens MAX_TEAM.
static func team_of(pets: Array) -> Array[PetComponent]:
	var out: Array[PetComponent] = []
	for p in pets:
		var pet: PetComponent = p as PetComponent
		if pet == null or not is_instance_valid(pet) or pet.is_queued_for_deletion():
			continue
		if pet.is_in_battle_team() and out.size() < PetBattleEngine.MAX_TEAM:
			out.append(pet)
	return out

## Darf noch ein weiteres Pet ins Team (Obergrenze noch nicht erreicht)?
static func can_add(pets: Array) -> bool:
	return team_of(pets).size() < PetBattleEngine.MAX_TEAM

## Kämpfer für die Engine aus echten Pets. Schlüssel "pet_<instance_id>" — damit der Controller nach dem
## Kampf XP an das richtige Pet vergibt (source_pet_id).
static func mons_for(pets: Array[PetComponent]) -> Array[PetBattleMon]:
	var out: Array[PetBattleMon] = []
	for pet in pets:
		var data: Dictionary = pet.get_battle_profile()
		var mon: PetBattleMon = PetBattleMon.from_profile(
			String(data["name"]), String(data["species_id"]), int(data["body_plan"]),
			data["body_size"] as Vector3, float(data["speed"]), int(data["level"]),
			"pet_%d" % pet.get_instance_id()
		)
		mon.source_pet_id = pet.get_instance_id()
		mon.appearance = pet.get_appearance()
		out.append(mon)
	return out

## Durchschnitts-Level (abgerundet, mindestens 1) — Maßstab für die Gegner-Level.
static func average_level(mons: Array[PetBattleMon]) -> int:
	if mons.is_empty():
		return 1
	var total: int = 0
	for m in mons:
		total += m.level
	return maxi(1, int(float(total) / float(mons.size())))
