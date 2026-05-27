extends Node
class_name InventoryUIController

var _hud: HUD
var _inventory: InventorySystem

# Kein _init mit Parametern, damit der Test einfach .new() machen kann
func _init() -> void:
    pass

func setup(hud_ref: HUD, inv_ref: InventorySystem) -> void:
    _hud = hud_ref
    _inventory = inv_ref
    # Erst jetzt verbinden, wenn die Referenzen sicher da sind
    _inventory.inventory_changed.connect(_update_view)
    _update_view()

func _update_view() -> void:
    # Hier knallt es zu Recht, wenn das HUD noch nicht bereit ist - 
    # das zeigt uns einen Fehler in unserer Test-Logik auf!
    if not is_instance_valid(_hud): return
    
    var display_data = []
    for entry in _inventory.get_all_items():
        var info = _inventory.get_item_info(entry.item_id)
        display_data.append({"name": info.name, "quantity": entry.quantity})
    
    _hud.update_inventory_display(display_data)