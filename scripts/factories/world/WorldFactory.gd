extends Node
## WorldFactory.gd — Die Zentrale

var trees: Node
var props: Node

func _ready() -> void:
    # Die Hauptfactory verwaltet die Unter-Fabriken
    trees = _add_sub_factory("res://scripts/factories/world/TreeFactory.gd", "Trees")
    props = _add_sub_factory("res://scripts/factories/world/PropFactory.gd", "Props")

func _add_sub_factory(path: String, n: String) -> Node:
    var s = load(path).new()
    s.name = n
    add_child(s)
    return s