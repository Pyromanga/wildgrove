# res://scripts/economy/equipment/StatModifierService.gd
extends Service
class_name StatModifierService

## StatModifierService — Akkumuliert Stat-Modifier und berechnet Effektivwerte.
##
## Löst A-07: Equipment-Boni, Buffs, Debuffs und Auren brauchen ein Fundament
## bevor das erste Equipment implementiert wird. Danach wäre die Migration teurer.
##
## DESIGN:
##   - Modifier werden per source_id verwaltet → jede Quelle hat genau einen Modifier
##     pro Stat (oder keinen). Equipment kann NICHT denselben source_id zweimal belegen.
##   - Expired-Cleanup: Diese Klasse hat KEIN eigenes on_tick(). Cleanup wird durch
##     CombatSystem.on_tick() via cleanup_all_expired() delegiert — für alle Player-IDs.
##     Wenn CombatSystem nicht aktiv ist (Tests ohne Combat), muss cleanup_all_expired()
##     manuell aufgerufen werden.
##   - get_effective_stat() ist O(n) in der Anzahl aktiver Modifier — bei typischen
##     Game-Szenarien (< 50 Modifier) vernachlässigbar.
##
## OPERATIONSREIHENFOLGE:
##   1. base_value
##   2. + sum(FLAT_ADD.value)
##   3. × (1.0 + sum(PERCENT_ADD.value))
##   4. × product(PERCENT_MULTIPLY.value)
##
## MULTI-TENANCY (ADR-029 Plan-Schritt 4, Round 69):
##   Intern: _players: { player_id (String): { source_id (String): StatModifier } }
##   Alle öffentlichen Methoden verlangen player_id: String als Pflichtparameter,
##   OHNE Default — identische Konvention zu InventorySystem/QuestService/
##   SkillSystem/EquipmentService (Round 63-66). Vorher war dies der letzte
##   verbliebene peer_id: int-Kernservice der ADR-029-Familie (siehe
##   TODO-offene-probleme.md, § Wichtig, "StatModifierService/WorldService auf
##   player_id migrieren") — jeder Aufrufer musste bis hierhin selbst zurück
##   nach peer_id übersetzen, genau das fragmentierte Ad-hoc-Muster, aus dem
##   R-7/R-8 (Round 49) entstanden war.
##
## VERWENDUNG:
##       StatModifier.permanent("equipment_sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
##   )
##
##   # Multiplayer:

const LOG_CAT := "StatModifiers"

## _players: { player_id (String): { source_id (String): StatModifier } }
## Initialisiert lazy in _player_dict().
var _players: Dictionary = {}

## Emittiert wenn ein Modifier hinzugefügt, entfernt oder durch Ablauf entfernt wurde.
## Listener (z.B. PlayerStats-UI, SkillSystem) können Werte neu berechnen.
signal modifier_changed(stat: String)

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func configure(_deps: ServiceDeps) -> void:
	AppLogger.log_debug("Konfiguriert.", LOG_CAT)

func on_ready() -> void:
	AppLogger.log_info("StatModifierService bereit (Multi-Tenant).", LOG_CAT)

func on_cleanup() -> void:
	_players.clear()
	AppLogger.log_info("StatModifierService cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Fügt einen Modifier hinzu oder überschreibt einen bestehenden mit derselben source_id.
## Gibt false zurück wenn source_id leer ist (Validierungsfehler).
func add_modifier(modifier: StatModifier, player_id: String) -> bool:
	if modifier.source_id.is_empty():
		AppLogger.log_error("add_modifier: source_id darf nicht leer sein!", LOG_CAT)
		return false
	if modifier.stat.is_empty():
		AppLogger.log_error("add_modifier: stat darf nicht leer sein!", LOG_CAT)
		return false

	var mods := _player_dict(player_id)
	var was_overwrite := mods.has(modifier.source_id)
	mods[modifier.source_id] = modifier

	AppLogger.log_debug(
		"%s %s (player %s)" % ["Überschrieben:" if was_overwrite else "Hinzugefügt:", modifier.to_debug_string(), player_id],
		LOG_CAT
	)
	modifier_changed.emit(modifier.stat)
	return true

## Entfernt einen Modifier anhand der source_id.
## Gibt false zurück wenn kein Modifier mit dieser ID gefunden wurde.
func remove_modifier(source_id: String, player_id: String) -> bool:
	var mods := _player_dict(player_id)
	if not mods.has(source_id):
		AppLogger.log_warn("remove_modifier('%s'): nicht gefunden (player %s)." % [source_id, player_id], LOG_CAT)
		return false

	var stat: String = (mods[source_id] as StatModifier).stat
	mods.erase(source_id)

	AppLogger.log_debug("Entfernt: '%s' (stat: %s, player %s)" % [source_id, stat, player_id], LOG_CAT)
	modifier_changed.emit(stat)
	return true

## Berechnet den effektiven Wert eines Stats mit allen aktiven Modifiern.
## base_value: der unmodifizierte Basiswert (z.B. aus PlayerStats oder ItemDefinition).
## stat: der Stat-Bezeichner (snake_case, z.B. "move_speed", "damage").
##
## Gibt base_value zurück wenn keine Modifier für diesen Stat registriert sind
## (das gilt auch für einen leeren player_id — bewusst kein Crash, siehe Aufrufer,
## die eine noch nicht auflösbare Identität als "kein Bonus" statt Fehler behandeln).
func get_effective_stat(stat: String, base_value: float, player_id: String) -> float:
	var mods := _player_dict(player_id)
	var flat_sum:      float = 0.0
	var percent_sum:   float = 0.0
	var multiply_prod: float = 1.0

	for source_id in mods:
		var mod: StatModifier = mods[source_id]
		if mod.stat != stat:
			continue
		if not mod.is_active():
			continue

		match mod.operation:
			StatModifier.Operation.FLAT_ADD:
				flat_sum += mod.value
			StatModifier.Operation.PERCENT_ADD:
				percent_sum += mod.value
			StatModifier.Operation.PERCENT_MULTIPLY:
				multiply_prod *= mod.value

	return (base_value + flat_sum) * (1.0 + percent_sum) * multiply_prod

## Gibt alle aktiven Modifier für einen bestimmten Stat zurück.
## Nützlich für UI (z.B. Tooltip mit Modifier-Aufschlüsselung).
func get_modifiers_for_stat(stat: String, player_id: String) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	var mods := _player_dict(player_id)
	for source_id in mods:
		var mod: StatModifier = mods[source_id]
		if mod.stat == stat and mod.is_active():
			result.append(mod)
	return result

## Gibt true zurück wenn ein Modifier mit dieser source_id aktiv ist.
func has_modifier(source_id: String, player_id: String) -> bool:
	var mods := _player_dict(player_id)
	return mods.has(source_id) and (mods[source_id] as StatModifier).is_active()

## Entfernt alle Modifier einer Quelle die mit einem Präfix beginnen.
## Nützlich wenn ein Item-Set mehrere Modifier mit demselben Präfix belegt hat
## z.B. remove_modifiers_with_prefix("equipment_") entfernt alle Equipment-Boni.
func remove_modifiers_with_prefix(prefix: String, player_id: String) -> int:
	var mods := _player_dict(player_id)
	var to_remove: Array[String] = []
	for source_id in mods:
		if source_id.begins_with(prefix):
			to_remove.append(source_id)

	var affected_stats: Array[String] = []
	for source_id in to_remove:
		var stat: String = (mods[source_id] as StatModifier).stat
		mods.erase(source_id)
		if not affected_stats.has(stat):
			affected_stats.append(stat)

	for stat in affected_stats:
		modifier_changed.emit(stat)

	if to_remove.size() > 0:
		AppLogger.log_debug(
			"Entfernt %d Modifier mit Präfix '%s' (player %s)." % [to_remove.size(), prefix, player_id],
			LOG_CAT
		)
	return to_remove.size()

## Entfernt alle abgelaufenen Modifier und emittiert modifier_changed für betroffene Stats.
## Wird vom ServiceTicker aufgerufen wenn ITickable implementiert ist.
## Kann auch manuell aufgerufen werden (z.B. in on_ready() nach einem Load).
func cleanup_expired(player_id: String) -> int:
	var mods := _player_dict(player_id)
	var to_remove: Array[String] = []
	var affected_stats: Array[String] = []

	for source_id in mods:
		var mod: StatModifier = mods[source_id]
		if not mod.is_active():
			to_remove.append(source_id)
			if not affected_stats.has(mod.stat):
				affected_stats.append(mod.stat)

	for source_id in to_remove:
		mods.erase(source_id)

	for stat in affected_stats:
		modifier_changed.emit(stat)

	if to_remove.size() > 0:
		AppLogger.log_debug("Expired Modifier entfernt: %d (player %s)." % [to_remove.size(), player_id], LOG_CAT)
	return to_remove.size()

## Bereinigt abgelaufene Modifier für ALLE bekannten Player-IDs.
## Wird von CombatSystem.on_tick() aufgerufen — verhindert Modifier-Leak
## in Multiplayer wo cleanup_expired(player_id) allein Spieler 2-N ignoriert hätte.
## Gibt Gesamtzahl entfernter Modifier zurück.
func cleanup_all_expired() -> int:
	var total := 0
	# _players.keys() kopieren — cleanup_expired() mutiert das Dictionary nicht direkt,
	# aber defensive Kopie verhindert Crashes bei zukünftigen Refactors.
	for pid in _players.keys().duplicate():
		total += cleanup_expired(pid)
	return total

## Räumt alle Modifier eines bestimmten Spielers — bei Session-Ende / Disconnect.
func clear_player(player_id: String) -> void:
	if not _players.has(player_id):
		return
	var mods: Dictionary = _players[player_id]
	var stats: Array[String] = []
	for source_id in mods:
		var s: String = (mods[source_id] as StatModifier).stat
		if not stats.has(s):
			stats.append(s)
	_players.erase(player_id)
	for stat in stats:
		modifier_changed.emit(stat)
	AppLogger.log_info("Alle Modifier für player %s entfernt." % player_id, LOG_CAT)

# ─────────────────────────────────────────────
# Debug-API
# ─────────────────────────────────────────────

## Gibt alle aktiven Modifier als lesbare Liste zurück. Für Terminal-Commands.
func get_debug_report(player_id: String) -> Array[String]:
	var result: Array[String] = []
	var mods := _player_dict(player_id)
	for source_id in mods:
		result.append((mods[source_id] as StatModifier).to_debug_string())
	return result

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

## Gibt das Modifier-Dictionary für player_id zurück, legt es bei Bedarf an.
func _player_dict(player_id: String) -> Dictionary:
	if not _players.has(player_id):
		_players[player_id] = {}
	return _players[player_id]
