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

func install(registry: ServiceRegistry) -> void:
	Logger.log_debug("Fülle DependencyContainer...", LOG_CAT)

	# Alle bekannten Services in den Container eintragen
	Services.populate(registry)

	# Signal: alle Services sind bereit und der Container ist befüllt
	EventBus.system.services_initialized.emit()

	Logger.log_info("DependencyContainer befüllt. System bereit.", LOG_CAT)

func uninstall() -> void:
	Services.clear()
	Logger.log_debug("DependencyContainer geleert.", LOG_CAT)