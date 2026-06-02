extends Node

## Kernel — Zentrale Service-Registry + Typed Shortcuts.
## Autoload: nach Logger, nach SimpleTerminal.
##
## Shortcuts sind null bis ServiceLoader.bind_shortcuts() nach Phase 3 läuft.
## Gameplay-Code nutzt Shortcuts. Bootstrap-Code nutzt get_service().

signal service_registered(service_name: String)
signal service_unregistered(service_name: String)

# ─────────────────────────────────────────────
# Typed Shortcuts — null bis bind_shortcuts()
# ─────────────────────────────────────────────
var events
var states
var builder
var inventory
var data
var factory3d
var world

var _services: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	Logger.log_debug("Kernel bereit.", "Kernel")

# ─────────────────────────────────────────────
# Registry API
# ─────────────────────────────────────────────

func register_service(service: Object) -> void:
	if not is_instance_valid(service):
		Logger.log_error("Ungültiges Objekt — Registrierung abgebrochen.", "Kernel")
		return
	var s_name := _resolve_name(service)
	if s_name.is_empty():
		Logger.log_error("Service hat keinen auflösbaren Namen.", "Kernel")
		return
	if _services.has(s_name):
		Logger.log_warn("Service '%s' überschrieben." % s_name, "Kernel")
	_services[s_name] = service
	Logger.log_debug("Registriert: '%s'" % s_name, "Kernel")
	service_registered.emit(s_name)

func get_service(service_name: String) -> Object:
	var key := service_name.to_lower()
	var svc  = _services.get(key)
	if not svc:
		Logger.log_error("Service nicht gefunden: '%s'" % service_name, "Kernel")
		return null
	if not is_instance_valid(svc):
		Logger.log_error("Service '%s' ist freigegeben." % service_name, "Kernel")
		_services.erase(key)
		return null
	return svc

func has_service(service_name: String) -> bool:
	return _services.has(service_name.to_lower())

func unregister_service(service: Object) -> void:
	if not is_instance_valid(service):
		return
	var s_name := _resolve_name(service)
	if s_name.is_empty():
		return
	if _services.erase(s_name):
		Logger.log_debug("Entfernt: '%s'" % s_name, "Kernel")
		service_unregistered.emit(s_name)

func get_registered_names() -> Array[String]:
	var names: Array[String] = []
	for key in _services.keys():
		names.append(key)
	return names

# ─────────────────────────────────────────────
# Shortcuts binden — aufgerufen von ServiceLoader nach Phase 3
# ─────────────────────────────────────────────

func bind_shortcuts() -> void:
	Logger.log_info("Binde Kernel-Shortcuts...", "Kernel")

	events    = get_service("gameevents")
	states    = get_service("playerstates")
	builder   = get_service("builder")
	inventory = get_service("inventory")
	data      = get_service("data")
	factory3d = get_service("factory3d")
	world     = get_service("world")

	var checks := {
		"events": events, "states": states, "builder": builder,
		"inventory": inventory, "data": data,
		"factory3d": factory3d, "world": world,
	}
	for k in checks:
		if not checks[k]:
			Logger.log_warn("Shortcut '%s' ist null." % k, "Kernel")

	Logger.log_info("Shortcuts gebunden.", "Kernel")

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _resolve_name(service: Object) -> String:
	if service is Node:
		var n := (service as Node).name
		if not n.is_empty():
			return n.to_lower()
	if service is Service:
		var sn := (service as Service).service_name
		if not sn.is_empty():
			return sn.to_lower()
	var cls := service.get_class()
	return cls.to_lower() if not cls.is_empty() else ""