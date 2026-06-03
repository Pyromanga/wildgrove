extends ServiceNode # Geändert von Service auf ServiceNode für die Registry
class_name DataService

## DataService — Verwaltet statische Basisdaten (PlayerData, ItemDB, etc.).
## Lädt Ressourcen als Single Source of Truth für Standardwerte.

const LOG_CAT   := "DataService"
const DATA_PATH := "res://config/PlayerData.tres"

var player_data: PlayerData

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	_load_resources()

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func get_player_stat(stat_name: String, default_val: float = 0.0) -> float:
	if not player_data:
		Logger.log_error("Abfrage '%s' fehlgeschlagen: player_data ist NULL!" % stat_name, LOG_CAT)
		return default_val
	
	# Godot's Object.get() ist perfekt für dynamische Abfragen von .tres Variablen
	var value = player_data.get(stat_name)
	
	if value != null:
    Logger.log_trace("Stat-Abfrage: %s" % stat_name, {"value": str(value)}, LOG_CAT)
		return float(value)
	
	Logger.log_warn("Stat '%s' existiert nicht in PlayerData.tres!" % stat_name, LOG_CAT)
	return default_val

## Setzt einen Stat im Speicher (wird nicht automatisch auf Festplatte gespeichert!)
func set_player_stat(stat_name: String, value: float) -> void:
	if player_data:
		if stat_name in player_data:
			player_data.set(stat_name, value)
		else:
			Logger.log_warn("Versuch unbekannten Stat zu setzen: %s" % stat_name, LOG_CAT)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _load_resources() -> void:
	if not ResourceLoader.exists(DATA_PATH):
		Logger.log_error("KRITISCH: PlayerData fehlt unter '%s'!" % DATA_PATH, LOG_CAT)
		# Hier könnte man eine leere Instanz als Fallback erstellen:
		# player_data = PlayerData.new()
		return
		
	player_data = load(DATA_PATH) as PlayerData
	
	if player_data:
		Logger.log_info("PlayerData (Basis-Konfiguration) geladen.", LOG_CAT)
	else:
		Logger.log_error("PlayerData-Resource konnte nicht gecastet werden!", LOG_CAT)