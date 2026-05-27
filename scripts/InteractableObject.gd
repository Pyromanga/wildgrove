extends Node3D
class_name InteractableObject

## Basis-Klasse für alle interaktiven Objekte
## Definiere diese Variablen, die in der Kind-Klasse gesetzt werden
var label: String = "Interagieren"
var duration: float = 2.0
var xp_type: String = "none"
var xp_amount: int = 10

func _ready() -> void:
    # 1. Visuelles Setup (wird von der Kind-Klasse überschrieben)
    _setup_visuals()
    
    # 2. Logik via Kernel-Builder 'bestellen'
    # Wir nutzen die Variablen der Klasse
    Kernel.builder.create(self)\
        .set_label(label)\
        .set_duration(duration)\
        .on_complete(_on_interaction_finished)\
        .build()

## Muss in Tree.gd oder Ore.gd implementiert werden
func _setup_visuals() -> void:
    pass

func _on_interaction_finished() -> void:
    Kernel.events.emit_xp(xp_type, xp_amount)
    queue_free()