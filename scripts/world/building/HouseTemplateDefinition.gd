class_name HouseTemplateDefinition
extends Resource

## HouseTemplateDefinition — Datengetriebene Beschreibung eines KOMPLETTEN Hauses als Liste
## relativer Bauteile. Neues Haus = neue .tres unter data/building/houses/ + Eintrag in
## DataManifest.HOUSE_TEMPLATES. Kein Code nötig, solange nur vorhandene BUILD_PIECES verbaut
## werden (siehe BuildPieceDefinition).
##
## Baut auf demselben Fundament wie einzelne Bauteile auf (BuildGrid/BuildRegistry/
## BuildPlacementRules) — ein Haus ist einfach mehrere Bauteil-Records, die WorldBuildHandler
## als EINE atomare Operation prüft und platziert (siehe dortiger Klassenkommentar
## "Häuser/Vorlagen"): entweder passt die GESAMTE Vorlage an die Zielstelle, oder nichts wird
## gebaut und kein Material verbraucht.
##
## KOORDINATEN: jeder Eintrag in `pieces` ist relativ zu einer Anker-Zelle (0,0), in demselben
## ganzzahligen Rasterraum, den BuildGrid für Schlüssel benutzt (Zell- UND Kantenindizes teilen
## sich diesen Raum — Kante axis=0 bei (cx,cz) beginnt an derselben Gitterecke wie Zelle (cx,cz),
## siehe BuildGrid-Klassenkommentar). Beim Platzieren addiert WorldBuildHandler die Anker-Zelle
## (aus der Zielposition, wie ein Boden sie ergäbe) auf dx/dz — siehe _house_layout().
##
## Eintrag: {piece_id: String, kind: int (BuildPieceDefinition.Kind, Redundanz zur Definition
##   spart einen Def-Lookup beim Drehen), axis: int, dx: int, dz: int}
##   FLOOR:            axis ungenutzt (-1). dx/dz = Zell-Offset.
##   ROOF:             axis = Firstrichtung (0 = First entlang X, 1 = entlang Z). dx/dz = Zell-Offset.
##   STAIRS:           axis = Blickrichtung (0..3, volle Drehung). dx/dz = Zell-Offset.
##   WALL/DOOR/WINDOW: axis = Kantenachse (0/1, wie BuildGrid.wall_key). dx/dz = Kantenindex
##                      (cx,cz in derselben Konvention wie BuildGrid.wall_key/snap()).
##
##   Optional bei JEDEM Eintrag: storey (int, Default 0) = Ebenen-OFFSET zur Ebene, auf der das Haus
##   platziert wird (Wehrgang auf der Mauer, Obergeschoss, Parapet über dem Tor). Obere Ebenen folgen
##   denselben Halteregeln wie von Hand gebaut (Boden/Requisite braucht eine Wand der Ebene darunter an
##   einer Zellkante, Wand steht auf der Wand darunter oder einem Boden derselben Ebene) — die
##   Baureihenfolge sortiert deshalb erst nach Ebene, dann Boden → Wand → Dach/Treppe/Requisite.
##   Drehen lässt "storey" unberührt (es ist keine Raumrichtung).
##
## DREHEN: BuildGrid.rotate_house_piece() dreht einen Eintrag um `rot_steps` (je 90°) um die
## Anker-Zelle — dieselbe Quelle für Vorschau (Geist) UND echtes Platzieren, damit die Vorschau
## nie anders gedreht aussieht als das Ergebnis.
##
## BAUREIHENFOLGE: WorldBuildHandler._house_layout() sortiert die Einträge beim Platzieren
## automatisch in Boden → Wand/Tür/Fenster → Dach/Treppe (dieselbe Reihenfolge, in der ein
## Spieler von Hand bauen würde) — die Reihenfolge in `pieces` selbst spielt keine Rolle.

@export var id: String = ""
@export var display_name: String = ""
## Kurzer Vorschautext fürs Bau-Menü (z.B. Materialübersicht, Zimmeranzahl) — optional.
@export_multiline var description: String = ""
@export var pieces: Array[Dictionary] = []

## Materialkosten aller Teile zusammengezählt — für die Anzeige im Bau-Menü VOR dem Platzieren
## (die tatsächliche Prüfung macht WorldBuildHandler.preview_house() gegen die echten
## BuildPieceDefinition-Kosten; diese Methode braucht dieselben Definitionen als Callable,
## damit HouseTemplateDefinition selbst keine DataService-Abhängigkeit bekommt).
func total_cost(defs_cb: Callable) -> Dictionary:
	var out: Dictionary = {}
	if not defs_cb.is_valid():
		return out
	for entry: Dictionary in pieces:
		var def: BuildPieceDefinition = defs_cb.call(String(entry.get("piece_id", ""))) as BuildPieceDefinition
		if def == null:
			continue
		for item_id: String in def.cost.keys():
			out[item_id] = int(out.get(item_id, 0)) + int(def.cost[item_id])
	return out
