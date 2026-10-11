class_name PlayerEvents extends BaseEvents

## PlayerEvents — Alle spielerbezogenen Signals.

## peer_id: wer die XP erhält. Default 1 (Solo/Host) für Aufrufer, die die
## wahre Identität (noch) nicht kennen — siehe emit_xp_gained()-Kommentar.
signal xp_gained(skill: String, amount: int, peer_id: int)
## peer_id: wer den Level-Up hatte. Wird von SkillSystem._check_level_up()
## gesetzt, das peer_id bereits korrekt im Scope hat.
signal level_up(skill: String, new_level: int, peer_id: int)
signal movement_interrupted(peer_id: int)
signal player_died
signal player_respawned
signal inventory_changed(items: Array[Dictionary])
signal speed_modifier_changed(id: String, multiplier: float)
signal speed_modifier_removed(id: String)
signal player_health_changed(current: int, maximum: int)
signal input_reset_requested
signal player_state_changed(state: int)

## Round 103 (ADR-047): gebündelter Bewegungs-Statistik-Report von der
## Autorität, alle STAT_FLUSH_INTERVAL_SEC (Player.gd) statt pro Tick — ein
## Signal pro Peer alle paar Sekunden statt 60/Sekunde, gegen Signal-/
## Log-Spam. walked/jumped/fallen jeweils in Metern seit dem letzten Flush.
signal movement_stats_batch(peer_id: int, walked_m: float, jumped_m: float, fallen_m: float)

func _init() -> void:
	super._init("Events/Player")

## peer_id: wer die XP erhält. Default 1 — nur für Aufrufer gedacht, die die
## wahre Empfänger-Identität (noch) nicht kennen (z.B. EnemyNPC._die(), siehe
## dortiger Kommentar zu fehlender Killer-Attribution). InteractionExecutor
## kennt peer_id bereits korrekt und MUSS ihn explizit übergeben.
func emit_xp_gained(skill: String, amount: int, peer_id: int = 1) -> void:
	_log("XP: +%d in '%s' (Spieler %d)" % [amount, skill, peer_id])
	xp_gained.emit(skill, amount, peer_id)

func emit_level_up(skill: String, new_level: int, peer_id: int = 1) -> void:
	_log_info("Level Up: '%s' → Level %d (Spieler %d)" % [skill, new_level, peer_id])
	level_up.emit(skill, new_level, peer_id)

## ADR-015: peer_id — wessen Interaktion unterbrochen wurde. Default 1
## (Solo/Host) für Aufrufer, die noch nicht umgestellt sind.
func emit_movement_interrupted(peer_id: int = 1) -> void:
	_log("Bewegung unterbrochen (Spieler %d)." % peer_id)
	movement_interrupted.emit(peer_id)

func emit_player_died() -> void:
	_log_warn("Spieler gestorben.")
	player_died.emit()

func emit_player_respawned() -> void:
	_log_info("Spieler respawned.")
	player_respawned.emit()

func emit_inventory_changed(items: Array[Dictionary]) -> void:
	_log("Inventar aktualisiert (%d Items)" % items.size())
	inventory_changed.emit(items)

func emit_speed_modifier_changed(id: String, multiplier: float) -> void:
	_log("Speed Modifikator: '%s' x%.2f" % [id, multiplier])
	speed_modifier_changed.emit(id, multiplier)

func emit_speed_modifier_removed(id: String) -> void:
	_log("Speed Modifikator entfernt: '%s'" % id)
	speed_modifier_removed.emit(id)

func emit_player_health_changed(current: int, maximum: int) -> void:
	player_health_changed.emit(current, maximum)

func emit_input_reset_requested() -> void:
	_log("Input-Reset angefordert.")
	input_reset_requested.emit()

func emit_player_state_changed(state: int) -> void:
	_log("Player-State geändert → %d" % state)
	player_state_changed.emit(state)

func emit_movement_stats_batch(peer_id: int, walked_m: float, jumped_m: float, fallen_m: float) -> void:
	movement_stats_batch.emit(peer_id, walked_m, jumped_m, fallen_m)
