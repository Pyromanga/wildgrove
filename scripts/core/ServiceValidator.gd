class_name ServiceValidator extends RefCounted

const LOG_CAT     := "ServiceValidator"
const CONFIG_PATH := "res://config/BootstrapConfig.tres"

func validate() -> Array[ServiceDefinition]:
	var config := _load_config()
	if config == null: return []

	if config.services.is_empty():
		Logger.log_warn("BootstrapConfig ist leer.", LOG_CAT)
		return []

	var defs: Array[ServiceDefinition] = []
	for s in config.services:
		defs.append(s as ServiceDefinition)

	var errors := 0
	for i in range(defs.size()):
		errors += _check_definition(defs[i], i)

	if errors > 0:
		Logger.log_error("%d Fehler in BootstrapConfig — Boot abgebrochen." % errors, LOG_CAT)
		return []

	Logger.log_info("%d Service-Definitionen validiert." % defs.size(), LOG_CAT)
	return defs

func _load_config() -> BootstrapConfig:
	if not ResourceLoader.exists(CONFIG_PATH):
		Logger.log_error("Config nicht gefunden: '%s'" % CONFIG_PATH, LOG_CAT)
		return null
	return load(CONFIG_PATH) as BootstrapConfig

func _check_definition(def: ServiceDefinition, index: int) -> int:
	var errors := 0
	
	if def == null:
		Logger.log_error("Eintrag am Index %d ist NULL (Resource fehlt)!" % index, LOG_CAT)
		return 1

	# Identifier für bessere Logs: Entweder der Name oder die Position
	var identifier := "'%s'" % def.service_name if not def.service_name.is_empty() else "Index %d" % index

	if def.service_name.is_empty():
		Logger.log_error("ServiceDefinition am Index %d hat keinen Namen!" % index, LOG_CAT)
		errors += 1

	if def.path.is_empty():
		Logger.log_error("Service %s hat keinen Pfad." % identifier, LOG_CAT)
		errors += 1
	elif not ResourceLoader.exists(def.path):
		Logger.log_error("Pfad existiert nicht: '%s' (Service: %s)" % [def.path, identifier], LOG_CAT)
		errors += 1

	return errors