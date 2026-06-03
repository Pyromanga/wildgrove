# res://scripts/core/ServiceTicker.gd
extends Node
class_name ServiceTicker

const LOG_CAT := "ServiceTicker"

var _tick_list: Array[Object] = []
var _physics_tick_list: Array[Object] = []

## Registriert einen Service für Updates
func register_service(svc: Object) -> void:
	var registered := false
	
	if svc.has_method("on_tick"):
		_tick_list.append(svc)
		registered = true
		
	if svc.has_method("on_physics_tick"):
		_physics_tick_list.append(svc)
		registered = true
	
	if registered:
		Logger.log_debug("Service '%s' für Ticks registriert." % svc.get_class(), LOG_CAT)

func _process(delta: float) -> void:
	for svc in _tick_list:
		svc.on_tick(delta)

func _physics_process(delta: float) -> void:
	for svc in _physics_tick_list:
		svc.on_physics_tick(delta)