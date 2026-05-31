extends Node3D
# Kein 'extends InteractableObject' mehr! Wir nutzen jetzt Node3D.

func _ready() -> void:
    # 1. Grafik bauen (Eisenerz-Block)
    _setup_visuals()

    # 2. Interaktions-Daten erstellen
    var d = InteractableData.new()
    d.id = "mine_iron"
    d.label = "Eisenerz abbauen"
    d.duration = 4.0
    d.xp_type = "mining"
    d.xp_amount = 40
    d.drops = { "iron_ore": 1 }

    # 3. Komponente hinzufügen
    # Diese Komponente übernimmt jetzt das Label, die Bar und die Logik.
    var comp = InteractableComponent.new()
    comp.data = d
    add_child(comp)

func _setup_visuals() -> void:
    var m   := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.8, 0.8, 0.8)
    m.mesh   = box
    
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.6, 0.5, 0.4)
    # Tipp: billboard_mode hier auf DISABLED lassen, damit es ein echter Block bleibt
    m.material_override = mat
    add_child(m)

# Wird von der InteractableComponent aufgerufen, wenn fertig
func _on_interacted(action_id: String) -> void:
    if action_id == "mine_iron":
        Logger.log_debug("Eisenerz wurde abgebaut und verschwindet.", "IronOre")
        queue_free()