class_name ServiceTeardownManager extends RefCounted

## ServiceTeardownManager — Phase 7, Teardown-Pipeline.

const LOG_CAT := "TeardownManager"


func execute(registry: ServiceRegistry) -> void:
	# Wir holen uns alle registrierten Service-Instanzen aus der Registry
	# Da get_all() nicht existiert, iterieren wir über die Namen
	var all_names := registry.get_all_names()
	var services_to_cleanup: Array[Object] = []

	for name in all_names:
		var svc = registry.get_service(name)
		if is_instance_valid(svc):
			services_to_cleanup.append(svc)

	# Optional: Umgekehrte Reihenfolge für die Sicherheit,
	# falls die Reihenfolge der Registrierung relevant war
	services_to_cleanup.reverse()

	for svc in services_to_cleanup:
		if svc.has_method("on_cleanup"):
			var svc_name := _resolve_name(svc)
			Logger.log_debug("on_cleanup() → '%s'" % svc_name, LOG_CAT)
			svc.on_cleanup()

	# Registry leeren
	registry.clear()
	Logger.log_info("Teardown abgeschlossen.", LOG_CAT)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _resolve_name(svc: Object) -> String:
	# Falls es ein Service-Objekt ist, das eine 'service_name' Variable hat
	if "service_name" in svc:
		return svc.service_name
	# Fallback für Nodes oder Standard-Klassen
	if svc is Node:
		return (svc as Node).name
	return svc.get_class()
