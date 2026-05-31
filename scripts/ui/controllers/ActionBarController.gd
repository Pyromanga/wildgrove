extends RefCounted
class_name ActionBarController

func setup(hud: HUD) -> void:
    # Hier kommt die Logik rein, die aktuell noch in create_hud() steht:
    # 1. Berechne Positionen (vielleicht bald via LayoutManager)
    # 2. Erstelle die 3 Buttons mit UIUtils (ehemals Factory)
    # 3. Verbinde Callbacks