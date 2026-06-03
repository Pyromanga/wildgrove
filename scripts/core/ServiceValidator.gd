class_name ServiceValidator extends RefCounted

const LOG_CAT     := "ServiceValidator"
const CONFIG_PATH := "res://config/BootstrapConfig.tres"

func validate() -> Array[ServiceDefinition]:
	var config := _load_config()
	if config == null: 
		return []

	if config.services.is_empty():
		Logger.log_warn("BootstrapConfig ist leer.", LOG_CAT)
		return []

	# Wir bauen das Array vorsichtig auf
	var defs: Array[ServiceDefinition] = []
	var errors := 0
	
	for i in range(config.services.size()):
		var s = config.services[i]
		
		# NULL-CHECK 1: Ist der Eintrag in der Liste überhaupt ein Objekt?
		if s == null:
			Logger.log_error("Eintrag am Index %d ist physisch NULL (Datei korrupt?)" % i, LOG_CAT)
			errors += 1
			continue
			
		# NULL-CHECK 2: Schlägt der Type-Cast fehl? (Wichtig bei Ladefehlern)
		var def := s as ServiceDefinition
		if def == null:
			Logger.log_error("Eintrag am Index %d ist keine 'ServiceDefinition' (Klasse nicht erkannt?)" % i, LOG_CAT)
			errors += 1
			continue
			
		defs.append(def)

	# Wenn schon beim Laden der Objekte Fehler auftraten, direkt stoppen
	if errors > 0:
		Logger.log_error("%d fundamentale Strukturfehler in der Config." % errors, LOG_CAT)
		return []

	# Jetzt die inhaltliche Validierung der sauberen Liste
	var validation_errors := 0
	for i in range(defs.size()):
		validation_errors += _check_definition(defs[i], i)

	if validation_errors > 0:
		Logger.log_error("%d inhaltliche Fehler gefunden — Boot abgebrochen." % validation_errors, LOG_CAT)
		return []

	Logger.log_info("%d Services erfolgreich validiert." % defs.size(), LOG_CAT)
	return defs

func _load_config() -> BootstrapConfig:
	if not ResourceLoader.exists(CONFIG_PATH):
		Logger.log_error("BootstrapConfig nicht gefunden: '%s'" % CONFIG_PATH, LOG_CAT)
		return null
	
	var res = load(CONFIG_PATH)
	if res == null:
		Logger.log_error("Resource konnte nicht geladen werden (Pfad okay, aber Datei defekt?).", LOG_CAT)
		return null
		
	return res as BootstrapConfig

func _check_definition(def: ServiceDefinition, index: int) -> int:
	var errors := 0
	var identifier := "'%s'" % def.service_name if not def.service_name.is_empty() else "Index %d" % index

	# 1. Basis-Checks (Hast du schon)
	if def.service_name.is_empty():
		Logger.log_error("Service am Index %d hat keinen 'service_name'!" % index, LOG_CAT)
		errors += 1

	if def.path.is_empty():
		Logger.log_error("Service %s: Pfad-Variable ist leer." % identifier, LOG_CAT)
		errors += 1
	elif not ResourceLoader.exists(def.path):
		Logger.log_error("Service %s: Pfad '%s' existiert nicht." % [identifier, def.path], LOG_CAT)
		errors += 1

	# 2. NEU: Check der Daten-Ressourcen (.tres)
	for res_path in def.required_data_files:
		if res_path.is_empty():
			Logger.log_warn("Service %s: Leerer Pfad in 'required_data_files' gefunden." % identifier, LOG_CAT)
			continue
			
		if not ResourceLoader.exists(res_path):
			# Hier exzessives Logging nutzen
			Logger.log_error("Service %s: Benötigte Datei fehlt: '%s'" % [identifier, res_path], LOG_CAT)
			errors += 1
		else:
			# Nur ein kleiner Trace, damit du im Log siehst, dass er es geprüft hat
			Logger.log_debug("Ressource validiert: '%s'" % res_path, LOG_CAT)

	# 3. NEU: Check auf zirkuläre Abhängigkeiten (Self-Reference)
	if def.service_name in def.deps:
		Logger.log_error("Service %s: Abhängigkeit auf sich selbst gefunden (Circular)!" % identifier, LOG_CAT)
		errors += 1

	return errors