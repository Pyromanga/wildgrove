extends CanvasLayer
class_name HUD

# Ersetze den Pfad "$Label" durch den tatsächlichen Pfad zu deinem Label-Node
# Falls das Label direkt unter dem HUD liegt, ist es "$LabelName"
@onready var _inventory_label: Label = $Label 

func update_inventory_display(items: Array) -> void:
    # Sicherheitsabfrage, falls das Label aus irgendeinem Grund noch nicht da ist
    if not is_instance_valid(_inventory_label):
        push_warning("HUD: Label nicht gefunden!")
        return
        
    var text = "Inventar:\n"
    for item in items:
        text += "- " + item.name + ": " + str(item.quantity) + "\n"
    _inventory_label.text = text