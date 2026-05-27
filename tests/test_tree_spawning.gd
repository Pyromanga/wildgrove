extends "res://addons/gut/test.gd"

func test_tree_spawning_at_correct_position():
    var world = Kernel.world_factory.create_world()
    var pos = Vector3(1, 1, 1)
    Kernel.world_factory.create_tree(pos, world)
    
    var tree = world.get_node("Tree")
    assert_eq(tree.position, pos, "Baum wurde an der falschen Position gespawnt")