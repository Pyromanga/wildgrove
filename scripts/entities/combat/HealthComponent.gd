class_name HealthComponent
extends Node

## HealthComponent — HP-Verwaltung für Spieler und feindliche NPCs.
## take_damage(amount) → einfacher Pfad ohne Attributions-Info, emittiert
##   health_changed und ggf. died(null).
## take_damage_record(record) → wendet record.final_amount an und emittiert
##   bei Tod died(record) — der todesursächliche Record trägt die Angreifer-
##   Identität (DamageRecord.attacker_peer_id, ADR-019) mit.

signal health_changed(current: int, maximum: int)
## record: der todesursächliche DamageRecord, oder null wenn der Tod durch
## einen direkten take_damage(amount)-Aufruf ausgelöst wurde (z.B. Tests,
## siehe HealthComponent-Kommentar). Consumer MÜSSEN den null-Fall behandeln.
signal died(record: DamageRecord)

## KONTRAKT (2026-09-25 gefixt, siehe TODO-offene-probleme.md "HealthComponent.
## max_health-Setter"): "Sync current mit max beim ERSTEN Setzen" war schon
## immer der dokumentierte Anspruch dieses Setters — die Implementierung hat
## das bisher aber NICHT geprüft, sondern bei JEDEM Setzen synchronisiert.
## Symptom: jede spätere max_health-Änderung an einer bereits laufenden
## Komponente (Buff, Admin-Befehl, künftiges Level-Up-System, …) hat das
## aktuelle Leben stillschweigend auf das neue Maximum gesetzt/geheilt, statt
## es unverändert zu lassen. `is_node_ready()` ist das verlässliche Signal für
## "erstes Setzen": alle drei produktiven Konstruktions-Call-Sites
## (PlayerSetup._build_health, EnemyNPC._setup_health, EnemyNPC-Pool-Reuse via
## cfg.max_health) setzen max_health nachweislich VOR add_child(), also bevor
## _ready() je gelaufen ist. Verhalten für diese drei Stellen dadurch
## unverändert (siehe scripts/agent/health_contract_check.py für die
## automatisierte Verifikation aller Call-Sites). Wer nach dem ersten Setzen
## trotzdem voll heilen will, ruft weiterhin explizit reset() auf (macht
## EnemyNPC beim Pool-Reuse bereits so) — das bleibt der einzige Weg, current
## bewusst auf max hochzusetzen.
@export var max_health: int = 50:
	set(v):
		max_health = v
		if not is_node_ready():
			current_health = v   ## Erstes Setzen (vor _ready(), siehe Kontrakt oben)
		else:
			## Live-Änderung: current NIE hochziehen (das wäre ein impliziter
			## Heal), nur nach unten klemmen falls current > neues Maximum.
			current_health = min(current_health, v)
var current_health: int = 50
var is_dead: bool = false

func _ready() -> void:
	## Sicherheitsnetz für den Fall, dass current_health vor _ready() aus
	## irgendeinem Grund nicht mit max_health synchron ist (z.B. Szenen-
	## Instanzierung/Editor-Reihenfolge). Läuft nur einmal, beeinflusst die
	## Live-Änderungs-Semantik des Setters oben nicht.
	current_health = max_health

## Einfacher Schadenspfad ohne Attributions-Info — für direkte Aufrufer, die
## keinen DamageRecord haben (Tests, Umweltschaden ohne CombatSystem-Pfad).
## Bei tödlichem Schaden wird died(null) emittiert.
func take_damage(amount: int) -> void:
	_apply_damage(amount, null)

## Bevorzugter Schadenspfad: wendet record.final_amount an und gibt den Record
## bei Tod an died() weiter, damit Consumer (z.B. EnemyNPC._die()) die echte
## Angreifer-Identität kennen (ADR-019 Option B).
func take_damage_record(record: DamageRecord) -> void:
	_apply_damage(int(record.final_amount), record)

func _apply_damage(amount: int, record: DamageRecord) -> void:
	if is_dead:
		return
	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		is_dead = true
		died.emit(record)

func heal(amount: int) -> void:
	if is_dead:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func reset() -> void:
	current_health = max_health
	is_dead = false
	health_changed.emit(current_health, max_health)
