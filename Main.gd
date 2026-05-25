extends Node
## Main.gd — Bootstrap (stabil, minimal)

const WorldScript    := preload("res://scripts/World.gd")
const PlayerScript   := preload("res://scripts/Player.gd")
const TouchScript    := preload("res://scripts/TouchInput.gd")
const HUDScript      := preload("res://scripts/HUD.gd")
const SettingsScript := preload("res://scripts/Settings.gd")


func _ready() -> void:
	# Welt
    	var world := Node3D.new()
        	world.set_script(WorldScript)
            	add_child(world)

                	# Spieler
                    	var player := CharacterBody3D.new()
                        	player.set_script(PlayerScript)
                            	player.name = "Player"
                                	add_child(player)

                                    	# UI verzögert laden
                                        	call_deferred("_build_ui")


                                            func _build_ui() -> void:
                                            	# Touch-Input
                                                	var touch := Node.new()
                                                    	touch.set_script(TouchScript)
                                                        	touch.name = "TouchInput"
                                                            	add_child(touch)

                                                                	# HUD (Joystick, Settings-Button)
                                                                    	var hud := CanvasLayer.new()
                                                                        	hud.layer = 10
                                                                            	hud.set_script(HUDScript)
                                                                                	add_child(hud)

                                                                                    	# Settings-Panel
                                                                                        	var sett := CanvasLayer.new()
                                                                                            	sett.layer = 20
                                                                                                	sett.set_script(SettingsScript)
                                                                                                    	add_child(sett)

                                                                                                        	# Signale
                                                                                                            	hud.settings_requested.connect(sett.toggle)
                                                                                                                	sett.ui_offset_changed.connect(hud.apply_ui_offset)extends