# res://scripts/entities/combat/StatusEffect.gd
class_name StatusEffect extends RefCounted

## StatusEffect — Datencontainer für einen aktiven, periodisch tickenden Status-Effekt
## (Gift, Brand, …). TD-12, siehe ADR-008 "Bekannter Tech Debt".
##
## DESIGN: Folgt demselben Muster wie StatModifier.gd / StatModifierService.gd —
## ein RefCounted-Datencontainer, verwaltet in einer Dictionary keyed by einer
## eindeutigen ID, Ablauf/Tick via ServiceTicker.on_tick() statt eigenem Timer-Node.
## Siehe CombatSystem._active_effects / CombatSystem.on_tick().
##
## DAMAGE TYPE: Status-Effekte nutzen IMMER DamageType.TRUE — siehe DamageRecord.gd
## Kommentar: "TRUE ignoriert alle Resistenzen (Gifttränke, Sturz, Reflect)". Ein
## Gift- oder Brand-Tick wird bewusst NICHT durch Rüstung/Magieresistenz reduziert.
##
## KEIN STACKING: Ein erneuter apply_poison()/apply_burn()-Aufruf mit identischer
## source_id/target_id-Kombination überschreibt den bestehenden Effekt (Reset von
## Dauer + Schaden) statt einen zweiten parallelen Tick zu erzeugen — dieselbe
## Konvention wie StatModifierService.add_modifier() für eine source_id.

enum Kind {
	POISON,
	BURN,
}

## Eindeutiger Schlüssel: "<kind>:<source_id>:<target_id>". Wird von CombatSystem
## als Dictionary-Key genutzt — siehe make().
var effect_key: String = ""

var kind: Kind = Kind.POISON

## UUID der Quelle (Angreifer, Item, Falle, …). Leer = Umweltschaden ohne Quelle.
var source_id: String = ""

## UUID des Ziels — nur für Logging/DamageRecord, NICHT für den Tick-Lookup
## (der läuft über health_component, siehe unten).
var target_id: String = ""

## Direkte Referenz auf das Ziel-HealthComponent. Bewusst keine UUID→Node-Lookup-
## Schicht (die existiert im Projekt nicht) — der Aufrufer von apply_poison()/
## apply_burn() hat die Referenz ohnehin schon (genau wie bei apply_damage()).
var health_component: HealthComponent = null

var damage_per_tick: float = 0.0
var tick_interval: float = 1.0
var ticks_remaining: int = 0

## Echte peer_id des Spielers, dessen Waffentreffer diesen Effekt ausgelöst hat,
## oder -1 wenn kein Spieler-Angreifer bekannt ist (ADR-019). Reist über
## CombatSystem.on_tick() in jeden Tick-DamageRecord, damit ein Gift-/Brand-Tick,
## der ein Ziel tötet, denselben Killer wie der ursprüngliche Treffer bekommt.
var attacker_peer_id: int = -1

## Akkumulierte Zeit seit dem letzten Tick. Intern von CombatSystem.on_tick() verwaltet.
var _elapsed: float = 0.0

## Factory — siehe CombatSystem.apply_poison() / apply_burn() für die öffentliche API.
## Validierung (tick_interval > 0, total_ticks > 0, hc gültig) liegt bewusst beim
## Aufrufer (CombatSystem), nicht hier — StatusEffect ist ein reiner Datencontainer.
static func make(
		effect_kind: Kind,
		source: String,
		target: String,
		hc: HealthComponent,
		dmg_per_tick: float,
		interval: float,
		total_ticks: int,
		attacker_peer_id: int = -1
) -> StatusEffect:
	var e := StatusEffect.new()
	e.kind             = effect_kind
	e.source_id        = source
	e.target_id        = target
	e.health_component = hc
	e.damage_per_tick  = dmg_per_tick
	e.tick_interval    = interval
	e.ticks_remaining  = total_ticks
	e.attacker_peer_id = attacker_peer_id
	e.effect_key       = "%d:%s:%s" % [effect_kind, source, target]
	return e

## context_tag für DamageRecord.make_environmental() — z.B. für Floating-Text/Logging,
## damit ein Gift-Tick im Log von einem Brand-Tick unterscheidbar ist.
func context_tag() -> String:
	return "poison_tick" if kind == Kind.POISON else "burn_tick"

func to_debug_string() -> String:
	return "StatusEffect[%s key=%s dmg/tick=%.1f interval=%.1fs remaining=%d]" % [
		"POISON" if kind == Kind.POISON else "BURN",
		effect_key, damage_per_tick, tick_interval, ticks_remaining,
	]
