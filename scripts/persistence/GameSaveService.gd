extends Service
class_name GameSaveService

## GameSaveService — Koordinator für übergreifende Speicheroperationen.
##
## Verantwortung (klar abgegrenzt nach A-04-Fix):
##   - Lauscht auf save_requested (externer Auslöser von UI/Buttons)
##   - Emittiert save_pre_flush damit Services transiente Daten sichern können
##     (z.B. WorldService → Pets, ohne dass GameSaveService WorldService kennt)
##   - Delegiert den eigentlichen Schreibvorgang an SaveSystem
##   - Doppelaufruf-Schutz (_is_saving-Guard)
##
## NEU (2026-10-11, Server-Persistenz): Autoritäts-Autosave.
##   Vorher lief save_game() NUR bei manuellem save_requested (UI-Button/Quicksave).
##   Ein Host-Crash oder normales Beenden ohne manuellen Save hat damit ALLE
##   Welt-Mutationen seit dem letzten Speichern verloren (Gebäude, Graben,
##   Ernten, Tag/Nacht). Jetzt:
##     1. AUTOSAVE-INTERVALL: Auf der Persistenz-Autorität (Tier 1 Solo ohne
##        echten Peer ODER Tier 2/3 Server/host) schreibt der Service alle
##        AUTOSAVE_INTERVAL_SEC Sekunden den aggregierten State auf Disk —
##        gestützt auf das ServiceTicker-Intervall-Throttling (Issue #1), d.h.
##        der Service tickt nur alle TICK_INTERVAL_SEC statt jeden Frame.
##     2. SAVE BEI SESSION-ENDE: Verlässt der GameState PLAYING (z.B. Host
##        beendet über das Menü), wird ein letzter Save ausgelöst — bevor
##        Session-Services ihre Daten wegwerfen.
##   Clients (Tier 2, kein Server) speichern bewusst NICHT automatisch: ihr
##   _loaded_state ist nach dem Join der Remote-Snapshot der Autorität — ein
##   Client-Autosave würde die Charakter-Buckets des Hosts in den eigenen
##   lokalen Save-Slot schreiben. Client-Fortschritt bleibt Aufgabe der
##   Autorität (die übernimmt die Mutationen via RPC) + manuellen Saves.
##
## Was GameSaveService NICHT tut:
##   - Kein direkter Zugriff auf andere Services via DI
##   - Kein Wissen über Pet-Daten, Spielstand-Inhalt oder Provider-Details
##   - Kein Schreiben auf Disk (delegiert an SaveSystem)
##
## Externe Auslöser:
##   EventBus.persistence.emit_save_requested()  ← von UI-Button oder Quicksave
##   ServiceTicker.on_tick(delta)                ← Autosave-Intervall (Autorität)
##   EventBus.system.state_changed              ← Save bei Spielende (Autorität)
##
## Internes Notify:
##   EventBus.persistence.save_pre_flush         ← WorldService lauscht hier (Pets)
##   EventBus.persistence.save_started           ← von SaveSystem, für UI-Feedback
##   EventBus.persistence.save_completed(bool)   ← von SaveSystem, für UI-Feedback

const LOG_CAT := "GameSave"

## Ticker-Granularität (Issue #1: Intervall-Throttling). 30 s reicht — der
## Autosave-Timer wird intern akkumuliert, keine Frame-Präzision nötig.
const TICK_INTERVAL_SEC := 30.0

## Autoritäts-Autosave: alle 2 Minuten den State auf Disk schreiben. Bewusst
## konservativ: Save-Dateien sind kleine JSONs, ein redundanter Save ist
## billig; ein verlorener Gebäude-/Grabb-Fortschritt ist es nicht. Crash-Loss
## ist damit auf max. AUTOSAVE_INTERVAL_SEC begrenzt.
const AUTOSAVE_INTERVAL_SEC := 120.0

var _save_system: SaveSystem
var _is_saving:   bool = false
var _bus:         IEventBus

## FIX (Root Cause #4, IT-03 rot auf 7a33c7d): Der Ticker kommt jetzt über
## ServiceDeps (get_optional — Tests ohne Ticker laufen ohne fatal weiter),
## statt über das nie existierende "Services"-Autoload. "Services" war ein
## PARSE-Fehler, der die komplette Datei unladbar machte: load() → null →
## Phase factory_character in boot_character() fehlgeschlagen → Host UND
## Client booteden keine Character-Services mehr → IT-03-Timeout.
var _ticker:      ServiceTicker

## Autosave-Akkumulator (Sekunden, aufsummierte Tick-Deltas).
var _autosave_accum: float = 0.0
## Zuletzt gesehener GameState — für Save-bei-Session-Ende (state_changed).
var _was_playing: bool = false

func configure(deps: ServiceDeps) -> void:
	_save_system = deps.require(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	_bus          = deps.require(ServiceKeys.EVENT_BUS)    as IEventBus
	# ServiceKeys.TICKER wird von BootPipeline in die Session-Registry gebridged
	# (ADR-017-Liste in boot_character()) — hier also ein normaler Lookup.
	_ticker       = deps.get_optional(ServiceKeys.TICKER)  as ServiceTicker
	if not is_instance_valid(_save_system):
		AppLogger.log_error("SaveSystem-Dependency fehlt!", LOG_CAT)

func on_ready() -> void:
	_bus.persistence().save_requested.connect(_on_save_requested)

	# Save bei Session-Ende: lausche auf GameState-Wechsel. Wenn PLAYING
	# verlassen wird (Hauptmenü, Quit), schreibt die Autorität einmal final.
	var system_bus := _bus.system()
	if system_bus and system_bus.has_signal("state_changed"):
		system_bus.state_changed.connect(_on_state_changed)
	else:
		AppLogger.log_warn("System-Bus ohne state_changed — Save bei Session-Ende inaktiv.", LOG_CAT)

	# Autosave-Timer: registriere beim Ticker (Intervall-Throttling, Issue #1).
	# Ohne Ticker kein Autosave — manuelles Speichern bleibt hiervon unberührt.
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	else:
		AppLogger.log_warn("ServiceTicker fehlt — Autoritäts-Autosave inaktiv!", LOG_CAT)

	AppLogger.log_info(
		"GameSaveService bereit. save_requested + Autosave (%.0fs Intervall, Autorität)."
		% AUTOSAVE_INTERVAL_SEC, LOG_CAT
	)

func on_cleanup() -> void:
	if _bus and _bus.persistence().save_requested.is_connected(_on_save_requested):
		_bus.persistence().save_requested.disconnect(_on_save_requested)
	var system_bus := _bus.system() if _bus else null
	if system_bus and system_bus.has_signal("state_changed") \
			and system_bus.state_changed.is_connected(_on_state_changed):
		system_bus.state_changed.disconnect(_on_state_changed)
	# Achtung: KEIN finaler Save in on_cleanup() — hier ist die Boot-Reihenfolge
	# im Teardown bereits am Abbauen; SaveSystem/Providers können schon weg sein.
	# Der finale Save läuft über _on_state_changed (PLAYING verlassen), der
	# VOR dem Teardown der Session-Services feuert.
	_autosave_accum = 0.0
	AppLogger.log_info("GameSaveService cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# ServiceTicker-Vertrag (Issue #1: gedrosselter Tick)
# ─────────────────────────────────────────────

## Tick-Intervall für den ServiceTicker (Issue #1-Throttling).
func get_tick_interval() -> float:
	return TICK_INTERVAL_SEC

## Gedrosselter Tick: akkumuliert Zeit und löst den Autosave auf der
## Persistenz-Autorität aus. delta ist hier das AUF SUMMIERTE Intervall-Delta.
func on_tick(delta: float) -> void:
	if not _is_persistence_authority():
		return
	if not is_instance_valid(_save_system) or not _save_system.has_active_session():
		return

	_autosave_accum += delta
	if _autosave_accum < AUTOSAVE_INTERVAL_SEC:
		return

	_autosave_accum = 0.0
	AppLogger.log_info("Autosave-Intervall erreicht (%.0fs) — speichere." % AUTOSAVE_INTERVAL_SEC, LOG_CAT)
	save_all()

# ─────────────────────────────────────────────
# Persistenz-Autorität
# ─────────────────────────────────────────────

## Tier-Prüfung analog NetworkBridge._has_peer()/_is_authority(), aber ohne
## Node-Kontext: GameSaveService ist ein RefCounted-Service, `multiplayer` ist
## hier nicht als Property verfügbar — der Peer wird über den Main-Loop geholt.
##   Tier 1 (Solo, OfflineMultiplayerPeer oder kein Peer)  → true (Autosave an)
##   Tier 2/3 Server/Host (is_server())                    → true (Autosave an)
##   Tier 2 Client (kein Server)                            → false (kein Autosave)
##
## FIX (Root Cause #4): Explizite Typen statt `:=` — SceneTree.multiplayer und
## MultiplayerAPI.multiplayer_peer haben in dieser Godot-Version keinen zur
## Compile-Zeit inferierbaren Typ, `var mp := ...` war ein Parse-Fehler.
func _is_persistence_authority() -> bool:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var mp: MultiplayerAPI = (loop as SceneTree).multiplayer
		if mp != null and mp.has_multiplayer_peer():
			var peer: MultiplayerPeer = mp.multiplayer_peer
			if peer != null and peer.get_class() != "OfflineMultiplayerPeer":
				return mp.is_server()
	return true

# ─────────────────────────────────────────────
# Speichern
# ─────────────────────────────────────────────

## Vollständiger Speichervorgang über alle registrierten Provider.
## Gibt true zurück wenn erfolgreich.
func save_all() -> bool:
	if not is_instance_valid(_save_system):
		AppLogger.log_error("SaveSystem nicht verfügbar — Speichern abgebrochen!", LOG_CAT)
		return false

	if _is_saving:
		AppLogger.log_warn("save_all() bereits aktiv — doppelter Aufruf ignoriert.", LOG_CAT)
		return false

	_is_saving = true
	var t := AppLogger.log_begin("save_all()", LOG_CAT)

	# Pre-Flush: Services mit transienten SceneTree-Daten bereiten ihren State vor.
	# WorldService lauscht hier und sichert Pet-Positionen — GameSaveService
	# kennt WorldService nicht direkt (ADR-001 Schichttrennung).
	_bus.persistence().emit_save_pre_flush()

	var success := _save_system.save_game()
	AppLogger.log_end("save_all()", t, LOG_CAT)
	_is_saving = false

	if success:
		AppLogger.log_info("Speichervorgang erfolgreich.", LOG_CAT)
	else:
		AppLogger.log_error("Speichervorgang fehlgeschlagen!", LOG_CAT)

	return success

func _on_save_requested() -> void:
	AppLogger.log_info("save_requested empfangen — starte save_all().", LOG_CAT)
	save_all()

## Save bei Session-Ende: PLAYING wird verlassen (Hauptmenü/Quit) — die
## Persistenz-Autorität schreibt einmal final, BEVOR der Session-Teardown
## Provider-Daten leert. Läuft auch ohne Ticker (state_changed kommt vom
## EventBus, nicht vom Tick).
func _on_state_changed(new_state: int) -> void:
	var was_playing := _was_playing
	_was_playing = new_state == GameEnums.State.PLAYING

	if not was_playing or _was_playing:
		return  # kein Übergang PLAYING → etwas anderes

	if not _is_persistence_authority():
		return
	if not is_instance_valid(_save_system) or not _save_system.has_active_session():
		return

	AppLogger.log_info("Spiel wird verlassen — finaler Autoritäts-Save.", LOG_CAT)
	save_all()
