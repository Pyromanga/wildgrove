class_name PetBattleEngine
extends RefCounted

## PetBattleEngine — rundenbasierte Kampflogik der Pet-Kämpfe (Pokémon-Prinzip). Reine Logik:
## keine Nodes, keine UI, keine Singletons. Alles Zufällige (Treffer, Kritische, Schaden, KI,
## Gleichstand beim Tempo) läuft über EINEN RandomNumberGenerator mit festem Seed → derselbe
## Seed + dieselben Eingaben = exakt derselbe Kampf (testbar, reproduzierbar).
##
## ABLAUF EINER RUNDE (use_move): der Spieler wählt eine Attacke, der Gegner wählt per KI. Wer das
## höhere Tempo hat (inkl. Statusstufen) greift zuerst an; ist das Ziel danach besiegt, entfällt der
## zweite Angriff. Am Rundenende tickt Gift. Danach: ist das aktive Gegner-Pet besiegt, kommt das
## nächste; sind alle besiegt → PLAYER_WON. Ist das aktive Spieler-Pet besiegt, muss der Spieler per
## switch_to() ein neues wählen (awaiting_switch) — oder verliert, wenn keins mehr übrig ist.
## Freiwilliges Wechseln (switch_to ohne awaiting_switch) kostet die Runde: der Gegner greift das
## neu eingewechselte Pet an.
##
## Nach dem Kampf wird nichts dauerhaft verändert: HP/Status gelten nur im Kampf (kein Permatod,
## kein Heilen nötig). XP/Belohnung vergibt der Controller (siehe PetBattleRewards).

enum Result { ONGOING, PLAYER_WON, ENEMY_WON, FORFEIT }

## Wie viele Pets der Spieler höchstens ins Kampfteam wählen darf (Wunsch "10 Pets").
const MAX_TEAM: int = 10

const CRIT_CHANCE: float = 1.0 / 16.0
const CRIT_MULT: float = 1.5
const STAB_MULT: float = 1.5
const RANDOM_MIN: float = 0.85
const POISON_FRACTION: float = 1.0 / 8.0
## Wahrscheinlichkeit, dass die Gegner-KI statt der besten eine zufällige Attacke wählt.
const AI_RANDOM_CHANCE: float = 0.25

const STAT_LABELS: Dictionary = {"atk": "Angriff", "def": "Verteidigung", "spd": "Tempo"}

var player_team: Array[PetBattleMon] = []
var enemy_team: Array[PetBattleMon] = []
var player_active: int = 0
var enemy_active: int = 0
var result: int = Result.ONGOING
## true = das aktive Spieler-Pet ist besiegt, der Spieler MUSS per switch_to() ersetzen.
var awaiting_switch: bool = false
var turn: int = 0

var _rng := RandomNumberGenerator.new()
var _log: Array[String] = []
## key → PetBattleMon der Spielerseite, die mindestens einmal gekämpft haben (für die XP-Verteilung).
var _participants: Dictionary = {}

func _init(p_player_team: Array[PetBattleMon], p_enemy_team: Array[PetBattleMon], seed_value: int = 0) -> void:
	_rng.seed = seed_value
	for m in p_player_team:
		if player_team.size() < MAX_TEAM:
			player_team.append(m)
	enemy_team = p_enemy_team.duplicate()
	if player_team.is_empty() or enemy_team.is_empty():
		result = Result.FORFEIT
		return
	player_active = maxi(_next_alive(player_team, -1), 0)
	enemy_active = maxi(_next_alive(enemy_team, -1), 0)
	_participants[player_team[player_active].key] = player_team[player_active]
	_say("Der Kampf beginnt! %s tritt gegen %s an." % [player_team[player_active].display_name, enemy_team[enemy_active].display_name])

# ─────────────────────────────────────────────
# Abfragen
# ─────────────────────────────────────────────

func active_player() -> PetBattleMon:
	return player_team[player_active]

func active_enemy() -> PetBattleMon:
	return enemy_team[enemy_active]

func is_over() -> bool:
	return result != Result.ONGOING

func needs_switch() -> bool:
	return awaiting_switch and not is_over()

## Indizes der noch kampffähigen Spieler-Pets (für die Wechsel-Liste).
func alive_player_indices() -> Array[int]:
	var out: Array[int] = []
	for i in range(player_team.size()):
		if not player_team[i].is_fainted():
			out.append(i)
	return out

func enemies_left() -> int:
	var n: int = 0
	for m in enemy_team:
		if not m.is_fainted():
			n += 1
	return n

func participants() -> Array[PetBattleMon]:
	var out: Array[PetBattleMon] = []
	for k in _participants:
		out.append(_participants[k] as PetBattleMon)
	return out

# ─────────────────────────────────────────────
# Aktionen des Spielers
# ─────────────────────────────────────────────

## Spielt eine Runde mit der Attacke an Position `move_index` des aktiven Pets. Rückgabe: die in
## dieser Runde neu entstandenen Log-Zeilen (leer, wenn die Aktion gerade nicht erlaubt ist).
func use_move(move_index: int) -> Array[String]:
	var start: int = _log.size()
	if is_over() or awaiting_switch:
		return []
	var me: PetBattleMon = active_player()
	if move_index < 0 or move_index >= me.moves.size():
		return []
	turn += 1
	var player_move: String = me.moves[move_index]
	var enemy_move: String = _choose_enemy_move()
	var p: PetBattleMon = me
	var e: PetBattleMon = active_enemy()
	if _player_acts_first(p, e):
		_act(p, e, player_move)
		if not p.is_fainted() and not e.is_fainted():
			_act(e, p, enemy_move)
	else:
		_act(e, p, enemy_move)
		if not p.is_fainted() and not e.is_fainted():
			_act(p, e, player_move)
	_end_of_turn(p, e)
	_after_turn()
	return _new_lines(start)

## Wechselt zum Pet an Position `index`. Nach einem Besiegen (awaiting_switch) ist das kostenlos;
## sonst kostet es die Runde und der Gegner greift das neue Pet an.
func switch_to(index: int) -> Array[String]:
	var start: int = _log.size()
	if is_over():
		return []
	if index < 0 or index >= player_team.size() or index == player_active:
		return []
	if player_team[index].is_fainted():
		return []
	var forced: bool = awaiting_switch
	var leaving: PetBattleMon = active_player()
	if not forced:
		turn += 1
		_say("%s, komm zurück!" % leaving.display_name)
	leaving.stages = {"atk": 0, "def": 0, "spd": 0}
	player_active = index
	var entering: PetBattleMon = active_player()
	_participants[entering.key] = entering
	_say("%s, los!" % entering.display_name)
	if forced:
		awaiting_switch = false
	else:
		var e: PetBattleMon = active_enemy()
		_act(e, entering, _choose_enemy_move())
		_end_of_turn(entering, e)
		_after_turn()
	return _new_lines(start)

## Spieler gibt auf — zählt als Niederlage ohne Belohnung.
func forfeit() -> Array[String]:
	var start: int = _log.size()
	if is_over():
		return []
	result = Result.FORFEIT
	awaiting_switch = false
	_say("Du gibst auf.")
	return _new_lines(start)

func get_log() -> Array[String]:
	return _log

# ─────────────────────────────────────────────
# Schadensrechnung (statisch → direkt testbar)
# ─────────────────────────────────────────────

## Erwarteter Schaden OHNE Zufall (kein Kritischer, mittlerer Streufaktor). Für Gegner-KI + Tests.
static func expected_damage(attacker: PetBattleMon, defender: PetBattleMon, move: Dictionary) -> float:
	var power: float = float(move.get("power", 0))
	if power <= 0.0:
		return 0.0
	var raw: float = ((2.0 * float(attacker.level) / 5.0 + 2.0) * power * attacker.effective("atk") / maxf(defender.effective("def"), 1.0)) / 50.0 + 2.0
	var mtype: int = int(move.get("type", PetBattleTypes.Type.NORMAL))
	var stab: float = STAB_MULT if mtype == attacker.type_id and mtype != PetBattleTypes.Type.NORMAL else 1.0
	var eff: float = PetBattleTypes.effectiveness(mtype, defender.type_id)
	return raw * stab * eff * ((RANDOM_MIN + 1.0) * 0.5)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _say(line: String) -> void:
	_log.append(line)

func _new_lines(start: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(start, _log.size()):
		out.append(_log[i])
	return out

func _next_alive(team: Array[PetBattleMon], after: int) -> int:
	for i in range(after + 1, team.size()):
		if not team[i].is_fainted():
			return i
	return -1

func _player_acts_first(p: PetBattleMon, e: PetBattleMon) -> bool:
	var sp: float = p.effective("spd")
	var se: float = e.effective("spd")
	if is_equal_approx(sp, se):
		return _rng.randf() < 0.5
	return sp > se

func _act(attacker: PetBattleMon, defender: PetBattleMon, move_id: String) -> void:
	var move: Dictionary = PetBattleMoves.get_move(move_id)
	if move.is_empty():
		return
	_say("%s setzt %s ein!" % [attacker.display_name, PetBattleMoves.name_of(move_id)])
	if _rng.randf() * 100.0 >= float(move.get("accuracy", 100)):
		_say("Die Attacke verfehlt!")
		return
	if not PetBattleMoves.is_attack(move):
		_apply_status_move(attacker, defender, move)
		return
	var raw: float = expected_damage(attacker, defender, move) / ((RANDOM_MIN + 1.0) * 0.5)
	var mtype: int = int(move.get("type", PetBattleTypes.Type.NORMAL))
	var eff: float = PetBattleTypes.effectiveness(mtype, defender.type_id)
	var crit: bool = _rng.randf() < CRIT_CHANCE
	var rolled: float = raw * _rng.randf_range(RANDOM_MIN, 1.0) * (CRIT_MULT if crit else 1.0)
	var damage: int = int(rolled)
	if eff > 0.0:
		damage = maxi(damage, 1)
	var dealt: int = defender.take_damage(damage)
	if crit:
		_say("Ein Volltreffer!")
	if eff > 1.0:
		_say("Das ist sehr effektiv!")
	elif eff < 1.0:
		_say("Das ist nicht sehr effektiv …")
	_say("%s verliert %d LP." % [defender.display_name, dealt])
	if defender.is_fainted():
		_say("%s ist besiegt!" % defender.display_name)
		return
	var poison_chance: float = float(move.get("poison", 0.0))
	if poison_chance > 0.0 and not defender.poisoned and _rng.randf() < poison_chance:
		defender.poisoned = true
		_say("%s wurde vergiftet!" % defender.display_name)

func _apply_status_move(attacker: PetBattleMon, defender: PetBattleMon, move: Dictionary) -> void:
	var target: PetBattleMon = attacker if String(move.get("target", "self")) == "self" else defender
	var stat: String = String(move.get("stat", "atk"))
	var changed: int = target.change_stage(stat, int(move.get("stages", 0)))
	var label: String = String(STAT_LABELS.get(stat, stat))
	if changed > 0:
		_say("%s: %s steigt!" % [target.display_name, label])
	elif changed < 0:
		_say("%s: %s sinkt!" % [target.display_name, label])
	else:
		_say("Es passiert nichts.")

func _end_of_turn(p: PetBattleMon, e: PetBattleMon) -> void:
	for mon in [p, e]:
		var m: PetBattleMon = mon as PetBattleMon
		if m.is_fainted() or not m.poisoned:
			continue
		var tick: int = maxi(1, int(float(m.max_hp) * POISON_FRACTION))
		m.take_damage(tick)
		_say("%s leidet unter Gift (-%d LP)." % [m.display_name, tick])
		if m.is_fainted():
			_say("%s ist besiegt!" % m.display_name)

## Nach einer Runde: Gegner nachrücken lassen, Sieg/Niederlage prüfen, Spieler ggf. zum Wechseln auffordern.
func _after_turn() -> void:
	var enemy_out: bool = _next_alive(enemy_team, -1) == -1
	var player_out: bool = _next_alive(player_team, -1) == -1
	if enemy_out:
		result = Result.PLAYER_WON
		_say("Du hast gewonnen!")
		return
	if player_out:
		result = Result.ENEMY_WON
		_say("Du hast verloren …")
		return
	if active_enemy().is_fainted():
		enemy_active = _next_alive(enemy_team, -1)
		_say("Der Gegner schickt %s in den Kampf!" % active_enemy().display_name)
	if active_player().is_fainted():
		awaiting_switch = true
		_say("Wähle dein nächstes Pet!")

## Gegner-KI: meist die Attacke mit dem höchsten erwarteten Schaden (Kill-Bonus), manchmal eine
## sinnvolle Hilfsattacke, in AI_RANDOM_CHANCE der Fälle eine zufällige.
func _choose_enemy_move() -> String:
	var e: PetBattleMon = active_enemy()
	var p: PetBattleMon = active_player()
	if e.moves.is_empty():
		return "rempler"
	if _rng.randf() < AI_RANDOM_CHANCE:
		return e.moves[_rng.randi_range(0, e.moves.size() - 1)]
	var best_id: String = e.moves[0]
	var best_score: float = -1.0
	for id in e.moves:
		var move: Dictionary = PetBattleMoves.get_move(id)
		var score: float = 0.0
		if PetBattleMoves.is_attack(move):
			score = expected_damage(e, p, move) * float(move.get("accuracy", 100)) / 100.0
			if score >= float(p.hp):
				score *= 1.5
		else:
			score = _status_score(e, p, move)
		if score > best_score:
			best_score = score
			best_id = id
	return best_id

func _status_score(user: PetBattleMon, target: PetBattleMon, move: Dictionary) -> float:
	var stat: String = String(move.get("stat", "atk"))
	if String(move.get("target", "self")) == "self":
		var stage: int = int(user.stages.get(stat, 0))
		if stage >= 2 or user.hp_fraction() < 0.4:
			return 0.0
		return 14.0 - 4.0 * float(stage)
	var their: int = int(target.stages.get(stat, 0))
	return 12.0 if their > -2 else 0.0
