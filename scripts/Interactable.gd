extends Node3D
## Interactable.gd — Die Basis-Logik für alle 3D-Interaktionen

var task = null

func _ready() -> void:
	# Hole die Task-Daten, die der InteractionBuilder beim Bauen gesetzt hat
    	task = get_meta("task")
        	_setup_detection_area()

            func _setup_detection_area() -> void:
            	var area = Area3D.new()
                	var col = CollisionShape3D.new()
                    	col.shape = SphereShape3D.new()
                        	col.shape.radius = 2.0
                            	area.add_child(col)
                                	add_child(area)
                                    	
                                        	# Wenn der Spieler eintritt, loggen wir das Event über den Kernel
                                            	area.body_entered.connect(func(b): 
                                                		if b.is_in_group("player"): 
                                                        			Kernel.events.log("Interaktion möglich: " + task.label)
                                                                    	)

                                                                        # Diese Funktion wird vom Player-Script aufgerufen, wenn er "Aktion" drückt
                                                                        func start_interaction() -> void:
                                                                        	if task:
                                                                            		Kernel.builder.execute_interaction(task)