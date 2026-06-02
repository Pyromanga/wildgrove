# res://scripts/core/services/ServiceValidator.gd
class_name ServiceValidator extends RefCounted

## ServiceValidator — Phase 1 der Boot-Pipeline.
##
## Lädt die BootstrapConfig und prüft sie auf Vollständigkeit,
## bevor auch nur ein Service instanziiert wird.
## Gibt bei Erfolg das fertige Array[ServiceDefinition] zurück,
## bei Fehler ein leeres Array (Boot wird abgebrochen).

const LOG_CAT     := "ServiceValidator"
const CONFIG_PATH := "res://config/bootstrap_config.tres"

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Lädt und validiert die BootstrapConfig.
## Rückgabe: befülltes Array[ServiceDefinition] oder [] bei Fehler.
func validate() -> Array[ServiceDefinition]:
	var config := _load_config()
	if config == null:
		return []

	if config.services.is_empty():
		Logger.log_warn("BootstrapConfig ist leer — keine Services definiert.", LOG_CAT)
		return []

	var defs: Array[ServiceDefinition] = config.services
	var errors := 0

	for def in defs:
		errors += _check_definition(def)

	if errors > 0:
		Logger.log_error("%d Fehler in BootstrapConfig — Boot abgebrochen." % errors, LOG_CAT)
		return []

	Logger.log_info("%d Service-Definitionen validiert." % defs.size(), LOG_CAT)
	return defs

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _load_config() -> BootstrapConfig:
	if not ResourceLoader.exists(CONFIG_PATH):
		Logger.log_error("BootstrapConfig nicht gefunden: '%s'" % CONFIG_PATH, LOG_CAT)
		return null

	var config := load(CONFIG_PATH) as BootstrapConfig
	if config == null:
		Logger.log_error("BootstrapConfig konnte nicht geladen werden: '%s'" % CONFIG_PATH, LOG_CAT)
		return null

	return config

func _check_definition(def: ServiceDefinition) -> int:
	var errors := 0

	if def.service_name.is_empty():
		Logger.log_error("ServiceDefinition ohne Namen gefunden!", LOG_CAT)
		errors += 1

	if def.path.is_empty():
		Logger.log_error("ServiceDefinition '%s' hat keinen Pfad." % def.service_name, LOG_CAT)
		errors += 1
	elif not ResourceLoader.exists(def.path):
		Logger.log_error(
			"Ressource nicht gefunden: '%s' (Service: '%s')" % [def.path, def.service_name],
			LOG_CAT
		)
		errors += 1

	return errors