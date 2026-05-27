extends CanvasLayer
class_name HUD

var _inventory_label: Label

func _ready() -> void:
    # Hier erzwingst du die Struktur. Wenn hier etwas schiefgeht,
    # ist das HUD kaputt – und das soll es auch!
    _build_ui()

func _build_ui() -> void:
    _inventory_label = Label.new()
    _inventory_label.name = "InventoryLabel" # Eindeutiger Name
    add_child(_inventory_label)
    # Weitere Elemente...

func update_inventory_display(items: Array) -> void:
    # Jetzt kannst du dich sicher auf _inventory_label verlassen
    var text = "Inventar:\n"
    for item in items:
        text += "- " + item.name + ": " + str(item.quantity) + "\n"
    _inventory_label.text = text