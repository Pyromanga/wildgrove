# res://tests/mocks/MockHarvestable.gd
extends Node3D

## Minimaler Node3D-Test-Double für EntityOrchestrator-Tests, die eine echte
## registrierbare/instanziierbare Entity brauchen (spawn_entity() lädt den
## Pfad via ResourceLoader — ein reiner Node3D.new() reicht dafür nicht aus).
## Bewusst ohne on_spawn()/on_despawn(): EntityOrchestrator behandelt beide
## als optional (has_method()-Guard), Tests für resolve_for_player() brauchen
## keine Lifecycle-Hooks.
