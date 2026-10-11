# res://scripts/platform/ServiceInstaller.gd
class_name ServiceInstaller extends RefCounted

## ServiceInstaller — Phase 7 der Boot-Pipeline (global und session).
##
## Prüft ob alle kritischen Services in der Registry vorhanden sind.
## Bei fehlenden kritischen Services: install()/install_session() geben false
## zurück — BootPipeline wertet das als Boot-Fehler und bricht die jeweilige
## Phase mit Result.failure() ab (siehe Boot-Fehler-Historie: ein fehlendes
## 'ticker' wurde früher nur geloggt, boot_app() meldete trotzdem Erfolg).

const LOG_CAT := "ServiceInstaller"

## Kritische Global-Services — Spiel nicht lauffähig wenn einer fehlt.
const CRITICAL_GLOBAL: Array[String] = [
	ServiceKeys.TICKER, ServiceKeys.SCENE, ServiceKeys.DATA,
	ServiceKeys.GAME_MANAGER, ServiceKeys.SAVE_SYSTEM, ServiceKeys.SESSION_MANAGER
]

## Kritische Session-Services — Session nicht lauffähig wenn einer fehlt.
const CRITICAL_SESSION: Array[String] = [
	ServiceKeys.INVENTORY,
	ServiceKeys.SKILL_SYSTEM,
	ServiceKeys.QUEST,
	ServiceKeys.WORLD,
	ServiceKeys.PLAYER_STATES,
]

## Empfohlene Session-Services (Warnung wenn fehlt, kein Abbruch).
const RECOMMENDED_SESSION: Array[String] = ["respawn", "world_gen", "reward_dispatcher", "stat_modifiers", "combat"]

func install(registry: ServiceRegistry) -> bool:
	return _check(registry, CRITICAL_GLOBAL, ([] as Array[String]), "global")

func install_session(registry: ServiceRegistry) -> bool:
	return _check(registry, CRITICAL_SESSION, RECOMMENDED_SESSION, "session")

func _check(
	registry: ServiceRegistry,
	critical: Array[String],
	recommended: Array[String],
	label: String
) -> bool:
	var t := AppLogger.log_begin("ServiceInstaller.install(%s)" % label, LOG_CAT)
	var ok := true

	for name in critical:
		if registry.has_service(name):
			AppLogger.log_debug("✓ kritisch [%s]: '%s'" % [label, name], LOG_CAT)
		else:
			AppLogger.log_error(
				"✗ KRITISCH FEHLT [%s]: '%s' — Spiel möglicherweise nicht lauffähig!" % [label, name],
				LOG_CAT
			)
			ok = false

	for name in recommended:
		if registry.has_service(name):
			AppLogger.log_debug("✓ empfohlen [%s]: '%s'" % [label, name], LOG_CAT)
		else:
			AppLogger.log_warn("⚠ empfohlen fehlt [%s]: '%s'" % [label, name], LOG_CAT)

	var total := registry.get_all_names().size()
	AppLogger.log_end("ServiceInstaller.install(%s)" % label, t, LOG_CAT)
	AppLogger.log_info(
		"%d Services installiert [%s]. Kritische OK: %s" % [total, label, "ja" if ok else "NEIN"],
		LOG_CAT
	)
	return ok
