extends Node
## SkillSystem.gd — RuneScape-artiges Skill-System
signal skill_changed(skill_name: String, level: int, xp: int)

var skills: Dictionary = {}        # skill_name -> { "level": int, "xp": int }
const XP_PER_LEVEL: int = 100      # XP für Level-Aufstieg (kann später erweitert werden)

func add_xp(skill_name: String, xp: int) -> void:
	if not skills.has(skill_name):
    		skills[skill_name] = { "level": 1, "xp": 0 }

            	var skill = skills[skill_name]
                	skill.xp += xp

                    	# Level-Up prüfen
                        	while skill.xp >= skill.level * XP_PER_LEVEL:
                            		skill.xp -= skill.level * XP_PER_LEVEL
                                    		skill.level += 1

                                            	emit_signal("skill_changed", skill_name, skill.level, skill.xp)

                                                func get_level(skill_name: String) -> int:
                                                	if skills.has(skill_name):
                                                    		return skills[skill_name].level
                                                            	return 0extends