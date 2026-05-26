extends Node

## SkillSystem.gd — RuneScape-artiges Skill-System
signal skill_changed(skill_name: String, level: int, xp: int)

# Speicher für die Skills
var skills: Dictionary = {}

func _ready() -> void:
	add_to_group("skills")
    	# Beispiel-Initialisierung (optional)
        	_init_skill("Mining")
            	_init_skill("Woodcutting")

                func _init_skill(skill_name: String) -> void:
                	if not skills.has(skill_name):
                    		skills[skill_name] = { "level": 1, "xp": 0 }

                            func add_xp(skill_name: String, amount: int) -> void:
                            	if not skills.has(skill_name):
                                		_init_skill(skill_name)

                                        	var skill = skills[skill_name]
                                            	skill.xp += amount

                                                	# Level-Up Prüfung (RuneScape-Logik: XP wird NICHT abgezogen)
                                                    	var old_level = skill.level
                                                        	var new_level = _calculate_level_from_xp(skill.xp)
                                                            	
                                                                	if new_level > old_level:
                                                                    		skill.level = new_level
                                                                            		print("Level Up in ", skill_name, "! Neues Level: ", new_level)
                                                                                    	
                                                                                        	skill_changed.emit(skill_name, skill.level, skill.xp)

                                                                                            func get_level(skill_name: String) -> int:
                                                                                            	if skills.has(skill_name):
                                                                                                		return skills[skill_name].level
                                                                                                        	return 1 # Standard-Level ist 1, nicht 0

                                                                                                            func get_xp(skill_name: String) -> int:
                                                                                                            	if skills.has(skill_name):
                                                                                                                		return skills[skill_name].xp
                                                                                                                        	return 0

                                                                                                                            ## Diese Formel bestimmt, wie viel XP man für welches Level braucht
                                                                                                                            func _calculate_level_from_xp(total_xp: int) -> int:
                                                                                                                            	# Einfache Formel: Level = Wurzel aus (XP / Konstante)
                                                                                                                                	# Oder eine RuneScape-ähnliche Treppe:
                                                                                                                                    	var level := 1
                                                                                                                                        	while _get_xp_for_level(level + 1) <= total_xp:
                                                                                                                                            		level += 1
                                                                                                                                                    		if level >= 99: break # Cap bei 99
                                                                                                                                                            	return level

                                                                                                                                                                ## Hilfsfunktion: Wie viel Gesamt-XP brauche ich für Level X?
                                                                                                                                                                func _get_xp_for_level(target_level: int) -> int:
                                                                                                                                                                	if target_level <= 1: return 0
                                                                                                                                                                    	# Beispiel: Jedes Level braucht (Level^2) * 100 XP
                                                                                                                                                                        	return int(pow(target_level - 1, 2) * 100)extends