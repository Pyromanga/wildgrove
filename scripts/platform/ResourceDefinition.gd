# res://scripts/platform/ResourceDefinition.gd
class_name ResourceDefinition extends Resource

## ResourceDefinition — deklariert eine injectable .tres/.res-Datei für BootPipeline.
##
## ADR-011: Macht Resource-Injection zu einem deklarierten Mechanismus.
## Jede .tres-Datei die als Dependency gebraucht wird, bekommt einen Eintrag
## in BootstrapConfig.global_resources oder session_resources.
## Kein Pipeline-Code ändert sich wenn ein neuer injectable Resource hinzukommt.
##
## VERWENDUNG (BootstrapConfig.tres):
##   [sub_resource type="Resource" id="Resource_gameconfig"]
##   script = ExtResource("ResourceDef_id")
##   registry_key = "gameconfig"
##   path = "res://config/GameConfig.tres"
##
## registry_key wird als Key in ServiceRegistry registriert.
## Services greifen via deps.require(ServiceKeys.GAME_CONFIG) darauf zu.

## Registry-Key unter dem diese Resource abrufbar ist.
## Muss mit dem entsprechenden ServiceKeys-Eintrag übereinstimmen.
@export var registry_key: String = ""

## Pfad zur .tres- oder .res-Datei.
@export_file("*.tres", "*.res") var path: String = ""
