extends Node
## Main.gd — Bootstrap

func _ready() -> void:
	# Systeme zuerst
	_add_script_node(Node.new(),           "res://scripts/SkillSystem.gd", "SkillSystem")

	# Welt & Spieler
	_add_script_node(Node3D.new(),         "res://scripts/World.gd",       "World")
	_add_script_node(CharacterBody3D.new(),"res://scripts/Player.gd",      "Player")

	# UI deferred — Viewport-Größe erst dann korrekt
	call_deferred("_build_ui")
	call_deferred("_connect_signals")


func _build_ui() -> void:
	_add_script_node(Node.new(),        "res://scripts/TouchInput.gd", "TouchInput")

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
	print("[Main] LEVEL UP: %s → %d" % [skill, new_level])


# ── Hilfsfunktion — lädt Script zur Laufzeit, kein preload ────────────────
func _add_script_node(node: Node, script_path: String, node_name: String) -> void:
	var script: Script = load(script_path)
	if script == null:
		push_error("[Main] Script nicht gefunden: " + script_path)
		return
	node.set_script(script)
	node.name = node_name
	add_child(node)
