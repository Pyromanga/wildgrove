# res://scripts/interfaces/core/IServiceContainer.gd
class_name IServiceContainer extends RefCounted

var game_events: RefCounted
var player_states: Node
var interaction_builder: Node
var inventory_system: Node
var player_data: Node
var factory3d: Node
var world: Node