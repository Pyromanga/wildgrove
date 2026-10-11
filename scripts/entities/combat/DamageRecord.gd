class_name DamageRecord
extends RefCounted

## DamageRecord — Unveränderlicher Datenbehälter für einen einzelnen Schadenspunkt.
##
## Wird von CombatSystem erstellt und dann weitergegeben:
##   CombatSystem.calculate_damage() → DamageRecord
##   HealthComponent.take_damage_record(record) → wendet final_amount an
##   EventBus.world.damage_dealt emittiert den fertigen Record
##
## NIEMALS nachträglich mutieren — Record ist nach calculate_damage() final.

## Schadenstypen (entsprechen ADR-008-Entscheidung).
## PHYSICAL → durch Rüstung reduziert
## MAGIC    → durch magische Resistenz reduziert
## TRUE     → ignoriert alle Resistenzen (Gifttränke, Sturz, etc.)
enum DamageType {
	PHYSICAL,
	MAGIC,
	TRUE,
}

## UUID der angreifenden Entity. Leer = Umweltschaden (Sturz, Gift).
## Bleibt ein Entity-Typ-Label für Logging (z.B. "player", "goblin_1") —
## NICHT die Spieler-Identität. Siehe attacker_peer_id dafür (ADR-019).
var source_id: String = ""

## UUID des Ziels.
var target_id: String = ""

## Echte peer_id des angreifenden Spielers, oder -1 wenn kein Spieler
## Angreifer ist (Umweltschaden, Gegner-Angriff auf Spieler, Gift/Brand ohne
## bekannten Verursacher). Getrennt von source_id (ADR-019 Punkt 3) — source_id
## bleibt reines Logging-Label, attacker_peer_id ist die einzige Quelle für
## Killer-Attribution (XP/Loot).
var attacker_peer_id: int = -1

## Roh-Schaden vor Resistenz-Berechnung.
var raw_amount: float = 0.0

## Schadenstyp — bestimmt welche Resistenzen angewendet werden.
var damage_type: DamageType = DamageType.PHYSICAL

## Finaler Schaden nach Berechnung (was tatsächlich abgezogen wird).
## Wird von CombatSystem.calculate_damage() gesetzt.
var final_amount: float = 0.0

## Ob dieser Treffer ein kritischer Treffer war.
var is_critical: bool = false

## Optionaler Freitext — z.B. "fall_damage", "poison_tick", "reflect" für Logging.
var context_tag: String = ""

## Factory: erstellt einen Record für Spieler-Angriff auf Enemy.
## [param attacker_peer_id] Echte peer_id des angreifenden Spielers (ADR-019).
## Default -1 nur für Aufrufer, die (noch) keinen Spieler kennen — die einzige
## intendierte Nutzung dessen ist source_id-only-Logging in Tests.
static func make_player_attack(
		source: String,
		target: String,
		raw: float,
		dtype: DamageType = DamageType.PHYSICAL,
		attacker_peer_id: int = -1
) -> DamageRecord:
	var r := DamageRecord.new()
	r.source_id  = source
	r.target_id  = target
	r.raw_amount = raw
	r.damage_type = dtype
	r.attacker_peer_id = attacker_peer_id
	return r

## Factory: erstellt einen Record für Enemy-Angriff auf Spieler (TD-11).
## Eigene Factory statt Wiederverwendung von make_player_attack() — der Name
## dokumentiert die Angriffsrichtung direkt im Log (context_tag), nicht nur
## über source_id/target_id, die je nach Entity-UUID kryptisch sein können.
## [param attacker_peer_id] Bleibt -1 im normalen PvE-Fall — ein Gegner ist
## kein Spieler. Parameter existiert trotzdem (statt hartcodiertem -1 intern),
## damit ein zukünftiger PvP-Pfad (Spieler steuert die angreifende Entity)
## denselben Konstruktor nutzen kann, ohne eine zweite Factory zu brauchen.
static func make_enemy_attack(
		source: String,
		target: String,
		raw: float,
		dtype: DamageType = DamageType.PHYSICAL,
		attacker_peer_id: int = -1
) -> DamageRecord:
	var r := DamageRecord.new()
	r.source_id   = source
	r.target_id   = target
	r.raw_amount  = raw
	r.damage_type = dtype
	r.context_tag = "enemy_melee"
	r.attacker_peer_id = attacker_peer_id
	return r

## Factory: erstellt einen Record für Umweltschaden (kein Angreifer) — ODER für
## einen Status-Effekt-Tick (Gift/Brand), der über CombatSystem.on_tick() läuft.
## [param attacker_peer_id] Für echten Umweltschaden (Sturz) bleibt dies -1.
## Für Status-Effekt-Ticks, die von einem Spieler-Waffentreffer ausgelöst wurden
## (StatusEffect.attacker_peer_id, ADR-019), wird die echte peer_id durchgereicht —
## sonst würde ein Gift-Tick, der einen Gegner tötet, denselben Killer-Attributions-
## Verlust erzeugen wie der ursprüngliche Treffer selbst.
static func make_environmental(
		target: String,
		raw: float,
		tag: String = "",
		attacker_peer_id: int = -1
) -> DamageRecord:
	var r := DamageRecord.new()
	r.source_id   = ""
	r.target_id   = target
	r.raw_amount  = raw
	r.damage_type = DamageType.TRUE
	r.context_tag = tag
	r.attacker_peer_id = attacker_peer_id
	return r

func to_debug_string() -> String:
	return "DamageRecord[%s→%s type=%d raw=%.1f final=%.1f crit=%s tag=%s attacker_pid=%s]" % [
		source_id if source_id else "ENV",
		target_id if target_id else "?",
		damage_type,
		raw_amount,
		final_amount,
		"YES" if is_critical else "no",
		context_tag if context_tag else "-",
		str(attacker_peer_id) if attacker_peer_id != -1 else "none",
	]
