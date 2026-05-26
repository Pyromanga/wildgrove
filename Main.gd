extends Node

## Main.gd — Bootstrap
## Diese Datei orchestriert alle Kern-Systeme des Spiels.

const WorldScript    := preload("res://scripts/World.gd")
const PlayerScript   := preload("res://scripts/Player.gd")
const TouchScript    := preload("res://scripts/TouchInput.gd")
const HUDScript      := preload("res://scripts/HUD.gd")
const SettingsScript := preload("res://scripts/Settings.gd")
const SkillScript    := preload("res://scripts/SkillSystem.gd")

func _ready() -> void:
	# 1. Logik-Systeme (Headless)
    	var skills := _create_node(Node, SkillScript, "SkillSystem")
        	var touch  := _create_node(Node, TouchScript, "TouchInput")
            	
                	# 2. Spielwelt & Charakter
                    	var world  := _create_node(Node3D, WorldScript, "World")
                        	var player := _create_node(CharacterBody3D, PlayerScript, "Player")
                            	
                                	# 3. Benutzeroberfläche (CanvasLayers)
                                    	var hud      := _create_canvas_node(HUDScript, "HUD", 10)
                                        	var settings := _create_canvas_node(SettingsScript, "Settings", 20)

                                            	# 4. Kommunikation aufbauen (Signale & Verknüpfungen)
                                                	_setup_connections(hud, settings, touch)

                                                    	# Optional: Test-XP vergeben nach 2 Sekunden
                                                        	get_tree().create_timer(2.0).timeout.connect(func():
                                                            		skills.add_xp("Mining", 150)
                                                                    	)


                                                                        ## Hilfsfunktion zum Erstellen von Standard-Nodes
                                                                        func _create_node(type: Variant, script: Script, node_name: String) -> Node:
                                                                        	var n: Node = type.new()
                                                                            	n.set_script(script)
                                                                                	n.name = node_name
                                                                                    	add_child(n)
                                                                                        	return n


                                                                                            ## Hilfsfunktion zum Erstellen von CanvasLayern
                                                                                            func _create_canvas_node(script: Script, node_name: String, layer_idx: int) -> CanvasLayer:
                                                                                            	var cl := CanvasLayer.new()
                                                                                                	cl.set_script(script)
                                                                                                    	cl.name = node_name
                                                                                                        	cl.layer = layer_idx
                                                                                                            	add_child(cl)
                                                                                                                	return cl


                                                                                                                    ## Zentrale Signal-Verwaltung
                                                                                                                    func _setup_connections(hud: CanvasLayer, settings: CanvasLayer, touch: Node) -> void:
                                                                                                                    	# Settings öffnen/schließen
                                                                                                                        	hud.settings_requested.connect(settings.toggle)
                                                                                                                            	
                                                                                                                                	# UI Offset (für Handys mit Notch)
                                                                                                                                    	settings.ui_offset_changed.connect(hud.apply_ui_offset)
                                                                                                                                        	
                                                                                                                                            	# Joystick-Visualisierung im HUD registrieren
                                                                                                                                                	if hud.has_method("_connect_touch_input"):
                                                                                                                                                    		hud._connect_touch_input()extends