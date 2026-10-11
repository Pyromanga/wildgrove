class_name BuildModeState
extends RefCounted

## BuildModeState — ist der Spieler (an DIESEM Prozess) gerade im Bau-Modus?
##
## "Bau-Modus" = das Bau-Menü ist offen ODER ein Bauteil/Haus wird gerade platziert. Mehrere
## Quellen, ein Ergebnis: solange mindestens eine aktiv ist, gilt der Modus. Reine UI-/Komfort-
## Information (z.B. BuildPiece zeigt "Abreißen" nur dann) — kein Sicherheitsmerkmal: die Autorität
## kann den lokalen UI-Zustand eines Clients nicht kennen und prüft Abreißen weiterhin selbst
## (Reichweite/Berechtigung im WorldBuildHandler).
##
## Statisch (wie InteractionResolver): ein Prozess = ein lokaler Spieler. Der Wechsel wird über
## UIEvents.build_mode_changed gemeldet, damit BuildPieces nicht pollen müssen.

const SOURCE_PANEL := "panel"        ## Bau-Menü offen
const SOURCE_PLACING := "placing"    ## Bauteil/Haus-Geist aktiv

static var _sources: Dictionary = {}

static func is_active() -> bool:
	return not _sources.is_empty()

## Setzt/entfernt eine Quelle; meldet nur bei einer Änderung des Gesamtzustands.
static func set_source(source: String, on: bool, bus: IEventBus = null) -> void:
	var before := is_active()
	if on:
		_sources[source] = true
	else:
		_sources.erase(source)
	var after := is_active()
	if bus != null and before != after:
		bus.ui().emit_build_mode_changed(after)

## Zurücksetzen (Tests, Szenenwechsel).
static func reset() -> void:
	_sources.clear()
