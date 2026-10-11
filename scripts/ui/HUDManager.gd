extends Node
class_name HUDManager

const LOG_CAT := "HUD"

var hud: HUD = null
var controllers: Dictionary = {}

var _ui_context_factory: Callable = func() -> IUIContext:
	push_error("HUDManager: set_ui_context_factory() vor build_all() aufrufen.")
	return null

var _bus: IEventBus = null

func initialize() -> void:
	hud = HUD.new()
	hud.name = "GameHUD"
	hud.visible = false
	hud.add_to_group("hud_canvas")

func set_ui_context_factory(factory: Callable) -> void:
	_ui_context_factory = factory

static func boot(tree: SceneTree, ui_context_factory: Callable = Callable()) -> HUDManager:
	var mgr := HUDManager.new()
	mgr.name = "HUDManager"
	mgr.initialize()
	if ui_context_factory.is_valid():
		mgr.set_ui_context_factory(ui_context_factory)
	tree.root.call_deferred("add_child", mgr)
	return mgr

func _ready() -> void:
	AppLogger.log_debug("HUDManager._ready() — hänge HUD unter /root ein.", LOG_CAT)
	get_tree().root.call_deferred("add_child", hud)
	var ctx: IUIContext = _ui_context_factory.call()
	if ctx != null:
		_bus = ctx.bus()
	if _bus != null:
		_bus.world().world_scene_ready.connect(_on_world_scene_ready)
		_bus.system().state_changed.connect(_on_state_changed)
	AppLogger.log_info("HUDManager bereit. HUD wird unter /root eingehängt.", LOG_CAT)

func _exit_tree() -> void:
	if _bus != null:
		if _bus.world().world_scene_ready.is_connected(_on_world_scene_ready):
			_bus.world().world_scene_ready.disconnect(_on_world_scene_ready)
		if _bus.system().state_changed.is_connected(_on_state_changed):
			_bus.system().state_changed.disconnect(_on_state_changed)
	for old_controller in controllers.values():
		if is_instance_valid(old_controller) and old_controller.has_method("teardown"):
			old_controller.teardown()
	if is_instance_valid(hud):
		hud.queue_free()
	hud = null
	controllers.clear()

func get_controller(key: String) -> Object:
	return controllers.get(key)

func _on_world_scene_ready(_scene_root: Node) -> void:
	AppLogger.log_debug("world_scene_ready Signal empfangen — baue HUD-Controller.", LOG_CAT)
	if not is_instance_valid(hud):
		AppLogger.log_error("_on_world_scene_ready: HUD ist null!", LOG_CAT)
		return

	var ctx: IUIContext = _ui_context_factory.call()
	if ctx == null or ctx.bus() == null:
		# Kann während eines Session-Reloads kurzzeitig auftreten, wenn
		# world_scene_ready feuert bevor der neue Session-Kontext vollständig
		# verdrahtet ist (siehe SceneLifecycleHarness). Kein HUD statt Crash —
		# ein späterer world_scene_ready (nach abgeschlossenem Reload) baut
		# den HUD dann korrekt neu auf.
		AppLogger.log_warn(
			"_on_world_scene_ready: UIContext/EventBus noch nicht bereit — HUD-Aufbau übersprungen.",
			LOG_CAT
		)
		return

	# BUGFIX (2026-09-20, "Zombie-Controller nach world_scene_ready"): mehrere
	# Controller (u.a. InventoryUIController, NotificationController) sind
	# reine RefCounted-Objekte ohne `extends Node` — sie hängen NICHT im
	# Scene-Tree unter `hud` und werden vom `child.free()`-Loop oben NICHT
	# erfasst. Sie verbinden sich in setup() aber mit langlebigen Signalen
	# (InventorySystem, EventBus, …), die sie dadurch künstlich am Leben
	# halten. Vorher wurde das nur für "notification" per Hand disconnectet
	# (und nur von EINEM der beiden Signale, die NotificationController
	# nutzt) — jeder andere betroffene Controller leakte weiter. Jetzt:
	# generischer Aufruf von teardown() auf JEDEM alten Controller, der eine
	# solche Methode anbietet, BEVOR die Registry überschrieben wird.
	for old_controller in controllers.values():
		if is_instance_valid(old_controller) and old_controller.has_method("teardown"):
			old_controller.teardown()

	for child in hud.get_children():
		hud.remove_child(child)
		child.free()
	controllers.clear()

	# NotificationController verbindet sich jetzt selbst mit interaction_reward_text
	# (in setup()/teardown()) — siehe Bugfix-Kommentar oben. Kein externer
	# Sonderfall mehr nötig.
	controllers = HUDBuilder.build_all(hud, ctx)

	hud.visible = true
	AppLogger.log_info("HUD aktiv. %d Controller." % controllers.size(), LOG_CAT)

func _on_state_changed(new_state: int) -> void:
	if not is_instance_valid(hud):
		return
	hud.visible = (new_state == GameEnums.State.PLAYING)
