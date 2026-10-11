class_name BootstrapConfig extends Resource

## BootstrapConfig — deklariert welche Services beim App-Start (global)
## und welche beim Charakter-Start (session) gebootet werden.
##
## ENTSCHEIDUNGSBAUM für neue Services:
##   Hält dieser Service Charakter-spezifischen State
##   oder lädt er Daten aus dem aktiven Save-Slot?
##     JA  → session_services
##     NEIN → global_services
##
## Global-Services leben für die gesamte App-Lifetime.
## Session-Services werden bei jedem Charakter-Wechsel
## vollständig abgerissen und neu gebootet (ADR-009).

## App-globale Services. Booten einmalig beim App-Start.
## Kein Charakter-State — überleben jeden Charakter-Wechsel.
@export var global_services: Array[ServiceDefinition] = []

## Injectable Resources die beim Global-Boot geladen werden (ADR-011 / Säule 2).
## Jede ResourceDefinition wird geladen und unter registry_key in der Registry registriert.
## Services greifen via deps.require(ServiceKeys.GAME_CONFIG) etc. darauf zu.
@export var global_resources: Array[ResourceDefinition] = []

## Injectable Resources die beim Session-Boot geladen werden.
@export var session_resources: Array[ResourceDefinition] = []

## Charakter-spezifische Services. Booten bei Session-Start,
## werden bei Charakter-Wechsel via ServiceTeardownManager bereinigt.
@export var session_services: Array[ServiceDefinition] = []

const DEFAULT_PATH := "res://config/BootstrapConfig.tres"
const LOG_CAT := "BootstrapConfig"

## Lädt die Produktions-Config von Disk (res://config/BootstrapConfig.tres).
##
## Einzige Stelle im Projekt, die diesen Pfad kennt. ServiceValidator (und
## jeder andere Aufrufer) bekommt die Config injiziert statt sie selbst zu
## laden — das macht ServiceValidator.validate()/validate_session() zu einer
## reinen Funktion ihres Inputs, vollständig ohne Disk-Zugriff testbar.
static func load_default() -> BootstrapConfig:
	if not ResourceLoader.exists(DEFAULT_PATH):
		AppLogger.log_error("BootstrapConfig nicht gefunden: '%s'" % DEFAULT_PATH, LOG_CAT)
		return null

	var res = load(DEFAULT_PATH)
	if res == null:
		AppLogger.log_error(
			"Resource konnte nicht geladen werden (Pfad okay, aber Datei defekt?).", LOG_CAT
		)
		return null

	return res as BootstrapConfig
