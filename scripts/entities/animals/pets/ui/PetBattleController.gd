class_name PetBattleController
extends Node

## PetBattleController — verbindet das Kampf-Fenster (PetBattleVisuals) mit der Kampflogik
## (PetBattleEngine) und den echten Pets/Belohnungen.
##
## ABLAUF
##   1. Ein Dorfbewohner wird herausgefordert (VillagerNPC → UIEvents.pet_battle_requested).
##   2. TEAMWAHL: alle eigenen Pets (WorldService.get_pets_for_peer) werden aufgelistet; der Haken setzt
##      PetComponent.set_battle_team() (im Save), höchstens PetBattleEngine.MAX_TEAM = 10.
##   3. START: Kämpfer aus dem Team (PetBattleTeam.mons_for), Gegner-Team aus dem Seed des Dorfbewohners
##      und dem Durchschnitts-Level des Teams (PetBattleEncounter). Rundenweise über die Engine.
##   4. ENDE: XP für alle Teilnehmer, bei Sieg zusätzlich Gold + ein Pet des Gegners (siehe
##      PetBattleEncounter), dann pet_battle_finished → der Dorfbewohner ruht sich aus und stellt beim
##      nächsten Mal ein neues Team auf.
##
## Der Controller besitzt den Kampfzustand (die Engine) — Visuals zeichnen nur. Läuft nur auf dem Peer,
## der die Herausforderung ausgelöst hat; Pets sind client-autoritativ, Belohnungs-Pets werden lokal
## gespawnt und über den normalen Pet-Spawn-Weg an andere Peers gemeldet (siehe WorldService).
## Schließen des Fensters mitten im Kampf zählt als Aufgeben (keine Belohnung, kein Zustandsrest).

const LOG_CAT := "PetBattle"

var _visuals: PetBattleVisuals
var _ctx: IUIContext
var _engine: PetBattleEngine = null
var _pets: Array[PetComponent] = []

var _villager_key: String = ""
var _villager_name: String = ""
var _enemy_seed: int = 0
var _bias_type: int = -1
var _enemy_entries: Array[Dictionary] = []

func setup(visuals: PetBattleVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.team_toggled.connect(_on_team_toggled)
	_visuals.start_pressed.connect(_on_start_pressed)
	_visuals.move_pressed.connect(_on_move_pressed)
	_visuals.switch_chosen.connect(_on_switch_chosen)
	_visuals.forfeit_pressed.connect(_on_forfeit_pressed)
	_visuals.close_requested.connect(_on_close_requested)
	_visuals.panel.visibility_changed.connect(_on_visibility_changed)
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		_ctx.bus().ui().pet_battle_requested.connect(_on_battle_requested)

# ─────────────────────────────────────────────
# Herausforderung + Teamwahl
# ─────────────────────────────────────────────

func _on_battle_requested(villager_key: String, villager_name: String, enemy_seed: int, bias_type: int) -> void:
	if _engine != null and not _engine.is_over():
		return  # es läuft schon ein Kampf
	_villager_key = villager_key
	_villager_name = villager_name
	_enemy_seed = enemy_seed
	_bias_type = bias_type
	_engine = null
	_pets = _collect_pets()
	if _pets.is_empty():
		_toast("Du hast noch kein Pet. Fange erst ein Tier!")
		return
	# Gibt es noch kein Team, nimm automatisch bis zu 3 Pets — der Spieler kann sofort starten.
	if PetBattleTeam.team_of(_pets).is_empty():
		for i in range(mini(3, _pets.size())):
			_pets[i].set_battle_team(true)
	_open_team_select()

func _collect_pets() -> Array[PetComponent]:
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if not is_instance_valid(world):
		return []
	var out: Array[PetComponent] = []
	for pet in world.get_pets_for_peer(_ctx.get_local_peer_id()):
		if is_instance_valid(pet) and not pet.is_queued_for_deletion():
			out.append(pet)
	return out

func _open_team_select() -> void:
	var rows: Array[Dictionary] = []
	for pet in _pets:
		var data: Dictionary = pet.get_battle_profile()
		rows.append({
			"id": pet.get_instance_id(),
			"name": String(data["name"]),
			"level": int(data["level"]),
			"type_id": PetBattleTypes.type_for(String(data["species_id"]), int(data["body_plan"])),
			"appearance": pet.get_appearance(),
			"selected": pet.is_in_battle_team(),
		})
	_visuals.open_team_select(
		"Gegen %s antreten — wähle bis zu %d Pets für dein Kampfteam." % [_villager_name, PetBattleEngine.MAX_TEAM],
		rows, PetBattleEngine.MAX_TEAM
	)

func _on_team_toggled(pet_id: int, selected: bool) -> void:
	var pet: PetComponent = _pet_by_id(pet_id)
	if pet == null:
		return
	if selected and not PetBattleTeam.can_add(_pets) and not pet.is_in_battle_team():
		_visuals.set_team_check(pet_id, false)
		_toast("Dein Kampfteam ist voll (%d Pets)." % PetBattleEngine.MAX_TEAM)
		return
	pet.set_battle_team(selected)
	_visuals.set_team_count(PetBattleTeam.team_of(_pets).size(), PetBattleEngine.MAX_TEAM)

func _pet_by_id(pet_id: int) -> PetComponent:
	for pet in _pets:
		if is_instance_valid(pet) and pet.get_instance_id() == pet_id:
			return pet
	return null

# ─────────────────────────────────────────────
# Kampf
# ─────────────────────────────────────────────

func _on_start_pressed() -> void:
	var team: Array[PetComponent] = PetBattleTeam.team_of(_pets)
	if team.is_empty():
		return
	var player_mons: Array[PetBattleMon] = PetBattleTeam.mons_for(team)
	var avg: int = PetBattleTeam.average_level(player_mons)
	_enemy_entries = PetBattleEncounter.generate_enemy_team(_enemy_seed, avg, _bias_type)
	var enemy_mons: Array[PetBattleMon] = PetBattleEncounter.mons_for_enemy_team(_enemy_entries)
	if enemy_mons.is_empty():
		_toast("%s hat gerade keine Tiere dabei." % _villager_name)
		return
	_engine = PetBattleEngine.new(player_mons, enemy_mons, _enemy_seed + 17)
	_visuals.show_battle(_engine, _villager_name)

func _on_move_pressed(index: int) -> void:
	if _engine == null:
		return
	_apply(_engine.use_move(index))

func _on_switch_chosen(index: int) -> void:
	if _engine == null:
		return
	_apply(_engine.switch_to(index))

func _on_forfeit_pressed() -> void:
	if _engine == null:
		return
	_apply(_engine.forfeit())

## Zeichnet nach einer Aktion neu und beendet den Kampf, falls er vorbei ist.
func _apply(new_lines: Array[String]) -> void:
	_visuals.refresh_battle(_engine, new_lines)
	if _engine.is_over():
		_finish()

func _finish() -> void:
	var engine: PetBattleEngine = _engine
	_engine = null
	var won: bool = engine.result == PetBattleEngine.Result.PLAYER_WON
	var enemy_levels: Array[int] = []
	for entry in _enemy_entries:
		enemy_levels.append(int(entry["level"]))

	var lines: Array[String] = []
	var xp: int = PetBattleEncounter.xp_for_participant(enemy_levels, won)
	var rewarded: int = 0
	for mon in engine.participants():
		var pet: PetComponent = instance_from_id(mon.source_pet_id) as PetComponent
		if is_instance_valid(pet):
			pet.add_xp(xp)
			rewarded += 1
	if rewarded > 0:
		lines.append("Jedes beteiligte Pet bekommt %d XP." % xp)

	if won:
		lines.append_array(_grant_win_rewards(enemy_levels))
	_ctx.bus().ui().emit_pet_battle_finished(_villager_key, won)
	var title: String = "🏆 Sieg!" if won else ("🏳 Aufgegeben" if engine.result == PetBattleEngine.Result.FORFEIT else "💥 Niederlage")
	if not won:
		lines.append("%s wartet auf eine Revanche." % _villager_name)
	_visuals.show_result(title, lines)

## Gold + Beute-Pet bei Sieg. Rückgabe: Belohnungszeilen fürs Ergebnis.
func _grant_win_rewards(enemy_levels: Array[int]) -> Array[String]:
	var lines: Array[String] = []
	var gold: int = PetBattleEncounter.gold_for_win(enemy_levels)
	var currency: CurrencyService = _ctx.get_currency()
	if gold > 0 and is_instance_valid(currency) and currency.request_add_gold(_ctx.get_local_player_id(), gold):
		lines.append("+%d Gold" % gold)

	var reward: Dictionary = PetBattleEncounter.pick_reward(_enemy_entries)
	var config: Dictionary = PetBattleEncounter.reward_pet_config(reward, _ctx.get_local_peer_id(), _ctx.get_local_player_id())
	var world: WorldService = _ctx.get_world()
	if config.is_empty() or not is_instance_valid(world):
		return lines
	var player: Node3D = _ctx.get_local_player()
	var pos: Vector3 = player.global_position + Vector3(1.2, 0.0, 1.2) if is_instance_valid(player) else Vector3.ZERO
	var pet: PetComponent = world.spawn_entity("pet", pos, config, _ctx.get_local_peer_id()) as PetComponent
	if is_instance_valid(pet):
		lines.append("Neues Pet: %s (Level %d)!" % [String(config["name"]), int(reward["level"])])
		AppLogger.log_info("Pet-Kampf gewonnen gegen '%s' → Beute-Pet '%s'." % [_villager_name, String(config["name"])], LOG_CAT)
	else:
		AppLogger.log_error("Beute-Pet konnte nicht gespawnt werden (spawn_entity('pet') fehlgeschlagen).", LOG_CAT)
	return lines

# ─────────────────────────────────────────────
# Schließen
# ─────────────────────────────────────────────

func _on_close_requested() -> void:
	_visuals.close()

## Fenster zu (✕, anderes Fenster geöffnet …) mitten im Kampf → gilt als Aufgeben, ohne Belohnung.
func _on_visibility_changed() -> void:
	if _visuals.panel.visible or _engine == null:
		return
	if not _engine.is_over():
		_engine.forfeit()
		_ctx.bus().ui().emit_pet_battle_finished(_villager_key, false)
	_engine = null

func _toast(text: String) -> void:
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		_ctx.bus().world().emit_interaction_reward_text(text)
