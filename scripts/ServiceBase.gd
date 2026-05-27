extends Node
class_name ServiceBase

## ServiceBase.gd
## Basisklasse für alle Services. Registriert sich automatisch beim Kernel
## und meldet sich beim Löschen sauber wieder ab.

func _ready() -> void:
	# Automatisches Registrieren beim Start
	if Kernel:
		Kernel.register_service(self)
		Logger.log_debug(self.name + " registriert.", "Service")
	else:
		push_error("ServiceBase: Kernel nicht gefunden! Autoload-Reihenfolge prüfen.")

func _exit_tree() -> void:
	# Automatisches Abmelden beim Zerstören (Verhindert Memory Leaks/Dangling Pointers)
	if Kernel:
		Kernel.unregister_service(self)
		Logger.log_debug(self.name + " abgemeldet.", "Service")