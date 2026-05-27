extends "res://addons/gut/test.gd"

# In test_tree_spawning.gd:
func test_tree_spawning_at_correct_position():
    var world = Kernel.world_factory.create_world()
    # Wir suchen jetzt den Baum an der Position, die wir erwarten
    # Falls die Factory mehrere Bäume spawnt, nimm den ersten:
    var tree = world.get_node("Tree") # Achtung: Falls es mehrere gibt, nutze get_children()
    assert_eq(tree.position, Vector3(5, 0, 5), "Position sollte mit Factory-Default übereinstimmen")