extends Node
## Main.gd — Bootstrap (liegt im Repo-Root)

const WorldScript    := preload("res://scripts/World.gd")
const PlayerScript   := preload("res://scripts/Player.gd")
const TouchScript    := preload("res://scripts/TouchInput.gd")
const HUDScript      := preload("res://scripts/HUD.gd")
const SettingsScript := preload("res://scripts/Settings.gd")
const InventoryScript := preload("res://scripts/PlayerInventory.gd")
const SkillSystemScript := preload("res://scripts/SkillSystem.gd")


func _ready() -> void:
	var world := Node3D.new()
    	world.set_script(WorldScript)
        	add_child(world)

            	var player := CharacterBody3D.new()
                	player.set_script(PlayerScript)
                    	player.name = "Player"
                        	add_child(player)

                            	# Neue Systeme
                                	var inventory := Node.new()
                                    	inventory.set_script(InventoryScript)
                                        	inventory.add_to_group("inventory")
                                            	add_child(inventory)

                                                	var skills := Node.new()
                                                    	skills.set_script(SkillSystemScript)
                                                        	skills.add_to_group("skills")
                                                            	add_child(skills)

                                                                	call_deferred("_build_ui")


                                                                    func _build_ui() -> void:
                                                                    	var touch := Node.new()
                                                                        	touch.set_script(TouchScript)
                                                                            	touch.name = "TouchInput"
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

                                                                                                                            	# Interaktions-Signal verbinden
                                                                                                                                	touch.interact_tap.connect(_on_interact_tap)


                                                                                                                                    func _on_interact_tap(pos: Vector2) -> void:
                                                                                                                                    	var player_node := get_node_or_null("Player")
                                                                                                                                        	if player_node and player_node.has_method("try_interact"):
                                                                                                                                            		player_node.try_interact(pos)extends