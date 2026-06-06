class_name PlayerStats
extends RefCounted

## PlayerStats — Laufzeit-Spielerwerte (veränderlich, werden gespeichert).
##
## NEU (Session 4): Trennt Konfiguration von Zustand.
##   PlayerData (Resource) = statische Konfiguration (speed, gravity, …) → nie geändert
##   PlayerStats (RefCounted) = Laufzeit-Zustand (health, stamina, hunger) → ändert sich
##
## PlayerService (geplant) hält die Instanz und exponiert sie via Services.player.stats.
## Bis PlayerService existiert: PlayerStats wird im Player-Node gehalten.
##
## SAVES: Wird als SaveSystem-Provider über PlayerService registriert.

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal stats_depleted(stat: String)   ## "health", "stamina"
signal stats_restored(stat: String)

const SAVE_KEY := "player_stats"

## ─── Health ───
var health_max:     float = 100.0
var health_current: float = 100.0

## ─── Stamina (Ausdauer für Rennen/Schwere Arbeit) ───
var stamina_max:           float = 100.0
var stamina_current:       float = 100.0
var stamina_regen_rate:    float = 5.0   ## pro Sekunde bei Inaktivität
var stamina_drain_rate:    float = 10.0  ## pro Sekunde beim Rennen

## ─── Hunger (optional: Stardew-Mechanik) ───
var hunger_max:     float = 100.0
var hunger_current: float = 100.0


func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health_current = maxf(health_current - amount, 0.0)
	health_changed.emit(health_current, health_max)
	if health_current <= 0.0:
		stats_depleted.emit("health")


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	var was_depleted := health_current <= 0.0
	health_current = minf(health_current + amount, health_max)
	health_changed.emit(health_current, health_max)
	if was_depleted and health_current > 0.0:
		stats_restored.emit("health")


func drain_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina_current = maxf(stamina_current - amount, 0.0)
	stamina_changed.emit(stamina_current, stamina_max)
	if stamina_current <= 0.0:
		stats_depleted.emit("stamina")


func restore_stamina(amount: float) -> void:
	stamina_current = minf(stamina_current + amount, stamina_max)
	stamina_changed.emit(stamina_current, stamina_max)


func is_alive() -> bool:
	return health_current > 0.0


func get_health_percent() -> float:
	return health_current / health_max if health_max > 0 else 0.0


func get_stamina_percent() -> float:
	return stamina_current / stamina_max if stamina_max > 0 else 0.0


## Serialisierung für SaveSystem.
func to_save_dict() -> Dictionary:
	return {
		"health_current":  health_current,
		"health_max":      health_max,
		"stamina_current": stamina_current,
		"stamina_max":     stamina_max,
		"hunger_current":  hunger_current,
		"hunger_max":      hunger_max,
	}


## Deserialisierung aus SaveSystem.
func from_save_dict(data: Dictionary) -> void:
	health_current  = data.get("health_current",  health_max)
	health_max      = data.get("health_max",       health_max)
	stamina_current = data.get("stamina_current",  stamina_max)
	stamina_max     = data.get("stamina_max",      stamina_max)
	hunger_current  = data.get("hunger_current",   hunger_max)
	hunger_max      = data.get("hunger_max",       hunger_max)
	health_changed.emit(health_current, health_max)
	stamina_changed.emit(stamina_current, stamina_max)
