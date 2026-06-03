extends Node
class_name ServiceTicker

const LOG_CAT := "ServiceTicker"

var _tick_list: Array[Object] = []
var _physics_tick_list: Array[Object] = []
var _running: bool = false


func start_ticking() -> void:
	_running = true
	Logger.log_debug("Ticker läuft.", LOG_CAT)


func register_service(svc: Object) -> void:
	var registered := false
	if svc.has_method("on_tick") and not svc in _tick_list:
		_tick_list.append(svc)
		registered = true

	if svc.has_method("on_physics_tick") and not svc in _physics_tick_list:
		_physics_tick_list.append(svc)
		registered = true

	if registered:
		Logger.log_debug("Service '%s' registriert." % svc.get_class(), LOG_CAT)


func _process(delta: float) -> void:
	if not _running:
		return
	for i in range(_tick_list.size() - 1, -1, -1):
		var svc = _tick_list[i]
		if is_instance_valid(svc):
			svc.on_tick(delta)
		else:
			_tick_list.remove_at(i)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	for i in range(_physics_tick_list.size() - 1, -1, -1):
		var svc = _physics_tick_list[i]
		if is_instance_valid(svc):
			svc.on_physics_tick(delta)
		else:
			_physics_tick_list.remove_at(i)
