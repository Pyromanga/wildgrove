extends Node

func _ready():
	var label = Label.new()
    	label.text = "Main OK"
        	label.add_theme_font_size_override("font_size", 64)
            	label.add_theme_color_override("font_color", Color.WHITE)
                	add_child(label)extendsextends