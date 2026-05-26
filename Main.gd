extends Node
## Main.gd — Optimierter Manager für den Spielstart

func _ready() -> void:
	# 1. Welt laden (Basis für alles 3D)
	_add_script_node(Node3D.new(), "res://scripts/World.gd", "World")
	
	# 2. Spieler laden (Wartet auf World)
	var player = _add_script_node(CharacterBody3D.new(), "res://scripts/Player.gd", "Player")

	# 3. UI & Eingabe (muss über dem 3D liegen)
	# TouchInput ist kein Singleton in der project.godot, daher hier laden!
	_add_script_node(Node.new(), "res://scripts/TouchInput.gd", "TouchInput")
	
	# UI-Aufbau verzögert, um sicherzustellen, dass Singletons bereit sind
	call_deferred("_build_ui")
	call_deferred("_connect_signals")
	
	# Debug-Check für den Bus (Singleton)
	if GameEvents:
		GameEvents.debug_log.connect(_on_debug_log)
		GameEvents.log("System-Bootstrap erfolgreich.")

func _build_ui() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.add_to_group("hud") # Wichtig für Factory/Builder!
	hud.set_script(load("res://scripts/HUD.gd"))
	add_child(hud)

	var sett := CanvasLayer.new()
	sett.name = "Settings"
	sett.add_to_group("settings")
	sett.set_script(load("res://scripts/Settings.gd"))
	add_child(sett)

	# Signale zwischen HUD und Settings verbinden
	if hud.has_signal("settings_requested"):
		hud.settings_requested.connect(sett.toggle)
	if sett.has_signal("ui_offset_changed"):
		sett.ui_offset_changed.connect(hud.apply_ui_offset)

func _connect_signals() -> void:
	# Hier verbinden wir globale Ereignisse mit der Main-Logik
	GameEvents.xp_gained.connect(func(skill, amt): 
		_on_debug_log("+%d %s XP erhalten" % [amt, skill])
	)

func _on_debug_log(msg: String) -> void:
	print_rich("[color=cyan][Main][/color] ", msg)

func _add_script_node(base_node: Node, script_path: String, node_name: String) -> Node:
	base_node.name = node_name
	if ResourceLoader.exists(script_path):
		base_node.set_script(load(script_path))
		add_child(base_node)
	else:
		push_error("FEHLER: Datei nicht gefunden: " + script_path)
	return base_node