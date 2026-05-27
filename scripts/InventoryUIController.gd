# res://scripts/InventoryUIController.gd
extends Node

var _hud: CanvasLayer # Dein passives HUD
var _inventory: Inventory # Dein Inventory-System

func _init(hud_ref: CanvasLayer, inv_ref: Inventory) -> void:
    _hud = hud_ref
    _inventory = inv_ref
    
    # Hier verknüpfen wir die Logik mit der UI
    _inventory.inventory_changed.connect(_update_view)

func _update_view() -> void:
    # 1. Daten holen (Logik)
    var raw_items = _inventory.get_all_items()
    
    # 2. Daten aufbereiten (Transformator)
    var display_data = []
    for entry in raw_items:
        var info = _inventory.get_item_info(entry.item_id)
        display_data.append({
            "name": info.name,
            "quantity": entry.quantity
        })
    
    # 3. UI füttern (Präsentation)
    _hud.update_inventory_display(display_data)