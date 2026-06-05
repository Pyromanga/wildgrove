# res://scripts/core/services/ServiceInstaller.gd
class_name ServiceInstaller extends RefCounted

## ServiceInstaller — Phase 6 der Boot-Pipeline.
##
## Befüllt den DependencyContainer mit den fertig initialisierten Services.
## Feuert danach EventBus.system.services_initialized — ab diesem Moment
## ist es sicher, Services über den DependencyContainer abzurufen.
##
## uninstall() wird vom TeardownManager aufgerufen.

const LOG_CAT := "ServiceInstaller"

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func install(registry: ServiceRegistry) -> ServiceRegistry:
	# Optional: Prüfe hier, ob kritische Services da sind
	if not registry.has_service("world"):
		Logger.log_warn("WorldService fehlt beim Installieren!", "Installer")

	return registry
