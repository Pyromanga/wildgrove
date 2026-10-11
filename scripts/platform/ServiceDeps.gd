# res://scripts/platform/ServiceDeps.gd
class_name ServiceDeps extends RefCounted

## ServiceDeps — Typsicherer Wrapper für den Dependency-Dictionary des DI-Systems.
##
## ADR-011: Löst das untypisierte `deps: Dictionary`-Interface ab.
## Jeder configure()-Aufruf bekommt eine ServiceDeps-Instanz statt einem Dictionary.
##
## DESIGN-ENTSCHEIDUNG:
##   require()      → Pflicht-Dep. AppLogger.fatal() wenn Key fehlt oder null —
##                    beendet das Spiel kontrolliert, in JEDEM Build-Typ (siehe
##                    AppLogger.fatal()-Doku für die Details zu assert()).
##                    Nutzen: Services die ohne diese Dep nicht funktionieren.
##   get_optional() → Optionaler Dep. Stilles null wenn fehlt — kein Fehler.
##                    Nutzen: Services die gracefully degradieren können.
##
## ENTSCHEIDUNGSBAUM require() vs get_optional():
##   Kann der Service seinen Job ohne diese Dep erledigen? (auch eingeschränkt)
##     JA  → get_optional()  (z.B. StatModifierService für Boni)
##     NEIN → require()      (z.B. SaveSystem für Persistenz)
##
## Erstellt via ServiceDeps.from_dict() — niemals direkt mit _new() instanziieren.

const LOG_CAT := "ServiceDeps"

var _data: Dictionary = {}

## Erstellt eine ServiceDeps-Instanz aus einem Dictionary.
## Einziger erlaubter Konstruktor-Weg.
static func from_dict(d: Dictionary) -> ServiceDeps:
	var sd := ServiceDeps.new()
	sd._data = d.duplicate()
	return sd

## Pflicht-Abhängigkeit. AppLogger.fatal() wenn key fehlt oder null ist.
## Ein Tippfehler oder eine fehlende Dep ist damit sofort sichtbar UND beendet
## das Spiel kontrolliert — auch im Release-Export (siehe AppLogger.fatal()-Doku:
## assert() wird dort rausoptimiert, das war vor diesem Fix ein stiller Bug-Vektor,
## der sich als "kein Fehler" angefühlt hat, weil er im Debug-Build/Editor zuverlässig
## krachte und im Export-Template einfach null zurückgab).
func require(key: String) -> Object:
	var val: Variant = _data.get(key)
	if val == null:
		AppLogger.fatal(
			"ServiceDeps.require('%s') fehlgeschlagen — Key nicht registriert oder null. " % key
			+ "Registrierte Keys: [%s]" % ", ".join(keys()),
			LOG_CAT
		)
		return null
	return val as Object

## Optionale Abhängigkeit. Gibt null zurück wenn key fehlt — kein Fehler, keine Warnung.
## Aufrufer ist verantwortlich für null-Checks.
func get_optional(key: String) -> Object:
	var val: Variant = _data.get(key)
	if val == null:
		return null
	return val as Object

## Prüft ob ein Key vorhanden und nicht null ist.
func has(key: String) -> bool:
	return _data.has(key) and _data[key] != null

## Alle registrierten Keys (sortiert für deterministisches Logging).
func keys() -> Array[String]:
	var result: Array[String] = []
	for k in _data.keys():
		result.append(str(k))
	result.sort()
	return result
