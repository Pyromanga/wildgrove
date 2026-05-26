extends Node

## Main.gd — Bootstrap (Pure Scripting Refactored)

const WorldScript    := preload("res://scripts/World.gd")
const PlayerScript   := preload("res://scripts/Player.gd")
const TouchScript    := preload("res://scripts/TouchInput.gd")
const HUDScript      := preload("res://scripts/HUD.gd")
const SettingsScript := preload("res://scripts/Settings.gd")
const SkillScript := preload("res://scripts/SkillSystem.gd")

func _ready() -> void:
	# Die Reihenfolge der Initialisierung ist hier klar definiert
    	var world    := _create_node(Node3D, WorldScript, "World")
        	var player   := _create_node(CharacterBody3D, PlayerScript, "Player")
            	var touch    := _create_node(Node, TouchScript, "TouchInput")
                	
                    	# UI braucht spezielle Behandlung wegen der Layer
                        	var hud      := _create_canvas_node(HUDScript, "HUD", 10)
                            	var settings := _create_canvas_node(SettingsScript, "Settings", 20)

                                	# Signale verbinden
                                    	hud.settings_requested.connect(settings.toggle)
                                        	settings.ui_offset_changed.connect(hud.apply_ui_offset)


                                            ## Hilfsfunktion für Standard-Nodes
                                            func _create_node(type: Variant, script: Script, node_name: String) -> Node:
                                            	var n: Node = type.new()
                                                	n.set_script(script)
                                                    	n.name = node_name
                                                        	add_child(n)
                                                            	return n


                                                                ## Hilfsfunktion für CanvasLayer (wegen der Layer-Eigenschaft)
                                                                func _create_canvas_node(script: Script, node_name: String, layer_idx: int) -> CanvasLayer:
                                                                	var cl := CanvasLayer.new()
                                                                    	cl.set_script(script)
                                                                        	cl.name = node_name
                                                                            	cl.layer = layer_idx
                                                                                	add_child(cl)
                                                                                    	return clextends