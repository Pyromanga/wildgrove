class_name ServiceDefinition extends Resource

## ServiceDefinition — Beschreibt einen einzelnen Service für den Bootstrap.
## Wird in BootstrapConfig.tres als Array gespeichert und im Editor befüllt.
## HINWEIS: Diese Datei ist die einzige Definition — die innere Klasse
##          in BootstrapConfig.gd wurde entfernt (war ein Duplikat).

## Eindeutiger Name des Service. Wird als Kernel-Registry-Schlüssel genutzt.
## Muss mit dem Node.name (für ServiceNode) oder Service.service_name übereinstimmen.
@export var service_name: String = ""

## Pfad zum GDScript oder zur PackedScene.
@export_file("*.gd", "*.tscn") var path: String = ""

## Namen der Services von denen dieser abhängt.
## Bestimmt die Initialisierungs-Reihenfolge (topologische Sortierung).
@export var deps: Array[String] = []

## Ob dieser Service ein Node im Szenen-Baum sein soll (ServiceNode)
## oder ein Pure Service (Service/RefCounted) ohne Node-Overhead.
@export var is_node_service: bool = true