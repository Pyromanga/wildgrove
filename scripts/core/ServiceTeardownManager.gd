# res://scripts/core/services/ServiceTeardownManager.gd
class_name ServiceTeardownManager extends RefCounted

## ServiceTeardownManager — Phase 7, Teardown-Pipeline.
##
## Wird vom ServiceOrchestrator in _notification(PREDELETE) aufgerufen.
## Reihenfolge ist bewusst umgekehrt zur Boot-Reihenfolge:
##   1. DependencyContainer leeren (kein Lookup mehr möglich)
##   2. Services in umgekehrter Dep-Reihenfolge deaktivieren (on_cleanup)
##   3. Registry leeren

const LOG_CAT := "TeardownManager"

func execute(registry: ServiceRegistry, installer: ServiceInstaller) -> void:
	# 1. Container leeren — ab jetzt kein Services.xyz mehr möglich
	installer.uninstall()

	# 2. Services in umgekehrter Reihenfolge aufräumen
	var all_services := registry.get_all()
	all_services.reverse()

	for svc in all_services:
		if not is_instance_valid(svc):
			continue

		if svc.has_method("on_cleanup"):
			var name := _resolve_name(svc)
			Logger.log_debug("on_cleanup() → '%s'" % name, LOG_CAT)
			svc.on_cleanup()

	# 3. Registry leeren
	registry.clear()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _resolve_name(svc: Object) -> String:
	if svc is Node:
		return (svc as Node).name
	if svc is Service:
		return (svc as Service).service_name
	return svc.get_class()