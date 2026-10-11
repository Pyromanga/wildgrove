extends Node3D
## World.gd — Einstiegspunkt der Spielwelt. Leerer Szenen-Container.
##
## Emittiert keine Events, kein AutoLoad-Zugriff, keine Logik selbst.
## WorldScopeInitializer (Kind-Node dieser Szene) signalisiert per Push an
## ServiceOrchestrator._on_world_initializer_ready(), sobald diese Szene bereit
## ist; der Orchestrator awaitet danach BootPipeline.boot_world(), das wiederum
## WorldService.on_world_scene_ready(self) aufruft (siehe dort).
