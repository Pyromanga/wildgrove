# res://scripts/economy/equipment/StatModifier.gd
class_name StatModifier extends RefCounted

## StatModifier — Typisierter Daten-Container für einen einzelnen Stat-Modifikator.
##
## Repräsentiert einen einzelnen Einfluss auf einen Basiswert.
## StatModifierService akkumuliert mehrere Modifier und berechnet den Effektivwert.
##
## VERWENDUNG:
##   var mod := StatModifier.new()
##   mod.source_id   = "equipment_iron_sword"
##   mod.stat        = "damage"
##   mod.operation   = StatModifier.Operation.FLAT_ADD
##   mod.value       = 5.0
##   mod.expires_at  = -1.0  # permanent
##
## OPERATIONSREIHENFOLGE (wenn mehrere Modifier auf denselben Stat):
##   1. Alle FLAT_ADD addieren   → base + sum(flat_add)
##   2. Alle PERCENT_ADD addieren → × (1 + sum(percent_add))
##   3. Alle PERCENT_MULTIPLY sequenziell anwenden → × each(percent_multiply)
##
##   Beispiel: base=100, FLAT_ADD +20, PERCENT_ADD +0.15, PERCENT_MULTIPLY ×0.8
##   → (100 + 20) × (1 + 0.15) × 0.8 = 110.4

enum Operation {
	## Fügt einen festen Betrag hinzu. Typisch für Equipment-Boni.
	## Beispiel: +5 Schaden durch Schwert.
	FLAT_ADD,

	## Fügt einen prozentualen Bonus hinzu (summiert mit anderen PERCENT_ADD).
	## Beispiel: +15% Schaden durch Fähigkeit. Mehrere PERCENT_ADD addieren sich.
	PERCENT_ADD,

	## Multipliziert den bisherigen Wert (sequenziell angewendet).
	## Typisch für Debuffs/Auren die sich nicht einfach addieren sollen.
	## Beispiel: ×0.5 Schaden durch Slow-Debuff.
	PERCENT_MULTIPLY,
}

## Eindeutiger Bezeichner der Quelle. Wird für remove_modifier() genutzt.
## Konvention: "<kategorie>_<bezeichner>" z.B. "equipment_iron_sword", "buff_haste_01"
## Bei Items mit mehreren Slots: "<slot>_<item_id>" z.B. "ring_left_speed_ring"
var source_id: String = ""

## Der Stat-Bezeichner. Konvention: snake_case, z.B. "move_speed", "damage", "max_health"
## Muss übereinstimmen mit dem stat-Parameter in StatModifierService.get_effective_stat().
var stat: String = ""

## Wie der Modifikator angewendet wird.
var operation: Operation = Operation.FLAT_ADD

## Der Wert des Modifikators.
## Bei FLAT_ADD: absoluter Betrag (z.B. 5.0)
## Bei PERCENT_ADD / PERCENT_MULTIPLY: Faktor (z.B. 0.15 für +15%, 0.5 für ×0.5)
var value: float = 0.0

## Ablaufzeitpunkt in Sekunden (Time.get_ticks_msec() / 1000.0).
## -1.0 = permanent (kein Ablauf).
## Für temporäre Buffs/Debuffs: Time.get_ticks_msec() / 1000.0 + duration_seconds
var expires_at: float = -1.0

## Hilfsmethode: Ist dieser Modifier noch aktiv?
func is_active() -> bool:
	if expires_at < 0.0:
		return true
	return Time.get_ticks_msec() / 1000.0 < expires_at

## Hilfsmethode: Erstellt einen permanenten Modifier in einer Zeile.
static func permanent(source: String, stat_name: String, op: Operation, val: float) -> StatModifier:
	var m := StatModifier.new()
	m.source_id  = source
	m.stat       = stat_name
	m.operation  = op
	m.value      = val
	m.expires_at = -1.0
	return m

## Hilfsmethode: Erstellt einen temporären Modifier mit Ablaufzeit.
static func temporary(source: String, stat_name: String, op: Operation, val: float, duration_sec: float) -> StatModifier:
	var m := StatModifier.new()
	m.source_id  = source
	m.stat       = stat_name
	m.operation  = op
	m.value      = val
	m.expires_at = Time.get_ticks_msec() / 1000.0 + duration_sec
	return m

## Lesbare Darstellung für Debugging.
func to_debug_string() -> String:
	var op_names := ["FLAT_ADD", "PERCENT_ADD", "PERCENT_MULTIPLY"]
	var expire_str := "permanent" if expires_at < 0.0 else ("%.1fs" % expires_at)
	return "[%s] %s %s %+.2f (%s)" % [source_id, stat, op_names[operation], value, expire_str]
