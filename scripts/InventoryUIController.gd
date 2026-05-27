extends Node
class_name InventoryUIController

func _ready() -> void:
    # Registrierung am globalen Bus, statt am konkreten Inventory-Objekt
    # Das entkoppelt den Controller komplett vom konkreten Inventory-Objekt
    Kernel.events.inventory_changed.connect(_update_view)
    _update_view() # Einmal initial zeichnen

func _update_view() -> void:
    # Wir holen uns die Daten direkt aus dem Kernel-Service
    var display_data = []
    for entry in Kernel.inventory.get_all_items():
        var info = Kernel.inventory.get_item_info(entry.item_id)
        display_data.append({"name": info.name, "quantity": entry.quantity})
    
    # Zugriff auf das HUD über den Kernel
    Kernel.hud.update_inventory_display(display_data)