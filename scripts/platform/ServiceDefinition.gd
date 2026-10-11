class_name ServiceDefinition extends Resource

## required_deps / optional_deps (statt eines einzigen "deps"): die
## require()/get_optional()-Entscheidung aus configure() lebte vorher NUR
## im jeweiligen Service-Code, nirgends strukturiert — di_test_overview.py
## musste sie per Textsuche im Code raten. Jetzt ist es Teil der Definition
## selbst: eine Config, ein Blick, keine Code-Analyse nötig.
##
## Für die Boot-Reihenfolge (Kahn's Algorithmus in ServiceDependencyResolver)
## zählen BEIDE Listen gleich — ob ein Service seine Dep optional behandelt,
## ändert nichts daran, dass sie (falls vorhanden) vor ihm gebootet sein muss.
## Deshalb all_deps() als einzige Stelle, die beide zusammenführt.
@export var service_name: String = ""
@export_file("*.gd", "*.tscn") var path: String = ""
@export var required_deps: Array[String] = []
@export var optional_deps: Array[String] = []
@export_file("*.tres", "*.res") var required_data_files: Array[String] = []

## Alle Deps zusammen — für Boot-Reihenfolge/Zyklus-Erkennung/DI-Befüllung.
## required_deps/optional_deps sind NUR für "was passiert bei configure()
## wenn sie fehlt" relevant, nicht für die Reihenfolge selbst.
func all_deps() -> Array[String]:
	var result: Array[String] = required_deps.duplicate()
	for d in optional_deps:
		if d not in result:
			result.append(d)
	return result
