class_name ServiceTeardownManager extends RefCounted

## ServiceTeardownManager — Phase 7, Teardown-Pipeline.
##
##
## execute(registry, boot_order) — Canonical-Pfad.
##   Iteriert boot_order.reversed() — deterministisch, unabhängig von
##   Dictionary-Insertion-Order und register_resource()-Timing.
##
## execute(registry) — Fallback (kein boot_order verfügbar).
##   Nutzt registry.get_all_names() wie bisher. Bleibt für Szenarien wo
##   keine Boot-Reihenfolge gespeichert wurde (z.B. direkte Registry-Tests).

const LOG_CAT := "TeardownManager"

## Canonical: Teardown in explizit reverser Boot-Reihenfolge.
## boot_order: das Array[String] das BootPipeline nach Dependency-Resolve speichert.
func execute(registry: ServiceRegistry, boot_order: Array[String] = []) -> void:
	var ordered: Array[String]
	if not boot_order.is_empty():
		ordered = boot_order.duplicate()
		ordered.reverse()
		AppLogger.log_debug(
			"Teardown in reverser Boot-Reihenfolge (%d Services)." % ordered.size(),
			LOG_CAT
		)
	else:
		# Fallback: Registry-Insertion-Order (implizit, aber deterministisch in GDScript 4.x)
		ordered = registry.get_all_names()
		ordered.reverse()
		AppLogger.log_debug(
			"Teardown via Registry-Reihenfolge (kein boot_order übergeben, %d Services)." % ordered.size(),
			LOG_CAT
		)

	for service_name in ordered:
		var svc: Object = registry.get_service(service_name)
		if not is_instance_valid(svc):
			AppLogger.log_debug("'%s' bereits freigegeben — übersprungen." % service_name, LOG_CAT)
			continue
		if svc is Service or svc is ServiceNode:
			AppLogger.log_debug("on_cleanup() → '%s'" % service_name, LOG_CAT)
			svc.on_cleanup()
		# BUGFIX (2026-09-18, "@Node@N" RPC-Pfad-Bug): Node-basierte Services
		# (ServiceNode, z.B. NetworkBridge) müssen aus dem SceneTree entfernt
		# werden, sonst bleibt der alte Node unter ServiceOrchestrator hängen.
		# Beim nächsten Boot kollidiert der neue add_child() mit demselben
		# Namen ("network_bridge") und Godot vergibt intern einen
		# nicht-lesbaren Namen wie "@Node@790" (force_readable_name=false),
		# statt zu überschreiben — RPC-Pfade laufen danach für den Rest der
		# Session ins Leere (Node not found: "ServiceOrchestrator/@Node@…").
		if svc is Node:
			if svc.is_inside_tree():
				svc.get_parent().remove_child(svc)
			svc.queue_free()

	registry.clear()
	AppLogger.log_info("Teardown abgeschlossen.", LOG_CAT)
