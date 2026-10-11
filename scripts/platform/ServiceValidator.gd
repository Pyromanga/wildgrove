class_name ServiceValidator extends RefCounted

## Injizierbare Config — analog zu ServiceFactory.mounter.
##
## Produktion: bleibt null, _load_config() lädt lazy via
## BootstrapConfig.load_default() (einzige Disk-Quelle, siehe BootstrapConfig.gd)
## und cached das Ergebnis hier.
## Tests: config direkt setzen (var validator := ServiceValidator.new();
## validator.config = my_fake_config) — validate()/validate_session() greifen
## dann nie auf res:// zu. Macht ServiceValidator zu einer reinen Funktion
## ihres Inputs.
var config: BootstrapConfig = null

const LOG_CAT := "ServiceValidator"

## Validiert die Global-Services aus BootstrapConfig.tres.
func validate() -> Array[ServiceDefinition]:
	var cfg := _load_config()
	if cfg == null:
		return []
	return _validate_list(cfg.global_services, "global")

## Validiert die Session-Services aus BootstrapConfig.tres.
## global_names: Namen der bereits gebootteten Global-Services (gelten als bekannte Deps).
func validate_session(global_names: Array[String] = []) -> Array[ServiceDefinition]:
	var cfg := _load_config()
	if cfg == null:
		return []
	return _validate_list(cfg.session_services, "session", global_names)

func _validate_list(
	services: Array[ServiceDefinition],
	label: String,
	external_names: Array[String] = []
) -> Array[ServiceDefinition]:
	if services.is_empty():
		AppLogger.log_warn("BootstrapConfig.%s_services ist leer." % label, LOG_CAT)
		return []

	# Bekannte Namen: eigene + externe (Global-Services)
	var known_names: Dictionary = {}
	for name in external_names:
		known_names[name.to_lower()] = true

	var defs: Array[ServiceDefinition] = []
	var errors := 0

	for i in range(services.size()):
		var s = services[i]

		if s == null:
			AppLogger.log_error(
				"[%s] Eintrag am Index %d ist physisch NULL." % [label, i], LOG_CAT
			)
			errors += 1
			continue

		var def := s as ServiceDefinition
		if def == null:
			AppLogger.log_error(
				"[%s] Eintrag am Index %d ist keine 'ServiceDefinition'." % [label, i], LOG_CAT
			)
			errors += 1
			continue

		defs.append(def)
		known_names[def.service_name.to_lower()] = true

	if errors > 0:
		AppLogger.log_error("%d fundamentale Strukturfehler in [%s]." % [errors, label], LOG_CAT)
		return []

	var validation_errors := 0
	for i in range(defs.size()):
		validation_errors += _check_definition(defs[i], i, known_names)

	if validation_errors > 0:
		AppLogger.log_error(
			"%d inhaltliche Fehler in [%s] — Boot abgebrochen." % [validation_errors, label], LOG_CAT
		)
		return []

	AppLogger.log_info("[%s] %d Services validiert." % [label, defs.size()], LOG_CAT)
	return defs

func _load_config() -> BootstrapConfig:
	if config != null:
		return config
	config = BootstrapConfig.load_default()
	return config

## Gibt die bereits geladene Config zurück (nach validate() aufrufbar).
## BootPipeline nutzt dies für Phase 1.5 (Resource-Loading) ohne doppelten Disk-Zugriff.
func get_loaded_config() -> BootstrapConfig:
	return config

func _check_definition(
	def: ServiceDefinition,
	index: int,
	known_names: Dictionary
) -> int:
	var errors := 0
	var identifier := (
		"'%s'" % def.service_name if not def.service_name.is_empty() else "Index %d" % index
	)

	if def.service_name.is_empty():
		AppLogger.log_error("Service am Index %d hat keinen 'service_name'!" % index, LOG_CAT)
		errors += 1

	if def.path.is_empty():
		AppLogger.log_error("Service %s: Pfad-Variable ist leer." % identifier, LOG_CAT)
		errors += 1
	elif not ResourceLoader.exists(def.path):
		AppLogger.log_error("Service %s: Pfad '%s' existiert nicht." % [identifier, def.path], LOG_CAT)
		errors += 1

	for res_path in def.required_data_files:
		if res_path.is_empty():
			AppLogger.log_warn(
				"Service %s: Leerer Pfad in 'required_data_files'." % identifier, LOG_CAT
			)
			continue
		if not ResourceLoader.exists(res_path):
			AppLogger.log_error(
				"Service %s: Benötigte Datei fehlt: '%s'" % [identifier, res_path], LOG_CAT
			)
			errors += 1

	if def.service_name in def.all_deps():
		AppLogger.log_error(
			"Service %s: Abhängigkeit auf sich selbst (Circular)!" % identifier, LOG_CAT
		)
		errors += 1

	return errors
