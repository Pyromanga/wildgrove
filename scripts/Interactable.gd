extends Node
## Interactable.gd — Komponente für interaktive Objekte

signal interacted(player)

var display_name := "Objekt"
var on_cooldown := false

# Neue Eigenschaften für Ressourcen- und Skill-System
var resource_type: String = ""       # z.B. "Holz", "Stein"
var resource_amount: int = 1
var xp_skill: String = ""            # z.B. "Holzfällen", "Bergbau"
var xp_amount: int = 10


func interact(player) -> void:
	if on_cooldown:
    		return
            	on_cooldown = true

                	# Ressource zum Inventar hinzufügen
                    	if resource_type != "":
                        		var inv_nodes := get_tree().get_nodes_in_group("inventory")
                                		if inv_nodes.size() > 0 and inv_nodes[0].has_method("add_item"):
                                        			inv_nodes[0].add_item(resource_type, resource_amount)

                                                    	# XP zum Skill hinzufügen
                                                        	if xp_skill != "":
                                                            		var skill_nodes := get_tree().get_nodes_in_group("skills")
                                                                    		if skill_nodes.size() > 0 and skill_nodes[0].has_method("add_xp"):
                                                                            			skill_nodes[0].add_xp(xp_skill, xp_amount)

                                                                                        	# Feedback im HUD anzeigen
                                                                                            	_show_feedback()

                                                                                                	emit_signal("interacted", player)

                                                                                                    	# Cooldown von 1 Sekunde
                                                                                                        	await get_tree().create_timer(1.0).timeout
                                                                                                            	on_cooldown = false


                                                                                                                func _show_feedback() -> void:
                                                                                                                	var hud_nodes := get_tree().get_nodes_in_group("hud")
                                                                                                                    	if hud_nodes.size() > 0 and hud_nodes[0].has_method("show_feedback"):
                                                                                                                        		var msg := ""
                                                                                                                                		if resource_type != "":
                                                                                                                                        			msg += "+%d %s" % [resource_amount, resource_type]
                                                                                                                                                    		if xp_skill != "":
                                                                                                                                                            			if msg != "": msg += ", "
                                                                                                                                                                        			msg += "+%d XP %s" % [xp_amount, xp_skill]
                                                                                                                                                                                    		if msg != "":
                                                                                                                                                                                            			hud_nodes[0].show_feedback(msg)extends