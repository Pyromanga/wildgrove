extends ServiceNode
class_name WorldService

var data: WorldData
var factory: WorldFactory

func init() -> void:
    super.init()
    data = WorldData.new()
    factory = WorldFactory.new()
    # Registrierung beim SaveSystem (für den State)
    var save_system = Kernel.get_service("savesystem")
    if save_system:
        save_system.register_save_provider(self)

## Das ist die Schnittstelle für dein SaveSystem
func get_save_data() -> Dictionary:
    return {
        "tree_positions": var_to_str(data.tree_positions),
        "player_pos": var_to_str(data.player_position)
    }

func load_save_data(state: Dictionary) -> void:
    data.tree_positions = str_to_var(state.get("tree_positions", "[]"))
    # ... hier Logik zum Wiederherstellen der Welt ...
    
func create_world() -> Node3D:
    # 1. Factory baut die Struktur
    var world_root = factory.create_world() 
    
    # 2. Skript an die Welt hängen
    world_root.set_script(load("res://scripts/world/World.gd"))
    
    # 3. Welt-Controller initialisieren
    world_root.setup(data) # Daten an den Controller übergeben
    
    return world_root