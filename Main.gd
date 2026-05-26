extends Node
## Main.gd — Bootstrap (Root Level)

func _ready() -> void:
	# 1. Globale Systeme laden
	# Falls SkillSystem und InventorySystem NICHT im Autoload (project.godot) stehen,
	# werden sie hier manuell erstellt.
	_add_script_node(Node.new(), "res://scripts/SkillSystem.gd", "SkillSystem")
	_add_script_node(Node.new(), "res://scripts/InventorySystem.gd", "InventorySystem")

	# 2. Welt & Spieler laden
	_add_script_node(Node3D.new(),         "res://scripts/World.gd",       "World")
	_add_script_node(CharacterBody3D.new(), "res://scripts/Player.gd",      "Player")

	# UI deferred laden — Viewport-Größe ist erst dann korrekt
	call_deferred("_build_ui")
	call_deferred("_connect_signals")
	
	# Das war der Fehler: log_msg existiert hier nicht. 
	# Wir nutzen die interne _on_debug_log Funktion als Brücke.
	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").debug_log.connect(_on_debug_log)

func _build_ui() -> void:
	_add_script_node(Node.new(), "res://scripts/TouchInput.gd", "TouchInput")

	var hud := CanvasLayer.new()
	hud.layer = 10
	hud.name  = "HUD"
	hud.set_script(load("res://scripts/HUD.gd"))
	add_child(hud)

	var sett := CanvasLayer.new()
	sett.layer = 20
	sett.name  = "Settings"
	sett.set_script(load("res://scripts/Settings.gd"))
	add_child(sett)

	# UI Signale verbinden
	if hud.has_signal("settings_requested"):
		hud.settings_requested.connect(sett.toggle)
	if sett.has_signal("ui_offset_changed"):
		sett.ui_offset_changed.connect(hud.apply_ui_offset)

func _connect_signals() -> void:
	# SkillSystem Signale verbinden
	var skill_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	if skill_nodes.size() > 0:
		var ss: Node = skill_nodes[0]
		ss.xp_gained.connect(_on_xp_gained)
		ss.level_up.connect(_on_level_up)

# --- Signal-Empfänger ---

func _on_xp_gained(skill: String, amount: int, _total: int) -> void:
	var msg = "+%d %s XP" % [amount, skill]
	_on_debug_log(msg)

func _on_level_up(skill: String, new_level: int) -> void:
	var msg = "Level Up! %s ist jetzt %d" % [skill, new_level]
	_on_debug_log(msg)

# Diese Funktion ersetzt das fehlende log_msg in diesem Script
func _on_debug_log(msg: String) -> void:
	print("[Main] " + msg)
	# Hier könnte man noch zusätzliche Logik einbauen, 
	# aber die Nachricht wird ohnehin vom HUD empfangen, 
	# wenn das HUD auch an GameEvents.debug_log hängt.

# Hilfsfunktion zum dynamischen Laden von Nodes mit Skripten
func _add_script_node(base_node: Node, script_path: String, node_name: String) -> Node:
	if ResourceLoader.exists(script_path):
		base_node.set_script(load(script_path))
	else:
		print("WARNUNG: Script nicht gefunden: ", script_path)
	base_node.name = node_name
	add_child(base_node)
	return base_node