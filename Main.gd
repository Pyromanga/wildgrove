extends Node
## Main.gd — Bootstrap

func _ready() -> void:
	# 1. Globale Systeme zuerst laden
	_add_script_node(Node.new(), "res://scripts/SkillSystem.gd", "SkillSystem")
	_add_script_node(Node.new(), "res://scripts/InventorySystem.gd", "InventorySystem")

	# 2. Welt & Spieler laden
	_add_script_node(Node3D.new(),         "res://scripts/World.gd",       "World")
	_add_script_node(CharacterBody3D.new(), "res://scripts/Player.gd",      "Player")

	# UI deferred laden — Viewport-Größe ist erst dann korrekt
	call_deferred("_build_ui")
	call_deferred("_connect_signals")

	GameEvents.debug_log.connect(log_msg) # Das verbindet den Bus mit deiner Konsole

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

	hud.settings_requested.connect(sett.toggle)
	sett.ui_offset_changed.connect(hud.apply_ui_offset)


func _connect_signals() -> void:
	var skill_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	if skill_nodes.size() == 0:
		return
	var ss: Node = skill_nodes[0]
	ss.xp_gained.connect(_on_xp_gained)
	ss.level_up.connect(_on_level_up)


func _on_xp_gained(skill: String, amount: int, _total: int) -> void:
	print("[Main] +%d %s XP" % [amount, skill])


func _on_level_up(skill: String, new_level: int) -> void:
	print("[Main] LEVEL UP in %s! Neues Level: %d" % [skill, new_level])


# Hilfsfunktion zum dynamischen Laden von Nodes mit Skripten
func _add_script_node(base_node: Node, script_path: String, node_name: String) -> Node:
	if ResourceLoader.exists(script_path):
		base_node.set_script(load(script_path))
	base_node.name = node_name
	add_child(base_node)
	return base_node