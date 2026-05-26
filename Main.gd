extends Node
## Main.gd — Bootstrap

const WorldScript    := preload("res://scripts/World.gd")
const PlayerScript   := preload("res://scripts/Player.gd")
const TouchScript    := preload("res://scripts/TouchInput.gd")
const HUDScript      := preload("res://scripts/HUD.gd")
const SettingsScript := preload("res://scripts/Settings.gd")
const SkillScript    := preload("res://scripts/SkillSystem.gd")


func _ready() -> void:
	# Systeme zuerst — damit Welt und Spieler sie schon finden
	var skill := Node.new()
	skill.set_script(SkillScript)
	skill.name = "SkillSystem"
	add_child(skill)

	var world := Node3D.new()
	world.set_script(WorldScript)
	add_child(world)

	var player := CharacterBody3D.new()
	player.set_script(PlayerScript)
	add_child(player)

	call_deferred("_build_ui")

	# SkillSystem-Events ans HUD weitergeben (nach _build_ui)
	call_deferred("_connect_skill_ui")


func _build_ui() -> void:
	var touch := Node.new()
	touch.set_script(TouchScript)
	add_child(touch)

	var hud := CanvasLayer.new()
	hud.layer = 10
	hud.set_script(HUDScript)
	add_child(hud)

	var sett := CanvasLayer.new()
	sett.layer = 20
	sett.set_script(SettingsScript)
	add_child(sett)

	hud.settings_requested.connect(sett.toggle)
	sett.ui_offset_changed.connect(hud.apply_ui_offset)


func _connect_skill_ui() -> void:
	var skill_nodes: Array = get_tree().get_nodes_in_group("skill_system")
	if skill_nodes.size() == 0:
		return
	var ss: Node = skill_nodes[0]

	# XP-Popup und Level-Up ans HUD
	var hud_layers: Array = get_tree().get_nodes_in_group("hud") 
	# HUD ist noch nicht in Gruppe — Signal direkt verbinden
	ss.xp_gained.connect(_on_xp_gained)
	ss.level_up.connect(_on_level_up)


func _on_xp_gained(skill: String, amount: int, _total: int) -> void:
	# Später: HUD XP-Popup anzeigen
	print("[Main] +%d %s XP" % [amount, skill])


func _on_level_up(skill: String, new_level: int) -> void:
	# Später: großes Level-Up Banner
	print("[Main] LEVEL UP: %s → %d" % [skill, new_level])
