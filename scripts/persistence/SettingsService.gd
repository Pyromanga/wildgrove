extends Service
class_name SettingsService

## SettingsService — Zentrale Persistenz für UI-/Client-lokale Einstellungen
## (Joystick, Kamera, Zoom, Bildschirm-Rotation, …).
##
## SCOPE: GLOBAL (wie SaveSystem/DataService) — läuft für die gesamte App-Lifetime,
## unabhängig vom aktiven Charakter. Settings sind Geräte-/Client-Präferenzen,
## kein Spielstand: sie gehören NICHT in SaveSystem/ISaveProvider (das ist
## Charakter-Fortschritt, pro player_id) und NICHT über das Netzwerk synchronisiert
## (siehe NetworkContract.gd „CLIENT-AUTORITATIV" — Settings sind rein lokal).
##
## Eigene Datei statt Teil eines Save-Slots, aus zwei Gründen:
##   1. Settings gelten geräteweit, nicht pro Charakter — sie dürfen einen
##      Charakter-Wechsel oder gelöschten Save-Slot überleben.
##   2. Sie müssen auch ohne aktive Session lesbar sein (z.B. Grafik-Optionen
##      im Hauptmenü, vor jedem Charakter-Login).
##
## PERSISTENZ: Atomic Write (tmp → rename), analog SaveSystem._atomic_write() —
## bewusst nicht geteilt: beide Services sind unabhängig lebensfähig, eine
## gemeinsame Utility wäre eine Kopplung ohne echten Zusatznutzen bei diesem
## Umfang (ein einzelner privater Helfer pro Service, kein Duplication-Schmerz).
##
## ZUGRIFF: über IUIContext.get_settings() (UI-Controller) oder direkt via
## ServiceKeys.SETTINGS_SERVICE (andere Services). Settings.gd (UI-Panel) hält
## selbst KEINEN State mehr — reiner Pull/Push auf diesen Service.

const LOG_CAT := "SettingsService"
const SETTINGS_PATH := "user://settings.json"

## Test-Override für den Persistenz-Pfad. Leer = Produktionspfad (SETTINGS_PATH).
## Analog SaveSystem, das pro Player-ID einen eigenen Pfad berechnet — SettingsService
## hat nur einen einzigen Pfad, der aber in Tests nicht die echte Settings-Datei
## des Dev-Rechners treffen darf. Kein Konstruktor-Parameter (Service wird via
## ServiceFactory ohne Argumente instanziiert) — deshalb ein expliziter Setter,
## NUR für Tests gedacht.
var _path_override: String = ""

## Einzige Quelle der Wahrheit für bekannte Settings-Keys und ihre Defaults.
## Neue Einstellung hinzufügen: hier ergänzen — Settings.gd braucht keine eigene Kopie mehr.
##
## fixed_joystick: true seit Round "Joystick blockiert linke Bildschirmhälfte" —
## der Joystick sitzt jetzt an einer festen, konfigurierbaren Stelle
## (joystick_pos_x/y) statt dort zu erscheinen, wo der Daumen die linke
## Bildschirmhälfte berührt. Das gibt den Rest der linken Seite für Kamera-
## Drehung/Zoom frei (siehe TouchInput._handle_touch()). false = altes
## Verhalten (schwebender Joystick, ganze linke Hälfte reserviert) für alle,
## die das lieber mögen — bleibt als Option erhalten.
const DEFAULTS: Dictionary = {
	"fixed_joystick":    true,
	"joystick_pos_x":    0.16,
	"joystick_pos_y":    0.82,
	"joystick_inverted": false,
	"cam_relative":      true,
	"cam_smooth":        10.0,
	"zoom_smooth":       5.0,
	"screen_rotation":   0,
	## Experimentelle Grafikoption, AUS per Default: echte volumetrische
	## Lichtschächte ("God-Rays") im Kronendach statt nur des normalen,
	## günstigen Wetter-Nebels (siehe WeatherVfx/WorldFactory._add_environment()
	## -Kommentare). Deutlich teurer (voller Froxel-Raymarch pro Frame) — auf
	## einem Mobilgerät ohne dedizierte GPU spürbar, deshalb hier ein reiner
	## An/Aus-Schalter zum Ausprobieren statt eines fest verdrahteten Features.
	## Wird von DayNightCycle gelesen/live angewendet (setting_changed).
	"volumetric_fog":    false,
	## Vorschau-Geist (TerrainEditGhost) beim Graben/Füllen mit der Schaufel — zeigt Ort und
	## Ausmaß des Pinsels VOR der Interaktion (Wunsch "wie beim Antippen highlighten").
	## Getrennt togglebar, weil Graben und Füllen für manche Spieler unterschiedlich oft
	## gebraucht werden. Default AN — reiner Client-Effekt ohne Spiellogik, kein Grund zum
	## Abschalten außer persönlichem Geschmack. Wird von GroundToolController live gelesen
	## (setting_changed) — kein Neustart nötig.
	"dig_preview":       true,
	"fill_preview":      true,
}

var _settings: Dictionary = {}

## Wird gefeuert, sobald ein Wert per set_setting()/reset_to_defaults() geändert
## wurde — UND persistiert werden konnte (siehe set_setting()). Ermöglicht
## Live-Reaktion (z.B. JoystickController verschiebt den Anker sofort, wenn
## der Spieler im Settings-Panel die Joystick-Position ändert) ohne Polling
## oder eine zweite, potenziell veraltete Kopie des Wertes zu halten.
signal setting_changed(key: String, value: Variant)

# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────

func configure(_deps: ServiceDeps) -> void:
	_settings = DEFAULTS.duplicate()
	var loaded := _read_from_disk()
	for key in loaded:
		if DEFAULTS.has(key):
			_settings[key] = loaded[key]
		else:
			AppLogger.log_warn(
				"Unbekannter Settings-Key '%s' in '%s' ignoriert." % [key, SETTINGS_PATH], LOG_CAT
			)
	AppLogger.log_info(
		"SettingsService bereit (%d Keys, %s)."
		% [_settings.size(), "geladen" if not loaded.is_empty() else "Defaults"],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Liest einen Setting-Wert. Gibt default_val zurück wenn der Key unbekannt ist.
func get_setting(key: String, default_val: Variant = null) -> Variant:
	if _settings.has(key):
		return _settings[key]
	return DEFAULTS.get(key, default_val)

## Setzt einen Setting-Wert und persistiert sofort (Settings ändern sich selten —
## kein Debounce/Batching nötig, siehe A-02-Analogon: lieber ein Write zu viel
## als ein Wert, der nur im RAM lebt und beim nächsten Crash verloren geht).
## Gibt true zurück wenn der Schreibvorgang auf Disk erfolgreich war.
func set_setting(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		AppLogger.log_warn("set_setting('%s'): unbekannter Key, wird trotzdem gesetzt." % key, LOG_CAT)
	_settings[key] = value
	var ok := _write_to_disk()
	if ok:
		setting_changed.emit(key, value)
	return ok

## Gibt eine flache Kopie aller aktuellen Settings zurück (z.B. für Panel-Aufbau).
func get_all_settings() -> Dictionary:
	return _settings.duplicate(false)

## Setzt alle Settings auf Defaults zurück und persistiert das Ergebnis.
func reset_to_defaults() -> bool:
	_settings = DEFAULTS.duplicate()
	var ok := _write_to_disk()
	if ok:
		for key in _settings:
			setting_changed.emit(key, _settings[key])
	return ok

## Test-Only: überschreibt den Persistenz-Pfad. Muss vor configure() gesetzt werden.
func set_path_override(p: String) -> void:
	_path_override = p

func _get_path() -> String:
	return _path_override if not _path_override.is_empty() else SETTINGS_PATH

# ─────────────────────────────────────────────
# Intern — Atomic Write (tmp → rename), analog SaveSystem
# ─────────────────────────────────────────────

func _write_to_disk() -> bool:
	var path := _get_path()
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		AppLogger.log_error("Konnte tmp-Datei nicht öffnen: %s" % tmp_path, LOG_CAT)
		return false
	file.store_string(JSON.stringify(_settings, "\t"))
	file.close()

	var rename_err := DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		AppLogger.log_error("Atomic Rename fehlgeschlagen (Error %d)!" % rename_err, LOG_CAT)
		return false
	return true

func _read_from_disk() -> Dictionary:
	var path := _get_path()
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		AppLogger.log_warn("'%s' existiert, konnte aber nicht geöffnet werden." % path, LOG_CAT)
		return {}
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		AppLogger.log_error("'%s' ist korrupt — starte mit Defaults." % path, LOG_CAT)
		return {}
	return json.data
