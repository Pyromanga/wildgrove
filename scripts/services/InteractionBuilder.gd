extends ServiceBase
class_name InteractionBuilder


## Interne Task-Klasse – wird per Builder-Pattern konfiguriert
class Task:
	var target: Node3D
	var label: String = "Interagieren"
	var duration: float = 2.0
	var on_done: Callable

	func _init(node: Node3D) -> void:
		target = node

	func set_label(l: String) -> Task:
		label = l
		return self

	func set_duration(d: float) -> Task:
		duration = d
		return self

	func on_complete(c: Callable) -> Task:
		on_done = c
		return self

	## Erzeugt einen Interactable-Node als Kind des Targets
	func build() -> Node3D:
		var interactable := Node3D.new()
		interactable.add_to_group("interactable")
		interactable.set_script(load("res://scripts/Interactable.gd"))
		interactable.set_meta("task", self)
		target.add_child(interactable)
		return interactable


## Führt eine Interaktion aus – inkl. Fortschrittsbalken & Callback
func execute_interaction(task: Task) -> void:
	Logger.log_debug("START execute_interaction für: " + task.label, "Builder")

	if not is_instance_valid(task.target):
		Logger.log_error("ABBRUCH: Target Instanz nicht mehr valide!", "Builder")
		return

	# Kein Callback? Dann trotzdem weitermachen, aber Hinweis loggen.
	if not task.on_done.is_valid():
		Logger.log_warn("Kein gültiger Callback für '%s' – nur BUSY-Zeit wird abgewartet." % task.label, "Builder")

	# Spieler auf BUSY setzen
	Kernel.states.set_state(Kernel.states.PlayerState.BUSY)
	Logger.log_debug("Spieler ist jetzt BUSY", "Builder")

	# Fortschrittsbalken im HUD anzeigen
	var hud_root = Kernel.hud if Kernel.hud else get_tree().root
	var bar = Kernel.ui_factory.create_progress_bar(250.0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud_root.add_child(bar)

	# Tween: Balken von 0 auf 100 füllen
	var tween := bar.create_tween()
	tween.tween_property(bar, "value", 100.0, task.duration).from(0.0)
	await tween.finished   # warten bis Tween durchgelaufen ist

	# Balken aufräumen
	bar.queue_free()

	# Callback ausführen, falls vorhanden
	if task.on_done.is_valid():
		Logger.log_debug("Rufe Callback auf...", "Builder")
		task.on_done.call()

	# Spieler wieder freigeben
	Kernel.states.set_state(Kernel.states.PlayerState.FREE)
	Logger.log_debug("Interaktion beendet, Spieler wieder FREE", "Builder")


## Neue Task für ein Node3D anlegen
func create(node: Node3D) -> Task:
	return Task.new(node)


## Prüft, ob ein Node zur Gruppe "interactable" gehört
func is_interactable(node: Node) -> bool:
	return node.is_in_group("interactable")


## Startet eine Standard-Interaktion (kurz, ohne Callback)
func trigger_interaction(target: Node3D) -> void:
	if is_interactable(target):
		var task := create(target).set_duration(0.1)
		# Optionalen Callback könntest du hier per .on_complete() anhängen
		Kernel.events.interaction_started.emit(task.label, task.duration)
		execute_interaction(task)