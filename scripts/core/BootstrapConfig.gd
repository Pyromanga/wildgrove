class_name BootstrapConfig extends Resource

## BootstrapConfig — Liste aller Services die beim Start geladen werden.
## Im Editor: Inspector → services Array befüllen.
## Jeder Eintrag ist eine ServiceDefinition Resource.
## HINWEIS: ServiceDefinition ist in ServiceDefinition.gd definiert (eigene Datei).
##          Es gibt keine innere Klasse mehr hier — das war ein Duplikat.

@export var services: Array[ServiceDefinition] = []