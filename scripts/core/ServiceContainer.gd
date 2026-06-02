# res://scripts/core/ServiceContainer.gd
class_name ServiceContainer extends RefCounted

## Hier darfst du deine Klassen typisieren!
var events: GameEvents
var states: PlayerStates
var builder: BuilderService
var inventory: InventoryService
var data: DataService
var factory3d: Factory3DService
var world: WorldService