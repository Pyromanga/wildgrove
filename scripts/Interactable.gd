extends Node
## Interactable.gd — Komponente für interaktive Objekte

signal interacted(player)

var display_name := "Objekt"
var on_cooldown := false

# Ressourcen-Daten
var resource_type: String = ""
var resource_amount: int = 1
var xp_skill: String = ""
var xp_amount: int = 10

func interact(player: Node3D) -> void:
	if on_cooldown:
    		return
            	
                	on_cooldown = true
                    	_process_interaction(player)
                        	
                            	# Cooldown Timer
                                	await get_tree().create_timer(1.0).timeout
                                    	on_cooldown = false

                                        func _process_interaction(player: Node3D) -> void:
                                        	# 1. XP vergeben
                                            	if xp_skill != "":
                                                		var skills = get_tree().get_first_node_in_group("skills")
                                                        		if skills and skills.has_method("add_xp"):
                                                                			skills.add_xp(xp_skill, xp_amount)
                                                                            	
                                                                                	# 2. Feedback im HUD
                                                                                    	var msg = ""
                                                                                        	if xp_skill != "":
                                                                                            		msg = "+%d XP %s" % [xp_amount, xp_skill]
                                                                                                    	
                                                                                                        	var hud = get_tree().get_first_node_in_group("hud")
                                                                                                            	if hud and hud.has_method("show_feedback") and msg != "":
                                                                                                                		hud.show_feedback(msg)
                                                                                                                        	
                                                                                                                            	interacted.emit(player)extends