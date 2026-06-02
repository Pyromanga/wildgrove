# res://scripts/core/ServiceContainer.gd
class_name ServiceContainer extends RefCounted

## Hier darfst du deine Klassen typisieren!
var game_events: GameEvents
var player_states: PlayerStates
var interaction_builder: BuilderService
var inventory_sytem: InventoryService
var data: DataService
var factory3d: Factory3DService
var world: WorldService