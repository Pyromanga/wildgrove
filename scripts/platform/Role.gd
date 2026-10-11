# res://scripts/platform/Role.gd
class_name Role extends Resource

## Role — Datengetriebene Rollen-Definition für PermissionService (ADR-031).
##
## Reines Datenmodell: eine Rolle ist ein Name + eine Menge Capability-Strings.
## Absichtlich KEINE Prüf-Logik hier — "darf Spieler X das?" wird
## ausschließlich serverautoritativ in PermissionService.has_capability()
## beantwortet, nie auf der Resource selbst (gleiche Trennung wie
## BiomeDefinition vs. BiomeRegistry: Resource = Daten, Service = Verhalten;
## eine Resource-Methode hier würde Client und Server gleichermaßen einladen,
## sie direkt aufzurufen statt über den autoritativen Pfad zu gehen).
##
## Neue Capability für eine bestehende Rolle: hier in der .tres-Datei ergänzen,
## kein Code-Umbau nötig (siehe ADR-031 "Entscheidung").

@export var id: String = ""
@export var display_name: String = ""
@export var capabilities: Array[StringName] = []
