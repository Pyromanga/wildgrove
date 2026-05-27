# HUD.gd
extends CanvasLayer

var _inventory_label: Label

# Die passive Schnittstelle: Das HUD nimmt an, was es braucht
func update_inventory_display(items: Array) -> void:
    var text = "Inventar:\n"
    for item in items:
        # Hier gehen wir davon aus, dass 'item' ein Dictionary oder Objekt ist
        text += "- " + item.name + ": " + str(item.quantity) + "\n"
    _inventory_label.text = text