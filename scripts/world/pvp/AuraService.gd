extends Service
class_name AuraService

## AuraService — ADR-036 "Aura/Gesinnung": Reputationswert pro Spieler
## (`-6000..+6000`), sinkt bei unprovozierten Skull-Kills, steigt über eine
## neue "Danken"-Spieler-Interaktion (max. 1×/24h pro Spielerpaar).
##
## "SKULL-AUSLÖSENDER (UNPROVOZIERTER) KILL" — Interpretationsentscheidung,
## da die ADR das nicht mechanisch exakt spezifiziert: eine Aura-Strafe wird
## angewendet, wenn der KILLER zum Zeitpunkt des Kills selbst geskullt war
## (`PvPService.is_skulled(killer_player_id)`). Skull-Status IST bereits die
## im Projekt vorhandene Definition von "hat kürzlich unprovoziert
## angegriffen/nicht auf Gegenwehr gewartet" (ADR-032) — eine zweite,
## parallele "war das ein unprovozierter Kill?"-Erkennung wäre doppelte
## Buchführung für dieselbe Information. Aufgerufen von
## PvPDeathLossService.apply_death_loss() nach jedem PvP-Tod.
##
## VULNERABILITY-SCHWELLE: `AURA_VULNERABILITY_THRESHOLD = -3000` (Mittelwert
## zwischen 0 und `-6000`) ist wie die Punktwerte unten ein dokumentierter
## Platzhalter, kein finaler Balance-Wert (ADR-036 selbst: "Konkrete Zahlen
## sind ein fairer Vorschlag"). `PvPService.is_vulnerable_in_safe_zone()`
## bleibt bewusst der alleinige Aggregationspunkt (siehe dortiger
## Klassenkommentar "AURA-TEIL NICHT ENTHALTEN") — dieser Service liefert nur
## `is_below_vulnerability_threshold()`, PvPService kombiniert es mit dem
## Skull-Teil.
##
## PERSISTENZ: `_aura` (player_id → int) UND `_thank_cooldowns` (Paar-Schlüssel
## → letzter Dank-Zeitstempel) sind BEIDE persistiert — ohne Cooldown-
## Persistenz könnte ein Server-Neustart den 24h-Cooldown umgehen (Exploit).

signal aura_changed(player_id: String, new_aura: int, delta: int)
signal thank_failed(from_player_id: String, reason: String)

const LOG_CAT := "Aura"
const SAVE_KEY := "aura"

const AURA_MIN: int = -6000
const AURA_MAX: int =  6000

## Platzhalter, kein finaler Balance-Wert (siehe Klassenkommentar).
const AURA_VULNERABILITY_THRESHOLD: int = -3000
const KILL_PENALTY: int = -200

const THANK_COOLDOWN_SEC: float = 24.0 * 60.0 * 60.0  ## 24 Stunden (ADR-036)
## Solange aura < 0: max(50, |aura| * 0.05). Ab aura >= 0: fixer +25-Zuwachs.
const THANK_MIN_GAIN_NEGATIVE: int = 50
const THANK_GAIN_NEGATIVE_PCT: float = 0.05
const THANK_GAIN_NON_NEGATIVE: int = 25

var _network:     NetworkBridge = null
var _save_system: SaveSystem    = null

## player_id (String) -> int
var _aura: Dictionary = {}
## Paar-Schlüssel (sortiert, "idA|idB") -> letzter Dank-Unix-Zeitstempel (float)
var _thank_cooldowns: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_network     = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_save_system = deps.get_optional(ServiceKeys.SAVE_SYSTEM)    as SaveSystem

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("AuraService initialisiert (%d gespeicherte Werte)." % _aura.size(), LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage
# ─────────────────────────────────────────────

func get_aura(player_id: String) -> int:
	return int(_aura.get(player_id, 0))

## Für PvPService.is_vulnerable_in_safe_zone() (siehe dortiger Klassenkommentar).
func is_below_vulnerability_threshold(player_id: String) -> bool:
	return get_aura(player_id) < AURA_VULNERABILITY_THRESHOLD

# ─────────────────────────────────────────────
# Öffentliche API — Kill-Strafe (von PvPDeathLossService aufgerufen)
# ─────────────────────────────────────────────

## Autoritäts-only wie PvPDeathLossService.apply_death_loss() selbst (das der
## einzige aktuelle Aufrufer ist) — kein request_*/on_*_confirmed()-Split,
## siehe dortiger Klassenkommentar für die identische Begründung.
func apply_kill_penalty(killer_player_id: String) -> void:
	if not _require_authority("apply_kill_penalty"):
		return
	if killer_player_id.is_empty():
		return
	_apply_delta(killer_player_id, KILL_PENALTY)

# ─────────────────────────────────────────────
# Öffentliche API — Danken (Spieler-Interaktion)
# ─────────────────────────────────────────────

## Absicht: "from_player_id bedankt sich bei to_player_id". Server prüft
## Cooldown UND berechnet den tatsächlichen Gain (proportional zum aktuellen
## Aura-Defizit von to_player_id) — der Client kennt weder das eine noch das
## andere zuverlässig.
##
## Wird von Player._on_thank_requested() aufgerufen (statt on_thank_confirmed()
## direkt) — einheitlicher Einstiegspunkt, konsistent mit
## ItemProtectionService.request_apply_protection()/AuctionHouseService/
## TradeService. Der Netzwerk-Zweig unten greift von DIESEM einen Aufrufer
## aus praktisch nie (Player._on_thank_requested() läuft erst nach einem
## is_multiplayer_authority()-Guard, ist an dieser Stelle also immer schon
## Autorität) — request_thank() bleibt trotzdem der EINE öffentliche
## API-Methode, damit ein künftiger zweiter Aufrufer (z.B. ein UI-Panel-
## Trigger ohne InteractableComponent) sie einfach mitbenutzen kann, ohne
## dass zwei verschiedene Einstiegspunkte mit unterschiedlichen Garantien
## nebeneinander existieren.
func request_thank(from_player_id: String, to_player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_aura_thank(from_player_id, to_player_id)
	else:
		on_thank_confirmed(from_player_id, to_player_id)

func on_thank_confirmed(from_player_id: String, to_player_id: String) -> void:
	if not _require_authority("on_thank_confirmed"):
		return

	if from_player_id.is_empty() or to_player_id.is_empty() or from_player_id == to_player_id:
		thank_failed.emit(from_player_id, "invalid_target")
		return

	var key := _pair_key(from_player_id, to_player_id)
	var last: float = float(_thank_cooldowns.get(key, 0.0))
	if _now() - last < THANK_COOLDOWN_SEC:
		thank_failed.emit(from_player_id, "cooldown_active")
		return

	_thank_cooldowns[key] = _now()

	var current := get_aura(to_player_id)
	var gain: int
	if current < 0:
		gain = maxi(THANK_MIN_GAIN_NEGATIVE, int(round(absf(float(current)) * THANK_GAIN_NEGATIVE_PCT)))
	else:
		gain = THANK_GAIN_NON_NEGATIVE

	_apply_delta(to_player_id, gain)
	AppLogger.log_debug(
		"'%s' bedankt sich bei '%s' (+%d Aura, jetzt %d)." % [from_player_id, to_player_id, gain, get_aura(to_player_id)],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _apply_delta(player_id: String, delta: int) -> void:
	var new_aura := clampi(get_aura(player_id) + delta, AURA_MIN, AURA_MAX)
	_aura[player_id] = new_aura
	aura_changed.emit(player_id, new_aura, delta)

func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

func _now() -> float:
	return Time.get_unix_time_from_system()

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

# ─────────────────────────────────────────────
# Save-Interface (analog PvPService/CurrencyService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

## Cooldowns werden mitgespeichert (siehe Klassenkommentar "PERSISTENZ") —
## abgelaufene (>24h) werden beim Speichern herausgefiltert, kein
## Erkenntniswert, hält den Save schlank (analog PvPService-Muster).
func get_save_data() -> Dictionary:
	var now := _now()
	var fresh_cooldowns: Dictionary = {}
	for key in _thank_cooldowns:
		if now - float(_thank_cooldowns[key]) < THANK_COOLDOWN_SEC:
			fresh_cooldowns[key] = _thank_cooldowns[key]
	return {"aura": _aura, "thank_cooldowns": fresh_cooldowns}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("aura") is Dictionary:
		_aura = saved["aura"]
	if saved.get("thank_cooldowns") is Dictionary:
		_thank_cooldowns = saved["thank_cooldowns"]
