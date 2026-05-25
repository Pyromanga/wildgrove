extends Node

var status_label: Label

func _ready() -> void:
	# Debug-Label immer anzeigen
    	status_label = Label.new()
        	status_label.add_theme_font_size_override("font_size", 32)
            	status_label.add_theme_color_override("font_color", Color.WHITE)
                	status_label.position = Vector2(30, 30)
                    	add_child(status_label)
                        	_log("Starte...")

                            	# Schritt für Schritt laden, damit wir den Fehler sehen
                                	_load_world()
                                    	_load_player()
                                        	_load_touch()
                                            	_load_hud()
                                                	_load_settings()
                                                    	_log("✅ Alle Systeme geladen")


                                                        func _log(msg: String) -> void:
                                                        	if status_label:
                                                            		status_label.text = msg
                                                                    		print(msg)  # falls Remote-Debug später läuft


                                                                            func _load_world() -> void:
                                                                            	_log("Lade World...")
                                                                                	var WorldScript = load("res://scripts/World.gd")
                                                                                    	if WorldScript == null:
                                                                                        		_log("❌ World.gd fehlerhaft")
                                                                                                		return
                                                                                                        	var world = Node3D.new()
                                                                                                            	world.set_script(WorldScript)
                                                                                                                	add_child(world)
                                                                                                                    	_log("✅ World geladen")

                                                                                                                        func _load_player() -> void:
                                                                                                                        	_log("Lade Player...")
                                                                                                                            	var PlayerScript = load("res://scripts/Player.gd")
                                                                                                                                	if PlayerScript == null:
                                                                                                                                    		_log("❌ Player.gd fehlerhaft")
                                                                                                                                            		return
                                                                                                                                                    	var player = CharacterBody3D.new()
                                                                                                                                                        	player.set_script(PlayerScript)
                                                                                                                                                            	player.name = "Player"
                                                                                                                                                                	add_child(player)
                                                                                                                                                                    	_log("✅ Player geladen")

                                                                                                                                                                        func _load_touch() -> void:
                                                                                                                                                                        	_log("Lade TouchInput...")
                                                                                                                                                                            	var TouchScript = load("res://scripts/TouchInput.gd")
                                                                                                                                                                                	if TouchScript == null:
                                                                                                                                                                                    		_log("❌ TouchInput.gd fehlerhaft")
                                                                                                                                                                                            		return
                                                                                                                                                                                                    	var touch = Node.new()
                                                                                                                                                                                                        	touch.set_script(TouchScript)
                                                                                                                                                                                                            	touch.name = "TouchInput"
                                                                                                                                                                                                                	add_child(touch)
                                                                                                                                                                                                                    	_log("✅ TouchInput geladen")

                                                                                                                                                                                                                        func _load_hud() -> void:
                                                                                                                                                                                                                        	_log("Lade HUD...")
                                                                                                                                                                                                                            	var HUDScript = load("res://scripts/HUD.gd")
                                                                                                                                                                                                                                	if HUDScript == null:
                                                                                                                                                                                                                                    		_log("❌ HUD.gd fehlerhaft")
                                                                                                                                                                                                                                            		return
                                                                                                                                                                                                                                                    	var hud = CanvasLayer.new()
                                                                                                                                                                                                                                                        	hud.layer = 10
                                                                                                                                                                                                                                                            	hud.set_script(HUDScript)
                                                                                                                                                                                                                                                                	add_child(hud)
                                                                                                                                                                                                                                                                    	_log("✅ HUD geladen")

                                                                                                                                                                                                                                                                        func _load_settings() -> void:
                                                                                                                                                                                                                                                                        	_log("Lade Settings...")
                                                                                                                                                                                                                                                                            	var SettingsScript = load("res://scripts/Settings.gd")
                                                                                                                                                                                                                                                                                	if SettingsScript == null:
                                                                                                                                                                                                                                                                                    		_log("❌ Settings.gd fehlerhaft")
                                                                                                                                                                                                                                                                                            		return
                                                                                                                                                                                                                                                                                                    	var sett = CanvasLayer.new()
                                                                                                                                                                                                                                                                                                        	sett.layer = 20
                                                                                                                                                                                                                                                                                                            	sett.set_script(SettingsScript)
                                                                                                                                                                                                                                                                                                                	add_child(sett)
                                                                                                                                                                                                                                                                                                                    	# Signalverbindung testen
                                                                                                                                                                                                                                                                                                                        	var hud_nodes = get_tree().get_nodes_in_group("hud")
                                                                                                                                                                                                                                                                                                                            	var sett_nodes = get_tree().get_nodes_in_group("settings")
                                                                                                                                                                                                                                                                                                                                	if hud_nodes.size() > 0 and sett_nodes.size() > 0:
                                                                                                                                                                                                                                                                                                                                    		hud_nodes[0].settings_requested.connect(sett_nodes[0].toggle)
                                                                                                                                                                                                                                                                                                                                            		sett_nodes[0].ui_offset_changed.connect(hud_nodes[0].apply_ui_offset)
                                                                                                                                                                                                                                                                                                                                                    	_log("✅ Settings + Signale")extends