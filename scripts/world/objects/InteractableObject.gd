extends Node3D
class_name InteractableObject

## Basis-Variablen (diese werden in der Kind-Klasse überschrieben)
var label: String = "Interagieren"
var duration: float = 2.0
var xp_type: String = "none"
var xp_amount: int = 10

func _ready() -> void:
	# 1. Visuelles Setup der Kind-Klasse ausführen
	_setup_visuals()
	
	# 2. Logik via Kernel-Builder bestellen
	# Wir übergeben hier die Werte der Instanz-Variablen
	Kernel.builder.create(self)\
		.set_label(label)\
		.set_duration(duration)\
		.on_complete(_handle_completion)\
		.build()

## Interne Callback-Funktion der Basis-Klasse
func _handle_completion() -> void:
  # Hier nutzen wir die Instanz-Variablen der spezifischen Klasse
  
  Kernel.events.player.emit_xp(xp_type, xp_amount)
  Kernel.inventory.add_item("log_normal", 3)
	
  # Optional: Falls die Kind-Klasse noch etwas beim Abschluss tun muss
  _on_interaction_finished()
	
  queue_free()

## Virtuelle Methoden für die Kind-Klasse
func _setup_visuals() -> void:
  pass

func _on_interaction_finished() -> void:
  pass