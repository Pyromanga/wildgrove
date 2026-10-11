class_name BuildPieceDefinition
extends Resource

## BuildPieceDefinition — Datengetriebene Beschreibung EINES Bauteils (Boden, Wand, Dach, ...).
##
## Neues Bauteil = neue .tres unter data/building/ + Eintrag in DataManifest.BUILD_PIECES.
## Solange es ein bekannter Kind ist (FLOOR/WALL/ROOF), ist KEIN Code nötig. Ein neuer Kind
## (z.B. Tür, Treppe) braucht Regeln in BuildGrid/BuildPlacementRules und Visuals in
## BuildPiece — die Erweiterungspunkte sind dort mit "ERWEITERUNG" markiert.

## ROOF (Dach): Satteldach-Segment über EINER Zelle. Braucht Wände derselben Ebene rund um
## die Zelle als Auflager (BuildPlacementRules._check_roof) — schließt ein Bauwerk nach oben
## ab. `height` ist hier NICHT die Wandhöhe, sondern die Firsthöhe über der Traufe (Auflage-
## punkt auf den Wänden). Geometrie: BuildPieceDefinition.build_roof_mesh() (Prisma/Walmdach-
## Ersatz), First verläuft entlang lokal X, Ausrichtung über yaw wie bei Wänden.
##
## DOOR/WINDOW (Tür/Fenster-Wand): teilen sich den Schlüsselraum UND die Platzierungsregeln
## mit WALL (BuildGrid.snap()/BuildPlacementRules.check() behandeln sie wie eine Wand — sie
## sitzen auf derselben Zellkante, schließen sich also gegenseitig mit einer normalen Wand
## aus). Einziger Unterschied: die Geometrie hat eine echte Öffnung (get_door_boxes()/
## get_window_boxes()) — mehrere Einzel-Boxen (Pfosten/Sturz/Brüstung) statt einer durch-
## gehenden Wandbox, jede mit eigener Kollision, damit man tatsächlich hindurchgehen kann.
##
## STAIRS (Treppe): belegt wie FLOOR/ROOF eine ZELLE, verbindet aber Ebene n mit n+1 begehbar
## (bisher nur per Bauen erreichbar, siehe docs/terrain-and-building.md). `height` = Aufstiegs-
## höhe (sollte BuildGrid.LEVEL_HEIGHT entsprechen, wie bei Wänden). Geometrie: STAIR_STEPS
## gestapelte Stufen (build_stairs_mesh()), Kollision als einzelne Stufen-Boxen
## (BuildPiece._add_stairs) statt einer durchgehenden (zu steilen) Rampe.
##
## TARGET (freistehendes Bauteil, z.B. Zielscheibe eines Bogenschießstands oder ein Brunnen):
## belegt wie FLOOR/STAIRS eine ZELLE, braucht aber KEINEN Halt (keine Wand/kein Boden nötig —
## steht frei auf dem Gelände, wie eine Treppe auf Ebene 0, nur ohne Steigung/ohne Einebnen).
## `height` = Gesamthöhe der Konstruktion. `axis` (0..3, volle Drehung wie STAIRS) bestimmt die
## Blickrichtung. `prop_shape` (PropShape) wählt die konkrete Geometrie — EIN Kind für beliebig
## viele freistehende Requisiten (Vogelscheuche, Wegweiser, ... später einfach ein neuer
## PropShape-Wert + ein neuer build_..._mesh(), kein neuer Kind mit eigenem Schlüsselraum/
## Platzierungscode nötig). Geometrie/Kollision: build_prop_mesh() für die Sichtgeometrie
## (dispatcht auf den passenden build_..._mesh() je prop_shape), get_box_size/get_box_center
## für die grobe Hüllbox (wie bei ROOF/STAIRS).
enum Kind { FLOOR, WALL, ROOF, DOOR, WINDOW, STAIRS, TARGET }

## Welche Requisiten-Geometrie ein TARGET-Bauteil zeigt — siehe Kind.TARGET-Kommentar und
## build_prop_mesh(). STAND_DISC: Zielscheibe auf Ständer (build_target_mesh()). WELL: Brunnen
## mit Ringmauer, Pfosten, Dach und Eimer (build_well_mesh()). TOWER_ROUND/TOWER_SQUARE
## (Wunsch "Türme rund und eckig"): Turmschaft (zylindrisch bzw. quadratisch, als dünnwandiger
## Ring/Rahmen sichtbar) mit umlaufendem Zinnenkranz und eigenem Dach (Kegel- bzw. Zeltdach) —
## build_tower_mesh(). Wie WELL/STAND_DISC rein Sichtgeometrie: Kollision bleibt die grobe
## Hüllbox aus get_box_size()/get_box_center() (voller Zylinder/Quader, nicht hohl — kein
## begehbares Inneres, siehe Klassenkommentar zu ROOF/STAIRS/TARGET). `height` ist die
## Schafthöhe bis zur Zinnenbasis; Zinnen und Dach kommen zusätzlich obendrauf (siehe
## tower_total_height()).
##
## CROSS/GRAVESTONE_STELE/GRAVESTONE_SLAB (Wunsch "Kirche & Friedhof"): dieselbe Requisiten-
## Idee wie WELL/TOWER — freistehend, nur Sichtgeometrie (Kollision bleibt die grobe Hüllbox,
## wie bei allen anderen PropShape-Werten). CROSS: schlichtes Balkenkreuz (build_cross_mesh()),
## per `height` skalierbar — dieselbe .tres-Art deckt sowohl ein großes Wegkreuz als auch ein
## kleines Grabkreuz ab, nur mit anderem `height`/`color`. GRAVESTONE_STELE: stehender
## Grabstein mit gerundeter Kuppe (build_gravestone_stele_mesh()). GRAVESTONE_SLAB: liegende
## Grabplatte (build_gravestone_slab_mesh()) — hier ist `height` die Plattendicke, nicht die
## Standhöhe (die Platte liegt flach), analog zu ROOF.FLAT, wo `height` ebenfalls zweckentfremdet
## eine andere Bedeutung als bei den übrigen Formen hat.
##
## CHAPEL/SIGNPOST/LAMP_POST (Wunsch "Kapelle, Wegweiser und Straßenlaternen"): weitere Requisiten
## auf demselben Kind — kein neuer Schlüsselraum/Platzierungscode. CHAPEL: kleine Feldkapelle mit
## Satteldach, spitzbogigem Eingang, Altar und Dachreiter (build_chapel_mesh()); `height` = Wandhöhe
## bis zur Traufe, Dach + Dachreiter kommen obendrauf (chapel_total_height()). Einziges Requisit
## mit BEGEHBARER Kollision: statt der Hüllbox liefert get_prop_collision_boxes() Wände/Türpfosten/
## Sturz/Boden — Eingang bleibt frei (Eingang = lokal +Z, Drehung über axis). SIGNPOST: Pfosten mit
## drei pfeilförmigen Schildern (build_signpost_mesh()); `height` = Pfostenhöhe. LAMP_POST:
## Laternenpfahl mit leuchtender Laterne (build_lamp_post_mesh()); `height` = Gesamthöhe. Wird
## light_range > 0 gesetzt, bekommt das Bauteil zusätzlich ein OmniLight3D (siehe has_light()).
##
## Mehrere Mesh-Flächen: diese drei Shapes haben mehr als eine Surface (PropSurface) — Hauptfarbe
## `color`, Zweitfarbe `accent_color` (Dach/Schilder) und eine Leuchtfläche. Die Zuordnung Surface →
## Rolle liefert prop_surface_roles(), die fertigen Materialien build_prop_materials().
##
## WINDMILL (Wunsch "Strukturen und shapes ... große Struktur"): runder Schaft wie TOWER_ROUND
## (build_windmill_mesh() nutzt dieselbe _add_ring_wall()/_add_cone_roof() wie der Turm, nur ohne
## Zinnenkranz und einwandig statt hohl — reine Sichtgeometrie, siehe Kind.TARGET-Kommentar),
## gekrönt NICHT von einem Dach allein, sondern von einem Flügelkreuz (Nabe + vier Arme) an der
## Vorderseite. `height` ist wie bei TOWER_ROUND/TOWER_SQUARE die Schafthöhe bis zur Dachtraufe;
## Kappe und Flügel kommen obendrauf (siehe windmill_total_height()).
##
## SUNDIAL (Wunsch "... kleine gimmicks"): kleine Sonnenuhr — schlanker Sockel (Zylinder), eine
## waagrechte Zifferblatt-Scheibe obendrauf und ein schräger Schattenstab (Gnomon), letzterer über
## denselben _add_strut()-Helfer wie die Standbeine der Zielscheibe. `height` = Sockelhöhe bis zur
## Scheibenoberseite; der Gnomon ragt zusätzlich darüber hinaus (siehe sundial_total_height()).
##
## GATEHOUSE (Wunsch "Richtung Burg"): quadratischer Torturm mit einer begehbaren Durchfahrt an
## der Basis (zwei Pfeiler + Sturz, siehe build_gatehouse_mesh()) — anders als CHAPEL keine
## eigene Kollisionsgeometrie für die Durchfahrt: die Hüllbox (get_box_size()/get_box_center())
## beginnt erst OBERHALB der Durchfahrt (GATEHOUSE_PASSAGE_HEIGHT), darunter ist der Weg frei
## begehbar (bewusst einfacher als CHAPELs get_prop_collision_boxes() — reicht für einen
## Durchgang, ein Innenraum wie bei der Kapelle ist hier nicht nötig). Oberhalb des Sturzes ein
## massiver quadratischer Turmstumpf mit Zinnenkranz (dieselben _add_square_merlons()/
## _add_pyramid_roof()-Helfer wie TOWER_SQUARE) und Zeltdach. `height` = Gesamthöhe des
## Turmstumpfs bis zur Zinnenbasis (wie bei TOWER_*), muss mindestens Durchfahrt + Sturz
## aufnehmen (siehe GATEHOUSE_MIN_HEIGHT).
##
## CATAPULT (Wunsch "Richtung Burg", kleines/mittleres Gimmick): freistehende Belagerungswaffe —
## vierbeiniges Gestell (vier Streben zu einem gemeinsamen Drehpunkt, dieselbe _add_strut()-
## Technik wie die Standbeine der Zielscheibe) mit Wurfarm (Schleuderkorb vorn) und Gegengewicht
## (hinten), siehe build_catapult_mesh(). `height` skaliert das Gestell; Wurfarm/Gegengewicht
## ragen zusätzlich darüber hinaus (siehe catapult_total_height()).
## HANDWERKS-REQUISITEN (Wunsch "mehr Strukturen, was es im Mittelalter so an Berufen gab — klein
## anfangen, daraus große Strukturen bauen"): vier weitere PropShape-Werte (neben FURNACE/ANVIL, den Schmiede-Stationen) auf demselben Kind TARGET
## (kein neuer Kind/Platzierungscode, siehe is_craft_prop()). Bei ALLEN gilt: `height` = GESAMTHÖHE
## der Requisite bis zum höchsten Punkt (nach unten durch craft_prop_height() auf eine Mindesthöhe
## begrenzt), die Hüllbox kommt aus craft_prop_footprint() + craft_prop_height(), Vorderseite = lokal
## +Z (Drehung über axis, wie Kapelle/Katapult). Alle Meshes bleiben innerhalb ihres Footprints
## (Test test_craft_props_mesh_stays_inside_footprint).
## BARREL (Böttcher/Brauer/Schankwirt): bauchiges Fass mit zwei Reifen. MAIN = Dauben, ACCENT = Reifen.
## MARKET_STALL (Händler): Marktstand mit Tresen, Waren und schrägem Stoffdach. MAIN = Holz/Waren,
##   ACCENT = Stoffdach (zwei Farbvarianten nur als Daten: market_stall_red / market_stall_blue).
## BAKE_OVEN (Bäcker): gemauerte Backofenkuppel auf Sockel, Rauchabzug, glühende Ofenöffnung.
##   MAIN = Stein, GLOW = Glut.
## WORKBENCH (Zimmermann/Tischler): Werkbank mit Schraubstock und Hammer. MAIN = Holz, ACCENT = Eisenwerkzeug.
## KLEINIGKEITEN + GRUNDFORMEN (Wunsch "mehr Kleinigkeiten ... ganze Dörfer, Städte und Königreiche füllen"),
## gleiche Regeln wie oben (is_craft_prop):
## CRATE Kistenstapel (MAIN/ACCENT), SACKS Sackstapel (MAIN/ACCENT), BENCH Bank mit Lehne (nur MAIN),
## TABLE Tisch mit zwei Hockern (MAIN/ACCENT = Hocker), CART Handkarren mit Rädern + optionaler Ladung
## (MAIN/ACCENT = Räder), BANNER Fahnenmast (MAIN/ACCENT = Tuch, Farbvarianten nur Daten), PILLAR Säule
## für Tore/Hallen/Kolonnaden (nur MAIN, Stein oder Holz über die Farbe), FIREPIT Feuerstelle
## (MAIN = Steinring, ACCENT = Scheite, GLOW = Glut/Flamme, KEIN Licht).
## ACHTUNG: neue Werte NUR hinten anhängen — die .tres speichern den Zahlenwert (prop_shape = n).
enum PropShape { STAND_DISC, WELL, TOWER_ROUND, TOWER_SQUARE, CROSS, GRAVESTONE_STELE, GRAVESTONE_SLAB, CHAPEL, SIGNPOST, LAMP_POST, WINDMILL, SUNDIAL, GATEHOUSE, CATAPULT, FURNACE, ANVIL, BARREL, MARKET_STALL, BAKE_OVEN, WORKBENCH, CRATE, SACKS, BENCH, TABLE, CART, BANNER, PILLAR, FIREPIT, TROUGH, WOODPILE, GARDEN_BED, SCARECROW, WEAPON_RACK }

## Rolle einer Mesh-Fläche (Surface) eines TARGET-Requisits — siehe prop_surface_roles(). MAIN:
## `color` (Mauern, Pfosten, Gestell). ACCENT: `accent_color` (Dach, Schilder). GLOW: warme
## Leuchtfläche (PROP_GLOW_COLOR, emissiv) für Laternenglas, Kapellenfenster und Kerzen.
enum PropSurface { MAIN, ACCENT, GLOW }

## Dachform eines ROOF-Bauteils (Wunsch "Dächer in mehr Formen") — siehe build_roof_mesh().
## GABLE (Satteldach, bisheriges Verhalten): First entlang lokal X, zwei geneigte Flächen +
##   zwei Giebeldreiecke. HIP (Walmdach): First verkürzt sich zu einem Punkt/einer Linie
##   mittig über der Zelle, alle vier Traufseiten geneigt, kein Giebeldreieck. PYRAMID
##   (Zeltdach): wie HIP, aber First auf einen einzelnen Punkt in der Mitte reduziert (First-
##   länge 0) — eine echte Pyramide, unabhängig von axis. FLAT (Flachdach): eine ebene Platte
##   auf Traufhöhe + eine dünne Attika-Kante, `height` wird dabei ignoriert (siehe
##   FLAT_ROOF_THICKNESS). `roof_ridge` (0..1, nur GABLE/HIP) macht die Form "adjustierbar":
##   0 = First auf voller Zellbreite (reines Satteldach), 1 = First auf einen Punkt geschrumpft
##   (= Walmdach/Pyramide) — Zwischenwerte ergeben einen verkürzten First (asymmetrisches Walm-
##   Satteldach-Mischdach), ohne dass GABLE/HIP eigene Sonderfälle bräuchten.
enum RoofShape { GABLE, HIP, PYRAMID, FLAT }

## Form eines STAIRS-Bauteils (Wunsch "Wendeltreppen, sollen in Große Häuser & Türme passen") —
## siehe build_stairs_mesh(). STRAIGHT (bisheriges Verhalten): gerade Stufenflucht entlang lokal
## Z, siehe Kind.STAIRS-Kommentar. SPIRAL: SPIRAL_TURNS volle Umdrehungen um einen Mittelpfosten,
## Grundfläche bleibt trotzdem EINE Zelle (wie bei STRAIGHT) — passt also ins selbe Rundtürme/
## Turmschaft-Raster (TOWER_ROUND/TOWER_SQUARE) und eignet sich für Etagen in Türmen/großen
## Häusern, wo eine gerade Treppe zu viel Grundfläche frisst. Bleibt derselbe Kind (STAIRS):
## Schlüsselraum, Rotation (volle 4-Schritt-Drehung über axis) und Auflagerregeln
## (BuildPlacementRules) sind identisch zu STRAIGHT, nur die Geometrie unterscheidet sich.
enum StairsShape { STRAIGHT, SPIRAL }

## Form der Öffnung eines DOOR/WINDOW-Bauteils (Wunsch "grundlegende Shapes für Torbögen usw.") —
## siehe get_door_boxes()/get_window_boxes(). RECT (bisheriges Verhalten): Pfosten + gerader Sturz.
## ARCH: Rundbogen — die Öffnung geht unterhalb des Scheitels (`opening_height`) in einen Halb-
## kreis (bzw. eine Halbellipse, wenn die Höhe dafür nicht reicht) über. Der Bogen wird aus
## ARCH_STEPS gestuften Boxen angenähert: Optik UND Kollision kommen aus derselben Box-Liste wie
## bei der Tür (BuildPiece._add_framed / BuildGhost), es gibt keine eigene Mesh-Pipeline. Breite
## und Scheitelhöhe sind Daten (`opening_width`, `opening_height`) — Haustür, Fenster und
## Stadttor sind nur verschiedene .tres.
enum OpeningShape { RECT, ARCH }

## Oberkante eines WALL-Bauteils (Wunsch "Stadtmauern"). PLAIN (bisheriges Verhalten): glatte Box.
## CRENELLATED: Zinnenkranz — unten durchgehende Mauer, die oberen WALL_MERLON_HEIGHT m wechseln
## zwischen Zinne und Lücke (an den Zellkanten halbe Zinnen, damit zwei Segmente nahtlos eine
## ganze ergeben). Höhe/Auflager/Platzierung unverändert: die Zinnen liegen INNERHALB von `height`.
enum WallTop { PLAIN, CRENELLATED }

## Stufen des angenäherten Rundbogens (OpeningShape.ARCH) und Höhe des Zinnenkranzes.
## Torflügel eines DOOR-Bauteils (Wunsch "Torflügel"): NONE = offener Durchgang (bisheriges Verhalten),
## OPEN = beide Flügel nach außen (lokal +Z) aufgeschwenkt, flach neben dem Durchgang (die Öffnung
## bleibt begehbar), CLOSED = Flügel füllen die Öffnung aus (sperrt den Durchgang, bis das Bauteil
## abgerissen wird — es gibt noch keine bewegliche Tür). Gilt für RECT UND ARCH, nicht für Fenster.
## Optik und Kollision kommen wie beim Rahmen aus derselben Box-Liste (get_door_boxes()).
enum LeafState { NONE, OPEN, CLOSED }

const LEAF_THICKNESS: float = 0.07
const LEAF_CLOSED_THICKNESS: float = 0.12
const ARCH_STEPS: int = 5
const WALL_MERLON_HEIGHT: float = 0.45

## Breite der Durchgangsöffnung einer Tür, mittig auf der Zellkante. Rest der Wandfläche
## (Pfosten links/rechts + Sturz darüber) bleibt fest — siehe get_door_boxes().
const DOOR_WIDTH: float = 1.1
## Höhe der Türöffnung ab der Basis (y=0). Bei height <= DOOR_OPEN_HEIGHT entfällt der Sturz
## (Tür so hoch wie die Wand).
const DOOR_OPEN_HEIGHT: float = 2.0

## Breite/Höhe der Fensteröffnung sowie Brüstungshöhe ab der Basis — siehe get_window_boxes().
const WINDOW_WIDTH: float = 1.1
const WINDOW_SILL: float = 0.9
const WINDOW_OPEN_HEIGHT: float = 1.0

## Anzahl Stufen einer Treppe. Kollision (BuildPiece._add_stairs) UND Sichtgeometrie
## (build_stairs_mesh) teilen sich diese Konstante, damit Optik und begehbare Fläche
## übereinstimmen.
const STAIR_STEPS: int = 8

## Maße einer Wendeltreppe (StairsShape.SPIRAL) — siehe build_spiral_stairs_mesh(). SPIRAL_TURNS
## = Umdrehungen über die volle Aufstiegshöhe (0.75 = 270°, wie bei echten engen Wendeltreppen).
## SPIRAL_MARGIN hält die Stufen innerhalb der Zelle (Außenradius = cell/2 - Margin), damit die
## Treppe nicht in Nachbarzellen/-Bauteile hineinragt. SPIRAL_NEWEL_RADIUS ist sowohl der
## sichtbare Mittelpfosten als auch der Innenradius der Stufen (Wunsch: begehbar UM den Pfosten
## herum, nicht durch ihn hindurch).
const SPIRAL_TURNS: float = 0.75
const SPIRAL_MARGIN: float = 0.15
const SPIRAL_NEWEL_RADIUS: float = 0.14
const SPIRAL_NEWEL_SEGMENTS: int = 10

## Radius der Zielscheibe eines TARGET-Bauteils (PropShape.STAND_DISC) sowie Segmentanzahl des
## Kreis-Fächers sowie Pfostendicke — siehe build_target_mesh().
const TARGET_RADIUS: float = 0.55
const TARGET_SEGMENTS: int = 16
const TARGET_POST_HALF: float = 0.06

## Maße eines Brunnens (PropShape.WELL) — siehe build_well_mesh(). Ringradius, Segmentanzahl
## der zylindrischen Ringmauer, Pfostendicke sowie halbe Dachtiefe (First entlang lokal Z).
const WELL_RADIUS: float = 0.65
const WELL_RING_SEGMENTS: int = 14
const WELL_POST_HALF: float = 0.06
const WELL_ROOF_HALF_DEPTH: float = 0.55
const WELL_BUCKET_HALF: float = 0.09

## Maße eines Kreuzes (PropShape.CROSS) — siehe build_cross_mesh(). Balkendicke (halbe
## Kantenlänge des quadratischen Querschnitts), halbe Länge des Querbalkens sowie dessen Position
## als Anteil der Gesamthöhe (0 = am Boden, 1 = an der Spitze) — ein Wegkreuz und ein kleines
## Grabkreuz teilen sich dieselbe Geometrie, nur `height` unterscheidet sich (siehe PropShape-
## Kommentar).
const CROSS_POST_HALF: float = 0.05
const CROSS_ARM_HALF_LENGTH: float = 0.32
const CROSS_ARM_Y_RATIO: float = 0.68

## Maße eines stehenden Grabsteins (PropShape.GRAVESTONE_STELE) — siehe
## build_gravestone_stele_mesh(). Breite/Dicke des geraden Schafts sowie Segmentanzahl der
## gerundeten Kuppe (Halbkreisbogen, Radius = halbe Breite) obendrauf.
const GRAVESTONE_WIDTH: float = 0.5
const GRAVESTONE_THICKNESS: float = 0.09
const GRAVESTONE_ARCH_SEGMENTS: int = 8

## Maße einer liegenden Grabplatte (PropShape.GRAVESTONE_SLAB) — siehe
## build_gravestone_slab_mesh(). Breite/Länge der Platte; die Dicke kommt aus `height` (siehe
## PropShape-Kommentar).
const GRAVESTONE_SLAB_WIDTH: float = 0.7
const GRAVESTONE_SLAB_LENGTH: float = 1.5

## Leuchtfläche (PropSurface.GLOW) und Lichtquelle (OmniLight3D bei light_range > 0): eine warme
## Lampenfarbe für alle Requisiten, damit Laterne, Kapellenfenster und Kerzen zusammenpassen.
const PROP_GLOW_COLOR: Color = Color(1.0, 0.78, 0.40)
const PROP_GLOW_ENERGY: float = 1.6
const PROP_LIGHT_ENERGY: float = 1.1

## Maße einer Kapelle (PropShape.CHAPEL) — siehe build_chapel_mesh(). Grundfläche 2,0 × 2,6 m
## (Halbmaße; Tiefe ragt je 0,3 m über die Zelle hinaus, wie der Turm), Wanddicke, Fundamenttiefe
## unter y=0 (versteckt Lücken am Hang, wie skirt bei Wänden), Oberkante der Bodenplatte,
## Mindest-Wandhöhe, Türöffnung (halbe Breite + Höhe des Spitzbogens über dem geraden Teil),
## Dachaufbau (Firsthöhe über der Traufe, Überstand seitlich/vorn-hinten, Plattendicke) sowie der
## Dachreiter (Lage auf dem First, halbe Kantenlänge, Pfostenstärke, Höhen von Glockenstuhl/Haube/
## Kreuz — zusammen CHAPEL_TURRET_HEIGHT über dem First).
const CHAPEL_HALF_WIDTH: float = 1.0
const CHAPEL_HALF_DEPTH: float = 1.3
const CHAPEL_WALL_THICKNESS: float = 0.2
const CHAPEL_FOUNDATION: float = 0.6
const CHAPEL_FLOOR_TOP: float = 0.06
const CHAPEL_MIN_WALL_HEIGHT: float = 1.8
const CHAPEL_DOOR_HALF_WIDTH: float = 0.45
const CHAPEL_DOOR_ARCH_RISE: float = 0.4
const CHAPEL_ROOF_RISE: float = 1.0
const CHAPEL_ROOF_OVERHANG: float = 0.18
const CHAPEL_ROOF_OVERHANG_Z: float = 0.25
const CHAPEL_ROOF_THICKNESS: float = 0.09
const CHAPEL_TURRET_Z: float = 0.6
const CHAPEL_TURRET_HALF: float = 0.2
const CHAPEL_TURRET_POST_HALF: float = 0.04
const CHAPEL_TURRET_POST_HEIGHT: float = 0.55
const CHAPEL_TURRET_CAP_HEIGHT: float = 0.4
const CHAPEL_TURRET_CROSS_HEIGHT: float = 0.3
const CHAPEL_TURRET_HEIGHT: float = CHAPEL_TURRET_POST_HEIGHT + CHAPEL_TURRET_CAP_HEIGHT + CHAPEL_TURRET_CROSS_HEIGHT

## Maße eines Wegweisers (PropShape.SIGNPOST) — siehe build_signpost_mesh(). Mindesthöhe, halbe
## Pfostenstärke, Sockel (halbe Kante, Oberkante) und Eingrabtiefe unter y=0, Schildmaße (halbe
## Höhe, Länge der Pfeilspitze, halbe Dicke) sowie die Schilder selbst als
## Vector4(Abstand von der Pfostenspitze, Richtung +1/-1 entlang lokal X, Drehung um Y in Grad,
## Länge) — von oben nach unten. Hüllbox (Kollision) umfasst nur den Pfosten: die Schilder hängen
## auf Kopfhöhe darüber, man geht daran vorbei.
const SIGNPOST_MIN_HEIGHT: float = 1.6
const SIGNPOST_POST_HALF: float = 0.07
const SIGNPOST_FOOT_HALF: float = 0.16
const SIGNPOST_FOOT_TOP: float = 0.1
const SIGNPOST_BURY: float = 0.3
const SIGNPOST_BOARD_HALF_HEIGHT: float = 0.12
const SIGNPOST_BOARD_TIP: float = 0.2
const SIGNPOST_BOARD_HALF_THICKNESS: float = 0.025
const SIGNPOST_HULL: float = 0.36
const SIGNPOST_BOARDS := [
	Vector4(0.32, 1.0, 10.0, 1.0),
	Vector4(0.64, -1.0, -16.0, 0.9),
	Vector4(0.96, 1.0, -58.0, 0.8),
]

## Maße einer Straßenlaterne (PropShape.LAMP_POST) — siehe build_lamp_post_mesh(). Mindesthöhe,
## Höhe der Laterne samt Haube (LANTERN_SPAN, von der Unterkante bis zur Spitze), Dicke der
## Bodenplatte der Laterne, Abstand der Glasoberkante zur Spitze (Haube + Zierspitze), halbe Kante
## des Fußes sowie Kantenlänge der Hüllbox. Glas-Ober-/Unterkante kommen aus lamp_glass_bounds() —
## einzige Quelle für Mesh UND Lichtposition.
const LAMP_MIN_HEIGHT: float = 1.6
const LAMP_LANTERN_SPAN: float = 0.85
const LAMP_BASE_PLATE: float = 0.05
const LAMP_CAP_DROP: float = 0.32
const LAMP_FOOT_HALF: float = 0.17
const LAMP_HULL: float = 0.4

## Maße eines Turms (PropShape.TOWER_ROUND/TOWER_SQUARE) — siehe build_tower_mesh().
## Radius (rund) bzw. halbe Kantenlänge (eckig) des Schafts, Wanddicke (Schaft ist ein Ring/
## Rahmen, kein Vollzylinder/-quader — man soll perspektivisch "hineinschauen" können, ohne
## dass Kollision o.ä. nötig wird), Segmentanzahl des runden Schafts, Zinnenanzahl/-höhe/-anteil
## (Anteil der Umfangs-/Kantenlänge, den eine einzelne Zinne einnimmt) sowie das Verhältnis von
## Dachhöhe zu Schafthöhe (Dach kommt obendrauf, siehe PropShape-Kommentar).
const TOWER_RADIUS: float = 1.1
const TOWER_WALL_THICKNESS: float = 0.22
const TOWER_ROUND_SEGMENTS: int = 16
const TOWER_MERLON_COUNT: int = 8
const TOWER_MERLON_HEIGHT: float = 0.4
const TOWER_MERLON_DUTY: float = 0.55
const TOWER_ROOF_RATIO: float = 0.55

## Maße einer Windmühle (PropShape.WINDMILL) — siehe build_windmill_mesh(). Schaftradius/
## -segmentanzahl (schlanker als der Turm — kein Wehrgang nötig), Verhältnis Kappenhöhe zu
## Schafthöhe (wie TOWER_ROOF_RATIO), Höhe der Nabe (Anteil der Schafthöhe, an der Rand die
## Flügel sitzen — nahe der Spitze, wie bei einer echten Bockwindmühle), halbe Nabenkante,
## Flügellänge (Mitte bis Spitze je Arm), halbe Flügelbreite/-dicke.
const WINDMILL_RADIUS: float = 0.7
const WINDMILL_SEGMENTS: int = 14
const WINDMILL_CAP_RATIO: float = 0.4
const WINDMILL_HUB_Y_RATIO: float = 0.88
const WINDMILL_HUB_HALF: float = 0.12
const WINDMILL_BLADE_LENGTH: float = 1.3
const WINDMILL_BLADE_HALF_WIDTH: float = 0.16
const WINDMILL_BLADE_HALF_THICK: float = 0.04

## Maße einer Sonnenuhr (PropShape.SUNDIAL) — siehe build_sundial_mesh(). Sockelradius/
## -segmentanzahl, Radius der Zifferblatt-Scheibe, halbe Gnomon-Dicke sowie dessen Länge als
## Anteil des Scheibenradius.
const SUNDIAL_BASE_RADIUS: float = 0.2
const SUNDIAL_BASE_SEGMENTS: int = 10
const SUNDIAL_DIAL_RADIUS: float = 0.34
const SUNDIAL_DIAL_SEGMENTS: int = 16
const SUNDIAL_GNOMON_HALF_THICK: float = 0.025
const SUNDIAL_GNOMON_LENGTH_RATIO: float = 0.8

## Maße eines Torturms (PropShape.GATEHOUSE) — siehe build_gatehouse_mesh(). Halbe Kantenlänge
## des Turms (füllt eine ganze Zellbreite, wie die Zellkante einer Mauer — damit er eine Lücke
## in einer Mauerflucht plausibel ausfüllt), halbe Breite der Durchfahrtsöffnung, deren
## Durchgangshöhe (Kollisionsfreie Zone darunter, siehe Kind.TARGET-Kommentar zu GATEHOUSE) sowie
## die Dicke des Sturzbalkens über der Durchfahrt. GATEHOUSE_MIN_HEIGHT stellt sicher, dass
## Durchfahrt + Sturz immer Platz im Gesamtbauwerk finden, auch bei sehr niedrigem `height`.
const GATEHOUSE_HALF_WIDTH: float = 1.0
const GATEHOUSE_PASSAGE_HALF_WIDTH: float = 0.55
const GATEHOUSE_PASSAGE_HEIGHT: float = 2.2
const GATEHOUSE_LINTEL_THICKNESS: float = 0.3
const GATEHOUSE_MIN_HEIGHT: float = GATEHOUSE_PASSAGE_HEIGHT + GATEHOUSE_LINTEL_THICKNESS + 0.5

## Maße einer Belagerungswaffe (PropShape.CATAPULT) — siehe build_catapult_mesh(). Halbe
## Gestellbreite (Abstand der vier Standbeine von der Mitte), Balkendicke der Streben/Achse,
## Länge von Wurfarm bzw. Gegengewichtsarm ab dem Drehpunkt sowie halbe Kantenlänge von
## Schleuderkorb- bzw. Gegengewichtsblock an den jeweiligen Armspitzen.
const CATAPULT_STAND_HALF_WIDTH: float = 0.45
const CATAPULT_BEAM_HALF: float = 0.05
const CATAPULT_ARM_LENGTH: float = 1.0
const CATAPULT_BUCKET_HALF: float = 0.12
const CATAPULT_COUNTERWEIGHT_HALF: float = 0.14

## Maße der Schmiede-Stationen (PropShape.FURNACE / PropShape.ANVIL) — siehe build_furnace_mesh()
## und build_anvil_mesh(). Hochofen: halbe Breite/Tiefe des Steinkörpers, Anteil der Körperhöhe an
## `height` (darüber der Schornstein), halbe Schornsteinkante, Feueröffnung (halbe Breite, Unter-/
## Oberkante als Anteil von `height`). Amboss: halbe Länge der Bahn (ohne Horn), halbe Tiefe der Bahn,
## halbe Kantenlänge des Holzstumpfs, Länge des Horns. Front = lokal +Z (Hochofen) bzw. Horn = lokal +X.
const FURNACE_HALF_WIDTH: float = 0.55
const FURNACE_HALF_DEPTH: float = 0.5
const FURNACE_BODY_RATIO: float = 0.62
const FURNACE_CHIMNEY_HALF: float = 0.2
const FURNACE_MOUTH_HALF_WIDTH: float = 0.24
const FURNACE_MOUTH_LOW_RATIO: float = 0.14
const FURNACE_MOUTH_HIGH_RATIO: float = 0.36
const FURNACE_MIN_HEIGHT: float = 1.2
const ANVIL_FACE_HALF_LENGTH: float = 0.3
const ANVIL_FACE_HALF_DEPTH: float = 0.14
const ANVIL_STUMP_HALF: float = 0.27
const ANVIL_HORN_LENGTH: float = 0.26
const ANVIL_MIN_HEIGHT: float = 0.6

## Handwerks-Requisiten (PropShape.BARREL ... WORKBENCH) — siehe craft_prop_height()/
## craft_prop_footprint() und die build_..._mesh()-Funktionen. Mindesthöhen verhindern, dass ein
## zu kleines `height` die Geometrie ineinanderschiebt (Hüllbox und Mesh lesen beide dieselbe,
## begrenzte Höhe). Rest: Maße einzelner Rundteile (Fass, Backofenkuppel).
const CRAFT_BARREL_MIN_HEIGHT: float = 0.6
const CRAFT_STALL_MIN_HEIGHT: float = 1.8
const CRAFT_OVEN_MIN_HEIGHT: float = 1.2
const CRAFT_BENCH_MIN_HEIGHT: float = 0.8
const BARREL_MID_RADIUS: float = 0.34
const BARREL_END_RADIUS: float = 0.27
const BARREL_SLICES: int = 6
const BARREL_SEGMENTS: int = 10
const BARREL_HOOP_GROW: float = 0.012
const OVEN_DOME_RADIUS: float = 0.5
const OVEN_PLINTH_HEIGHT: float = 0.35
const OVEN_DOME_SLICES: int = 5
const OVEN_DOME_SEGMENTS: int = 12
const CRAFT_CRATE_MIN_HEIGHT: float = 0.5
const CRAFT_SACKS_MIN_HEIGHT: float = 0.5
const CRAFT_BENCH2_MIN_HEIGHT: float = 0.7
const CRAFT_TABLE_MIN_HEIGHT: float = 0.7
const CRAFT_CART_MIN_HEIGHT: float = 0.72
const CRAFT_BANNER_MIN_HEIGHT: float = 1.6
const CRAFT_PILLAR_MIN_HEIGHT: float = 1.2
const CRAFT_FIREPIT_MIN_HEIGHT: float = 0.45
## Hof-/Wehr-Requisiten (Wunsch "Strukturen und Gebäude weiter ausbauen"): Stall, Garten, Wehrhof.
const CRAFT_TROUGH_MIN_HEIGHT: float = 0.5
const CRAFT_WOODPILE_MIN_HEIGHT: float = 0.75
const CRAFT_GARDEN_BED_MIN_HEIGHT: float = 0.45
const CRAFT_SCARECROW_MIN_HEIGHT: float = 1.8
const CRAFT_WEAPON_RACK_MIN_HEIGHT: float = 1.5
const PILLAR_SEGMENTS: int = 10
const FIREPIT_RADIUS: float = 0.5
const FIREPIT_SEGMENTS: int = 10
const CART_WHEEL_RADIUS: float = 0.3
const CART_WHEEL_SEGMENTS: int = 10

## Dicke der Platte + Attika-Höhe eines FLAT-Dachs (RoofShape.FLAT) — hier ist `height` nicht
## die Firsthöhe (die gibt es bei einem Flachdach nicht), sondern wird ignoriert; siehe
## build_flat_roof_mesh().
const FLAT_ROOF_THICKNESS: float = 0.12
const FLAT_ROOF_PARAPET: float = 0.25

@export var id: String = ""
@export var display_name: String = ""
@export var kind: int = Kind.FLOOR
@export var color: Color = Color(0.55, 0.40, 0.25)

## Nur TARGET: welche Requisiten-Geometrie (PropShape) — siehe Kind.TARGET-Kommentar.
@export var prop_shape: int = PropShape.STAND_DISC

## Nur TARGET mit mehreren Flächen (CHAPEL: Dach, SIGNPOST: Schilder): Zweitfarbe der Surface
## PropSurface.ACCENT — siehe prop_surface_roles(). Bestehende .tres ohne dieses Feld behalten
## das Verhalten (einflächige Shapes ignorieren es).
@export var accent_color: Color = Color(0.33, 0.22, 0.15)

## Nur TARGET: Reichweite (Meter) eines OmniLight3D an der Leuchtfläche — 0 = kein Licht (Standard,
## bestehende .tres unverändert). Nur sinnvoll für Shapes mit PropSurface.GLOW (LAMP_POST).
@export var light_range: float = 0.0

## STRUKTUR-NUTZUNG (Brunnen: Wasser schöpfen, später z.B. Mühle: Korn mahlen): optionale Aktion,
## die BuildPiece als zusätzliche Interaktion anbietet. Leeres `use_label` (Standard) = keine —
## alle bestehenden .tres unverändert. Ablauf siehe StructureUse: die Autorität verbraucht
## `use_consumes` ({item_id: Menge}) und gibt `use_gives` ({item_id: Menge}); der Client schickt
## nie, WAS er bekommt. `use_cooldown` (Sekunden, je Spieler und Bauteil) bremst Spam-Requests.
## `use_animation` wählt eine rein optische Animation während der Aktion (USE_ANIM_*).
@export var use_label: String = ""
@export var use_duration: float = 1.5
@export var use_consumes: Dictionary = {}
@export var use_gives: Dictionary = {}
@export var use_cooldown: float = 2.0
@export var use_animation: String = ""

## Bekannte Nutz-Animationen (use_animation). Brunnen: Eimer am Seil taucht ein und kommt gefüllt hoch.
const USE_ANIM_WELL_BUCKET := "well_bucket"

## Nur ROOF: welche Dachform (RoofShape) — siehe RoofShape-Kommentar. Default GABLE erhält das
## bisherige Verhalten bestehender Dach-.tres ohne dieses Feld (fehlt = 0 = GABLE).
@export var roof_shape: int = RoofShape.GABLE

## Nur ROOF mit roof_shape=HIP: wie weit der First zu einem Punkt schrumpft (0 = First auf
## voller Zellbreite/reines Satteldach, 1 = First auf einen Punkt geschrumpft/reines Walmdach).
## Der "adjustierende" Regler zwischen Sattel- und Walmdach, siehe RoofShape-Kommentar.
@export_range(0.0, 1.0) var roof_ridge: float = 1.0

## Nur STAIRS: welche Form (StairsShape) — siehe StairsShape-Kommentar. Default STRAIGHT erhält
## das bisherige Verhalten bestehender Treppen-.tres ohne dieses Feld (fehlt = 0 = STRAIGHT).
@export var stairs_shape: int = StairsShape.STRAIGHT

## Nur DOOR/WINDOW: Form der Öffnung (OpeningShape). Default RECT = bisheriges Verhalten.
@export var opening_shape: int = OpeningShape.RECT

## Nur DOOR/WINDOW: lichte Breite der Öffnung in m (0 = Standard DOOR_WIDTH/WINDOW_WIDTH).
@export var opening_width: float = 0.0

## Nur DOOR/WINDOW: Oberkante der Öffnung ab der Basis in m — bei ARCH der Bogenscheitel
## (0 = Standard DOOR_OPEN_HEIGHT bzw. Brüstung + WINDOW_OPEN_HEIGHT).
@export var opening_height: float = 0.0

## Nur WALL: Wandoberkante (WallTop). Default PLAIN = bisheriges Verhalten.
@export var wall_top: int = WallTop.PLAIN

## Nur DOOR: Torflügel (LeafState). Default NONE = bisheriges Verhalten (offener Durchgang).
@export var leaf_state: int = LeafState.NONE

## FLOOR: Dicke der Platte (Oberkante = Bauhöhe).
## WALL:  sichtbare Höhe über der Basis.
@export var height: float = 0.3

## Nur WALL: Wanddicke in Metern.
@export var thickness: float = 0.2

## Wie tief das Bauteil UNTER seine Basis reicht. Versteckt Lücken zwischen Bauteil und
## unebenem Gelände (Boden ist nicht plan, Wände sind es). Rein optisch/kollisionsseitig.
@export var skirt: float = 0.8

## Baukosten: { item_id: Anzahl }. Werden beim Bauen abgezogen und beim Abreißen
## zu refund_ratio zurückgegeben (1.0 = vollständig).
@export var cost: Dictionary = {}
@export_range(0.0, 1.0) var refund_ratio: float = 1.0

## Wunsch "Quest schaltet Spawner-Grabstein per Toggle im Baumenü frei":
## generischer, wiederverwendbarer Freischalt-Haken — NICHT gravestone-
## spezifisch, jedes künftige Bauteil kann darüber an eine Quest gekoppelt
## werden. Leer (Default) = immer verfügbar, unverändertes Alt-Verhalten für
## alle bestehenden Bauteile. Ist das Feld gesetzt, prüft BuildPanelController.
## build_entries() vor der Aufnahme in die Katalog-Liste per QuestService.
## is_quest_completed(requires_quest_id, player_id) — bewusst KEIN separates
## "unlocks"-Flag/Reward-System: der Quest-Abschluss-Status ist bereits die
## eine Wahrheitsquelle, eine zweite (z.B. ein Inventar-Flag, das der Reward
## setzt) könnte auseinanderlaufen (Spielstand ohne dieses Flag aus einer
## alten Version, Admin setzt Quest zurück ohne das Flag zu kennen, ...).
## "Per Toggle im Baumenü": das IST der Toggle — vor Quest-Abschluss taucht
## der Eintrag im Baumenü schlicht nicht auf, danach schon (siehe
## BuildPanelController.build_entries()), kein zusätzlicher UI-Schalter nötig.
@export var requires_quest_id: String = ""

## Wunsch "Spieler-Spawner-Bauteile" (Grabstein -> Skelett, Lagerfeuer ->
## Goblin): unabhängig von requires_quest_id (auch ein sofort verfügbares
## Bauteil könnte theoretisch ein Spawner sein) — meldet das platzierte
## BuildPiece bei AmbientSpawnService an/ab (siehe BuildPiece.gd
## on_spawn()/on_despawn()), MIT diesem type_id als zu spawnendem
## Entity-Typ. Leer (Default) = kein Spawner, unverändertes Alt-Verhalten
## für alle rein dekorativen Bauteile. String statt bool, weil
## AmbientSpawnService generisch ist (siehe dortiger Klassenkommentar
## "HISTORIE") — welcher Gegnertyp nachwächst, ist reine Konfiguration je
## .tres, kein Sonderfall im Code.
@export var ambient_spawn_type_id: String = ""

## Schmiede-Station (Schmelzen & Schmieden, SmithingRecipe.STATIONS): "furnace" (Hochofen) oder
## "anvil" (Amboss). Leer (Default) = keine Station, unverändertes Alt-Verhalten. Nur sinnvoll
## für Kind.TARGET-Bauteile: BuildPiece hängt dann neben "Abreißen" eine zweite Aktion "Benutzen"
## an, die das Schmiede-Panel für genau diese Station öffnet (UIEvents.smithing_opened) und der
## Autorität den Zugang meldet (SmithingEvents.smithing_station_used). Die Rezepte selbst
## stehen in data/smithing_recipes/ — die Station entscheidet NUR, welche davon angeboten werden.
@export var station_kind: String = ""

func is_floor() -> bool:
	return kind == Kind.FLOOR

## Ist dieses Bauteil eine Schmiede-Station (Hochofen/Amboss)?
func has_use() -> bool:
	return is_target() and not use_label.is_empty()

## Hat das Bauteil eine bewegte Eimer-Animation (Brunnen)? Dann baut BuildPiece Eimer + Seil als
## eigene Nodes statt als Teil des statischen Meshes (siehe build_well_mesh(with_bucket=false)).
func has_well_bucket_animation() -> bool:
	return is_target() and prop_shape == PropShape.WELL and use_animation == USE_ANIM_WELL_BUCKET

func is_station() -> bool:
	return not station_kind.is_empty()

func is_wall() -> bool:
	return kind == Kind.WALL

func is_roof() -> bool:
	return kind == Kind.ROOF

func is_door() -> bool:
	return kind == Kind.DOOR

func is_window() -> bool:
	return kind == Kind.WINDOW

func is_stairs() -> bool:
	return kind == Kind.STAIRS

func is_target() -> bool:
	return kind == Kind.TARGET

## Wandartig = belegt eine Zellkante wie WALL und benutzt dieselben Platzierungsregeln
## (BuildPlacementRules) — WALL, DOOR, WINDOW.
func is_wall_like() -> bool:
	return kind == Kind.WALL or kind == Kind.DOOR or kind == Kind.WINDOW

## GEOMETRIE — einzige Quelle für Bauteil (BuildPiece) UND Geist (Baumodus), damit die
## Vorschau nie anders aussieht als das fertige Bauteil. `cell` = BuildGrid.CELL (als Parameter,
## damit diese Ressource keine Abhängigkeit auf BuildGrid bekommt).
## Ursprung = Basis-Mittelpunkt (Oberkante bei Böden, Standfläche bei Wänden), +Y oben,
## Wandlänge entlang lokal X (Ausrichtung über yaw).
func get_box_size(cell: float) -> Vector3:
	var total: float = height + skirt
	if is_wall_like():
		return Vector3(cell, total, thickness)
	if is_roof():
		# Grobe Hüllbox fürs Kollisions-Shape (BuildPiece._build_geometry) — die sichtbare
		# Geometrie ist das Prisma aus build_roof_mesh(), nicht diese Box.
		if roof_shape == RoofShape.FLAT:
			# Flachdach ist nur Platte + niedrige Attika, nicht `height` hoch (siehe
			# _build_flat_roof_mesh()/RoofShape-Kommentar: height bleibt hier ungenutzt).
			return Vector3(cell, FLAT_ROOF_THICKNESS + FLAT_ROOF_PARAPET, cell)
		return Vector3(cell, height, cell)
	if is_stairs():
		# Grobe Hüllbox — die sichtbare/begehbare Geometrie sind die Einzelstufen
		# (build_stairs_mesh() / BuildPiece._add_stairs()).
		return Vector3(cell, height, cell)
	if is_target():
		# Grobe Hüllbox um die jeweilige Requisiten-Geometrie (build_prop_mesh()) — deutlich
		# schmaler als eine ganze Zelle, damit man z.B. seitlich vorbeigehen kann.
		if prop_shape == PropShape.WELL:
			return Vector3(WELL_RADIUS * 2.2, height, WELL_RADIUS * 2.2)
		if prop_shape == PropShape.TOWER_ROUND or prop_shape == PropShape.TOWER_SQUARE:
			# Hüllbox reicht bis über die Dachspitze (Schaft + Zinnen + Dach), nicht nur bis
			# zur Zinnenbasis — sonst würde die Kollision mitten im Dach enden.
			return Vector3(TOWER_RADIUS * 2.2, tower_total_height(height), TOWER_RADIUS * 2.2)
		if prop_shape == PropShape.CROSS:
			return Vector3(CROSS_ARM_HALF_LENGTH * 2.4, height, CROSS_POST_HALF * 2.4)
		if prop_shape == PropShape.GRAVESTONE_STELE:
			return Vector3(GRAVESTONE_WIDTH * 1.3, height, GRAVESTONE_THICKNESS * 1.3)
		if prop_shape == PropShape.GRAVESTONE_SLAB:
			# `height` ist hier die Plattendicke, nicht die Standhöhe (siehe PropShape-
			# Kommentar) — die Hüllbox liegt entsprechend flach statt hochkant.
			return Vector3(GRAVESTONE_SLAB_WIDTH * 1.1, height, GRAVESTONE_SLAB_LENGTH * 1.1)
		if prop_shape == PropShape.CHAPEL:
			# Umschließende Box (Wände + Dach + Dachreiter) — NICHT die Kollision: die Kapelle ist
			# begehbar, ihre Kollision kommt aus get_prop_collision_boxes().
			return Vector3(
				(CHAPEL_HALF_WIDTH + CHAPEL_ROOF_OVERHANG) * 2.0,
				chapel_total_height(height),
				(CHAPEL_HALF_DEPTH + CHAPEL_ROOF_OVERHANG_Z) * 2.0)
		if prop_shape == PropShape.SIGNPOST:
			return Vector3(SIGNPOST_HULL, height, SIGNPOST_HULL)
		if prop_shape == PropShape.LAMP_POST:
			return Vector3(LAMP_HULL, height, LAMP_HULL)
		if prop_shape == PropShape.WINDMILL:
			# Hüllbox muss die seitlich abstehenden Flügel UND die Dachspitze einschließen —
			# siehe windmill_total_height()/build_windmill_mesh().
			return Vector3(
				WINDMILL_BLADE_LENGTH * 2.2,
				windmill_total_height(height),
				WINDMILL_RADIUS * 2.4)
		if prop_shape == PropShape.SUNDIAL:
			return Vector3(
				SUNDIAL_DIAL_RADIUS * 2.2,
				sundial_total_height(height),
				SUNDIAL_DIAL_RADIUS * 2.2)
		if prop_shape == PropShape.GATEHOUSE:
			# Hüllbox deckt nur den Bereich OBERHALB der Durchfahrt ab (siehe get_box_center()
			# und Kind.TARGET-Kommentar zu GATEHOUSE) — darunter bleibt der Weg frei begehbar.
			var gatehouse_total: float = gatehouse_total_height(height)
			return Vector3(GATEHOUSE_HALF_WIDTH * 2.2, gatehouse_total - GATEHOUSE_PASSAGE_HEIGHT, GATEHOUSE_HALF_WIDTH * 2.2)
		if prop_shape == PropShape.CATAPULT:
			return Vector3(
				CATAPULT_STAND_HALF_WIDTH * 2.6,
				catapult_total_height(height),
				CATAPULT_ARM_LENGTH * 1.8)
		if prop_shape == PropShape.FURNACE:
			return Vector3(FURNACE_HALF_WIDTH * 2.0, maxf(height, FURNACE_MIN_HEIGHT), FURNACE_HALF_DEPTH * 2.0)
		if prop_shape == PropShape.ANVIL:
			return Vector3((ANVIL_FACE_HALF_LENGTH + ANVIL_HORN_LENGTH) * 2.0, maxf(height, ANVIL_MIN_HEIGHT), ANVIL_STUMP_HALF * 2.0)
		if is_craft_prop(prop_shape):
			# Handwerks-Requisiten: Footprint + begrenzte Gesamthöhe, siehe PropShape-Kommentar.
			var craft_fp: Vector2 = craft_prop_footprint(prop_shape)
			return Vector3(craft_fp.x, craft_prop_height(prop_shape, height), craft_fp.y)
		return Vector3(TARGET_RADIUS * 2.2, height, TARGET_RADIUS * 1.4)
	return Vector3(cell, total, cell)

func get_box_center() -> Vector3:
	var total: float = height + skirt
	if is_wall_like():
		return Vector3(0.0, (height - skirt) * 0.5, 0.0)
	if is_target() and (prop_shape == PropShape.TOWER_ROUND or prop_shape == PropShape.TOWER_SQUARE):
		# Hüllbox reicht bis über die Dachspitze — Mittelpunkt daher über tower_total_height(),
		# nicht über `height` (das wäre nur der Schaft, siehe get_box_size()).
		return Vector3(0.0, tower_total_height(height) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.CHAPEL:
		return Vector3(0.0, chapel_total_height(height) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.WINDMILL:
		return Vector3(0.0, windmill_total_height(height) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.SUNDIAL:
		return Vector3(0.0, sundial_total_height(height) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.GATEHOUSE:
		# Mittelpunkt der (verkürzten) Hüllbox liegt mittig ZWISCHEN Durchfahrt-Oberkante und
		# Bauwerksspitze, nicht mittig ab dem Boden — siehe get_box_size().
		var gatehouse_total: float = gatehouse_total_height(height)
		return Vector3(0.0, (GATEHOUSE_PASSAGE_HEIGHT + gatehouse_total) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.CATAPULT:
		return Vector3(0.0, catapult_total_height(height) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.FURNACE:
		return Vector3(0.0, maxf(height, FURNACE_MIN_HEIGHT) * 0.5, 0.0)
	if is_target() and prop_shape == PropShape.ANVIL:
		# Hüllbox symmetrisch um die Mitte, so breit wie Bahn + Horn — auf der Hornseite ist sie
		# bewusst großzügig statt exakt, damit man nicht in die Hornspitze hineinläuft.
		return Vector3(0.0, maxf(height, ANVIL_MIN_HEIGHT) * 0.5, 0.0)
	if is_target() and is_craft_prop(prop_shape):
		return Vector3(0.0, craft_prop_height(prop_shape, height) * 0.5, 0.0)
	if is_roof() and roof_shape == RoofShape.FLAT:
		return Vector3(0.0, (FLAT_ROOF_THICKNESS + FLAT_ROOF_PARAPET) * 0.5, 0.0)
	if is_roof() or is_stairs() or is_target():
		return Vector3(0.0, height * 0.5, 0.0)
	return Vector3(0.0, -total * 0.5, 0.0)

## Kollisionsboxen eines Requisits, das NICHT als einzelne Hüllbox kollidieren soll — bisher nur
## die Kapelle (PropShape.CHAPEL): zwei Seitenwände, Rückwand, zwei Türpfosten, Sturz über dem
## Eingang und Bodenplatte, jeweils {size, center} wie get_door_boxes(). Die Türöffnung und der
## Innenraum bleiben frei — man kann hineingehen. Die Wände reichen bis CHAPEL_FOUNDATION unter y=0
## (Hanglage, wie skirt bei Wänden), Dach und Dachreiter kollidieren nicht (unerreichbar hoch).
## Leeres Array = normale Hüllbox aus get_box_size()/get_box_center() (alle anderen Requisiten).
func get_prop_collision_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	if not is_target() or prop_shape != PropShape.CHAPEL:
		return boxes
	var h: float = maxf(height, CHAPEL_MIN_WALL_HEIGHT)
	var hw: float = CHAPEL_HALF_WIDTH
	var hd: float = CHAPEL_HALF_DEPTH
	var t: float = CHAPEL_WALL_THICKNESS
	var f: float = CHAPEL_FOUNDATION
	var dw: float = CHAPEL_DOOR_HALF_WIDTH
	var dh: float = _chapel_door_height(h)
	boxes.append(_box_entry(Vector3(-hw, -f, -hd), Vector3(-hw + t, h, hd)))
	boxes.append(_box_entry(Vector3(hw - t, -f, -hd), Vector3(hw, h, hd)))
	boxes.append(_box_entry(Vector3(-hw + t, -f, -hd), Vector3(hw - t, h, -hd + t)))
	boxes.append(_box_entry(Vector3(-hw + t, -f, hd - t), Vector3(-dw, h, hd)))
	boxes.append(_box_entry(Vector3(dw, -f, hd - t), Vector3(hw - t, h, hd)))
	boxes.append(_box_entry(Vector3(-dw, dh, hd - t), Vector3(dw, h, hd)))
	boxes.append(_box_entry(Vector3(-hw + t, -f, -hd + t), Vector3(hw - t, CHAPEL_FLOOR_TOP, hd)))
	return boxes

static func _box_entry(lo: Vector3, hi: Vector3) -> Dictionary:
	return {"size": hi - lo, "center": (lo + hi) * 0.5}

## Sendet dieses Bauteil Licht aus (OmniLight3D an der Leuchtfläche, siehe BuildPiece._add_prop_light())?
func has_light() -> bool:
	return is_target() and light_range > 0.0

## Rolle jeder Mesh-Fläche (Surface) eines Requisits, in Surface-Reihenfolge — Länge = Anzahl
## Surfaces von build_prop_mesh(). Einflächige Shapes (alle älteren) → [MAIN].
static func prop_surface_roles(shape: int) -> Array[int]:
	match shape:
		PropShape.CHAPEL:
			return [PropSurface.MAIN, PropSurface.ACCENT, PropSurface.GLOW]
		PropShape.SIGNPOST:
			return [PropSurface.MAIN, PropSurface.ACCENT]
		PropShape.LAMP_POST:
			return [PropSurface.MAIN, PropSurface.GLOW]
		PropShape.FURNACE:
			return [PropSurface.MAIN, PropSurface.ACCENT, PropSurface.GLOW]
		PropShape.ANVIL:
			return [PropSurface.MAIN, PropSurface.ACCENT]
		PropShape.BARREL, PropShape.MARKET_STALL, PropShape.WORKBENCH:
			return [PropSurface.MAIN, PropSurface.ACCENT]
		PropShape.BAKE_OVEN:
			return [PropSurface.MAIN, PropSurface.GLOW]
		PropShape.CRATE, PropShape.SACKS, PropShape.TABLE, PropShape.CART, PropShape.BANNER:
			return [PropSurface.MAIN, PropSurface.ACCENT]
		PropShape.TROUGH, PropShape.WOODPILE, PropShape.GARDEN_BED, PropShape.SCARECROW, PropShape.WEAPON_RACK:
			return [PropSurface.MAIN, PropSurface.ACCENT]
		PropShape.FIREPIT:
			return [PropSurface.MAIN, PropSurface.ACCENT, PropSurface.GLOW]
		_:
			return [PropSurface.MAIN]

## Materialien zu den Surfaces von build_prop_mesh() (gleiche Reihenfolge wie prop_surface_roles()):
## MAIN = color, ACCENT = accent_color, GLOW = emissive Lampenfarbe. Doppelseitig (wie bisher bei
## allen Requisiten). Gemeinsame Quelle für BuildPiece; der Geist (BuildGhost) färbt dagegen per
## material_override einheitlich nach Baubarkeit.
func build_prop_materials() -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for role: int in prop_surface_roles(prop_shape):
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.9
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		match role:
			PropSurface.ACCENT:
				mat.albedo_color = accent_color
			PropSurface.GLOW:
				mat.albedo_color = PROP_GLOW_COLOR
				mat.emission_enabled = true
				mat.emission = PROP_GLOW_COLOR
				mat.emission_energy_multiplier = PROP_GLOW_ENERGY
			_:
				mat.albedo_color = color
		out.append(mat)
	return out

## Lokale Position der Lichtquelle eines Requisits (Mitte der Leuchtfläche) — nur LAMP_POST hat
## bisher eine, alle anderen Shapes Vector3.ZERO (dort ohne Bedeutung, has_light() ist false).
static func prop_light_offset(shape: int, prop_height: float) -> Vector3:
	if shape == PropShape.LAMP_POST:
		var glass: Vector2 = lamp_glass_bounds(prop_height)
		return Vector3(0.0, (glass.x + glass.y) * 0.5, 0.0)
	if shape == PropShape.FURNACE:
		# Licht sitzt knapp VOR der Feueröffnung, damit es den Boden/Spieler vor dem Ofen erhellt.
		var mouth: Vector2 = furnace_mouth_bounds(prop_height)
		return Vector3(0.0, (mouth.x + mouth.y) * 0.5, FURNACE_HALF_DEPTH + 0.2)
	return Vector3.ZERO

## Boxen für eine Tür: zwei Pfosten (volle Wandhöhe inkl. Skirt) + Sturz über der Öffnung.
## Die Öffnung selbst (Boden bis DOOR_OPEN_HEIGHT, auch im Skirt-Bereich darunter) bleibt frei
## begehbar — kein Boxenteil dort, sonst würde die Schwelle auf unebenem Gelände blockieren.
## Gemeinsame Quelle für BuildPiece (Einzel-Boxen + je eigene Kollision) und BuildGhost
## (build_framed_mesh() kombiniert dieselben Boxen zu einem Vorschau-Mesh).
func get_door_boxes(cell: float) -> Array[Dictionary]:
	var hc: float = cell * 0.5
	var door_w: float = opening_width if opening_width > 0.0 else DOOR_WIDTH
	var half_w: float = clampf(door_w * 0.5, 0.05, hc - 0.05)
	var open_h: float = clampf(opening_height if opening_height > 0.0 else DOOR_OPEN_HEIGHT, 0.1, height)
	var boxes: Array[Dictionary] = []
	if opening_shape == OpeningShape.ARCH:
		boxes = _arch_frame_boxes(cell, half_w, 0.0, open_h)
	else:
		var total: float = height + skirt
		var jamb_w: float = hc - half_w
		boxes.append({"size": Vector3(jamb_w, total, thickness),
			"center": Vector3(-(hc + half_w) * 0.5, (height - skirt) * 0.5, 0.0)})
		boxes.append({"size": Vector3(jamb_w, total, thickness),
			"center": Vector3((hc + half_w) * 0.5, (height - skirt) * 0.5, 0.0)})
		if open_h < height:
			boxes.append({"size": Vector3(half_w * 2.0, height - open_h, thickness),
				"center": Vector3(0.0, (open_h + height) * 0.5, 0.0)})
	boxes.append_array(_leaf_boxes(cell, half_w, open_h))
	return boxes

## Torflügel als Boxen (siehe LeafState). `open_h` = Oberkante der Öffnung (bei ARCH der Scheitel).
## OPEN: zwei Flügel, je halbe Öffnungsbreite lang, hochkant am Pfosten nach außen (+Z) geklappt
##   (höchstens bis zur Zellkante), bis zum Bogenansatz hoch. CLOSED: eine Platte über die ganze
##   Öffnung bis zum Ansatz plus bei ARCH je Bogenstufe eine Platte in der Breite der Stufen-Öffnung.
func _leaf_boxes(cell: float, half_w: float, open_h: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if leaf_state == LeafState.NONE:
		return out
	var arch: bool = opening_shape == OpeningShape.ARCH
	var apex: float = clampf(open_h, 0.2, height) if arch else open_h
	var rise: float = minf(half_w, apex - 0.1) if arch else 0.0
	var spring: float = apex - rise
	if leaf_state == LeafState.OPEN:
		var leaf_len: float = minf(half_w, cell * 0.5 - thickness * 0.5 - 0.02)
		for side: float in [-1.0, 1.0]:
			out.append({"size": Vector3(LEAF_THICKNESS, spring, leaf_len),
				"center": Vector3(side * (half_w - LEAF_THICKNESS * 0.5), spring * 0.5, thickness * 0.5 + leaf_len * 0.5)})
		return out
	out.append({"size": Vector3(half_w * 2.0, spring, LEAF_CLOSED_THICKNESS),
		"center": Vector3(0.0, spring * 0.5, 0.0)})
	if arch:
		for i in ARCH_STEPS:
			var y0: float = spring + rise * float(i) / float(ARCH_STEPS)
			var y1: float = spring + rise * float(i + 1) / float(ARCH_STEPS)
			var t: float = (y1 - spring) / rise
			var w: float = half_w * sqrt(maxf(1.0 - t * t, 0.0))
			if w >= 0.01:
				out.append({"size": Vector3(w * 2.0, y1 - y0, LEAF_CLOSED_THICKNESS),
					"center": Vector3(0.0, (y0 + y1) * 0.5, 0.0)})
	return out

## Boxen für ein Fenster: zwei Pfosten (volle Höhe), Brüstung (Boden bis WINDOW_SILL) und
## Sturz (WINDOW_SILL+WINDOW_OPEN_HEIGHT bis Wandhöhe) — die Öffnung dazwischen bleibt frei.
## Mit opening_shape = ARCH endet die Öffnung oben im Rundbogen (siehe _arch_frame_boxes()).
func get_window_boxes(cell: float) -> Array[Dictionary]:
	var hc: float = cell * 0.5
	var win_w: float = opening_width if opening_width > 0.0 else WINDOW_WIDTH
	var half_w: float = clampf(win_w * 0.5, 0.05, hc - 0.05)
	var sill_top: float = clampf(WINDOW_SILL, 0.0, height)
	var open_top: float = clampf(opening_height if opening_height > 0.0 else sill_top + WINDOW_OPEN_HEIGHT, sill_top, height)
	if opening_shape == OpeningShape.ARCH:
		return _arch_frame_boxes(cell, half_w, sill_top, open_top)
	var total: float = height + skirt
	var jamb_w: float = hc - half_w
	var boxes: Array[Dictionary] = []
	boxes.append({"size": Vector3(jamb_w, total, thickness),
		"center": Vector3(-(hc + half_w) * 0.5, (height - skirt) * 0.5, 0.0)})
	boxes.append({"size": Vector3(jamb_w, total, thickness),
		"center": Vector3((hc + half_w) * 0.5, (height - skirt) * 0.5, 0.0)})
	boxes.append({"size": Vector3(half_w * 2.0, sill_top + skirt, thickness),
		"center": Vector3(0.0, (sill_top - skirt) * 0.5, 0.0)})
	if open_top < height:
		boxes.append({"size": Vector3(half_w * 2.0, height - open_top, thickness),
			"center": Vector3(0.0, (open_top + height) * 0.5, 0.0)})
	return boxes

## Rahmen einer Öffnung mit Rundbogen (OpeningShape.ARCH) als Box-Liste: zwei Pfosten bis zum
## Bogenansatz (`spring`), optional eine Brüstung (Fenster, `sill` > 0), ARCH_STEPS Stufenpaare, die
## den Halbkreis/die Halbellipse von außen annähern (je Stufe nur so schmal wie die Kurve AM OBEREN
## Stufenrand — die Öffnung ist der echten Kurve also einbeschrieben: nie breiter als der Bogen, nie
## von Wand blockiert, die Wand daneben bleibt dicht), eine durchgehende Scheitelbox und darüber die
## restliche Wand. `half_w` = halbe lichte Breite, `apex_in` = Scheitelhöhe ab Basis.
## Der Bogenanstieg ist höchstens half_w (Halbkreis); ist weniger Höhe da, wird er flacher (Ellipse).
func _arch_frame_boxes(cell: float, half_w: float, sill: float, apex_in: float) -> Array[Dictionary]:
	var hc: float = cell * 0.5
	var apex: float = clampf(apex_in, sill + 0.2, height)
	var rise: float = minf(half_w, apex - sill - 0.1)
	var spring: float = apex - rise
	var jamb_w: float = hc - half_w
	var boxes: Array[Dictionary] = []
	for side: float in [-1.0, 1.0]:
		boxes.append({"size": Vector3(jamb_w, spring + skirt, thickness),
			"center": Vector3(side * (hc + half_w) * 0.5, (spring - skirt) * 0.5, 0.0)})
	if sill > 0.0:
		boxes.append({"size": Vector3(half_w * 2.0, sill + skirt, thickness),
			"center": Vector3(0.0, (sill - skirt) * 0.5, 0.0)})
	for i in ARCH_STEPS:
		var y0: float = spring + rise * float(i) / float(ARCH_STEPS)
		var y1: float = spring + rise * float(i + 1) / float(ARCH_STEPS)
		var t: float = (y1 - spring) / rise
		var w: float = half_w * sqrt(maxf(1.0 - t * t, 0.0))
		if w < 0.01:
			boxes.append({"size": Vector3(cell, y1 - y0, thickness),
				"center": Vector3(0.0, (y0 + y1) * 0.5, 0.0)})
		else:
			for side: float in [-1.0, 1.0]:
				boxes.append({"size": Vector3(hc - w, y1 - y0, thickness),
					"center": Vector3(side * (hc + w) * 0.5, (y0 + y1) * 0.5, 0.0)})
	if apex < height:
		boxes.append({"size": Vector3(cell, height - apex, thickness),
			"center": Vector3(0.0, (apex + height) * 0.5, 0.0)})
	return boxes

## Boxen einer Zinnenmauer (WallTop.CRENELLATED): durchgehender Mauerkörper bis `height` minus
## Zinnenhöhe, darüber links eine halbe Zinne, mittig eine ganze und rechts eine halbe (je ein
## Viertel der Zellbreite pro Einheit: halb / Lücke / ganz / Lücke / halb). Gemeinsame Quelle für
## BuildPiece (Einzel-Boxen mit Kollision) und BuildGhost (zu einem Mesh kombiniert).
func get_wall_boxes(cell: float) -> Array[Dictionary]:
	var hc: float = cell * 0.5
	var mh: float = minf(WALL_MERLON_HEIGHT, height * 0.5)
	var unit: float = cell * 0.25
	var boxes: Array[Dictionary] = []
	boxes.append({"size": Vector3(cell, height - mh + skirt, thickness),
		"center": Vector3(0.0, (height - mh - skirt) * 0.5, 0.0)})
	boxes.append({"size": Vector3(unit * 0.5, mh, thickness),
		"center": Vector3(-hc + unit * 0.25, height - mh * 0.5, 0.0)})
	boxes.append({"size": Vector3(unit, mh, thickness),
		"center": Vector3(0.0, height - mh * 0.5, 0.0)})
	boxes.append({"size": Vector3(unit * 0.5, mh, thickness),
		"center": Vector3(hc - unit * 0.25, height - mh * 0.5, 0.0)})
	return boxes

## Hat dieses WALL-Bauteil einen Zinnenkranz (statt einer glatten Oberkante)?
func has_crenellations() -> bool:
	return kind == Kind.WALL and wall_top == WallTop.CRENELLATED

## Sichtbare Geometrie eines Dach-Bauteils: Satteldach-Prisma über einer Zelle, First entlang
## lokal X bei y=height, Traufe (Basis) bei y=0 auf den vier Eckpunkten der Zelle. Gemeinsame
## Quelle für BuildPiece (fertiges Bauteil) UND BuildGhost (Vorschau) — dieselbe Regel wie bei
## get_box_size()/get_box_center() für Boden/Wand: der Geist sieht immer so aus wie das Ergebnis.
static func build_roof_mesh(cell: float, height: float, shape: int = RoofShape.GABLE, ridge: float = 1.0) -> ArrayMesh:
	match shape:
		RoofShape.HIP:
			return _build_hip_gable_mesh(cell, height, clampf(ridge, 0.0, 1.0))
		RoofShape.PYRAMID:
			# Walmdach mit First = 0 (Punkt statt Linie) — bei quadratischer Zelle automatisch
			# eine echte, symmetrische Pyramide, unabhängig vom roof_ridge-Feld.
			return _build_hip_gable_mesh(cell, height, 1.0)
		RoofShape.FLAT:
			return _build_flat_roof_mesh(cell)
		_:
			# GABLE (Standard, bisheriges Verhalten): entspricht Walmdach mit ridge=0.
			return _build_hip_gable_mesh(cell, height, 0.0)

## Gemeinsame Geometrie für GABLE/HIP/PYRAMID: First entlang lokal X bei z=0, dessen halbe
## Länge zwischen hc (ridge=0, First reicht bis an die Giebelkanten → Satteldach) und 0
## (ridge=1, First auf einen Punkt geschrumpft → Walmdach/Pyramide) interpoliert. Bei ridge=0
## entarten die beiden zusätzlichen Walmflächen zu Nullflächen (Start-/Endpunkt fallen mit den
## Firstenden zusammen) und die Giebeldreiecke gewinnen ihre volle Fläche zurück — der
## bisherige build_roof_mesh()-Sonderfall für GABLE ist damit nur ein Spezialfall hiervon,
## kein eigener Code-Pfad. Traufe bleibt in jedem Fall auf den vier Zellecken (y=0).
static func _build_hip_gable_mesh(cell: float, height: float, ridge: float) -> ArrayMesh:
	var h: float = maxf(height, 0.05)
	var hc: float = cell * 0.5
	var half_ridge: float = hc * (1.0 - ridge)

	var v_fl := Vector3(-hc, 0.0, -hc)   # front-left
	var v_fr := Vector3(hc, 0.0, -hc)    # front-right
	var v_bl := Vector3(-hc, 0.0, hc)    # back-left
	var v_br := Vector3(hc, 0.0, hc)     # back-right
	var r_l := Vector3(-half_ridge, h, 0.0)   # First links
	var r_r := Vector3(half_ridge, h, 0.0)    # First rechts

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Vordere/hintere Dachfläche: bei ridge=0 ein Quad (Satteldach-Trapezfläche entartet zum
	# Rechteck), bei ridge>0 ein Trapez (First kürzer als Traufe).
	_add_quad(st, v_fl, v_fr, r_r, r_l)
	_add_quad(st, v_br, v_bl, r_l, r_r)
	# Giebel-/Walmflächen Ost/West: EIN Dreieck pro Seite von den beiden Eckpunkten zum
	# nahen Firstende — bei ridge=0 liegt das Firstende genau auf der Eckkante (klassisches
	# Giebeldreieck eines Satteldachs), bei ridge>0 rückt es zur Mitte ein (Walmfläche).
	# Dieselbe Formel deckt also GABLE und HIP/PYRAMID ab, ohne Fallunterscheidung.
	_add_tri(st, v_fr, v_br, r_r)
	_add_tri(st, v_bl, v_fl, r_l)
	# Unterseite (Boden des Prismas) — sichtbar für Spieler, die von innen hochschauen.
	_add_quad(st, v_fl, v_bl, v_br, v_fr)

	st.generate_normals()
	return st.commit()

## Flachdach (RoofShape.FLAT): dünne Platte auf Traufhöhe (y=0..FLAT_ROOF_THICKNESS) mit
## umlaufender, niedriger Attika-Kante (FLAT_ROOF_PARAPET) statt einer geneigten Fläche —
## `height` bleibt ungenutzt (siehe RoofShape-Kommentar), damit ein Wechsel von GABLE/HIP auf
## FLAT ohne Datenänderung an bestehenden .tres möglich ist.
static func _build_flat_roof_mesh(cell: float) -> ArrayMesh:
	var hc: float = cell * 0.5
	var t: float = FLAT_ROOF_THICKNESS
	var p: float = FLAT_ROOF_PARAPET
	var inner: float = maxf(hc - 0.12, 0.1)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Deckplatte (Boden bei y=0, Oberkante bei y=t) über die volle Zelle.
	_add_box_geom(st, Vector3(-hc, 0.0, -hc), Vector3(hc, t, hc))
	# Attika: vier niedrige, dünne Wandstreifen entlang der Traufkanten (Oberkante y=t+p).
	_add_box_geom(st, Vector3(-hc, t, -hc), Vector3(hc, t + p, -inner))
	_add_box_geom(st, Vector3(-hc, t, inner), Vector3(hc, t + p, hc))
	_add_box_geom(st, Vector3(-hc, t, -inner), Vector3(-inner, t + p, inner))
	_add_box_geom(st, Vector3(inner, t, -inner), Vector3(hc, t + p, inner))

	st.generate_normals()
	return st.commit()

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

## Quad aus vier Punkten (Reihenfolge = Umlauf), als zwei Dreiecke, Normale nach außen.
static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_tri(st, a, b, c)
	_add_tri(st, a, c, d)

## Sichtbare Geometrie einer Treppe: STAIR_STEPS gestapelte Stufen, aufsteigend entlang lokal Z
## von -cell/2 (y=0) nach +cell/2 (y=height). Gemeinsame Quelle für BuildPiece UND BuildGhost —
## dieselbe Stufenteilung wie die Kollision in BuildPiece._add_stairs(), damit Vorschau, Optik
## und begehbare Fläche übereinstimmen.
static func build_stairs_mesh(cell: float, height: float, shape: int = StairsShape.STRAIGHT) -> ArrayMesh:
	if shape == StairsShape.SPIRAL:
		return build_spiral_stairs_mesh(cell, height)
	var steps: int = STAIR_STEPS
	var step_h: float = maxf(height, 0.05) / float(steps)
	var step_d: float = cell / float(steps)
	var hc: float = cell * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var z0: float = -hc + step_d * float(i)
		var z1: float = z0 + step_d
		var y1: float = step_h * float(i + 1)
		_add_box_geom(st, Vector3(-hc, 0.0, z0), Vector3(hc, y1, z1))
	st.generate_normals()
	return st.commit()

## Sichtbare Geometrie einer Wendeltreppe (StairsShape.SPIRAL): STAIR_STEPS radiale Keil-Stufen
## (dieselbe Technik wie _add_radial_block() der Turm-Zinnen, nur von y=0 statt y0 bis zur
## jeweiligen Stufenhöhe — wie bei den geraden Stufen reicht jede Stufe bis zum Boden, damit
## niemand darunter rutschen kann), verteilt über SPIRAL_TURNS Umdrehungen um einen dünnen
## Mittelpfosten (_add_ring_wall(), wie der Turmschaft). Gemeinsame Quelle für BuildPiece UND
## BuildGhost, wie build_stairs_mesh().
static func build_spiral_stairs_mesh(cell: float, height: float) -> ArrayMesh:
	var steps: int = STAIR_STEPS
	var h: float = maxf(height, 0.05)
	var step_h: float = h / float(steps)
	var hc: float = cell * 0.5
	var r_out: float = maxf(hc - SPIRAL_MARGIN, SPIRAL_NEWEL_RADIUS + 0.2)
	var r_in: float = SPIRAL_NEWEL_RADIUS
	var step_angle: float = TAU * SPIRAL_TURNS / float(steps)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Mittelpfosten: durchgehende Säule von der Basis bis zur Oberkante — optischer Anker der
	# Spirale UND Innenradius der Stufen (siehe Klassenkommentar StairsShape).
	_add_ring_wall(st, r_in, h, SPIRAL_NEWEL_SEGMENTS)

	for i in steps:
		var a0: float = step_angle * float(i)
		var a1: float = a0 + step_angle
		var y1: float = step_h * float(i + 1)
		_add_radial_block(st, r_in, r_out, 0.0, y1, a0, a1)

	st.generate_normals()
	return st.commit()

## Sichtbare Geometrie eines TARGET-Bauteils: runde Zielscheibe (Kreis-Fächer, beidseitig
## sichtbar) auf einem senkrechten Pfosten mit zwei schrägen Standbeinen. Scheibe liegt in der
## lokalen XY-Ebene bei z=0 (Blickrichtung/Normale entlang lokal Z, Ausrichtung über yaw wie bei
## Treppen). Gemeinsame Quelle für BuildPiece (fertiges Bauteil) UND BuildGhost (Vorschau).
static func build_target_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, 0.3)
	var r: float = TARGET_RADIUS
	var post_half: float = TARGET_POST_HALF
	# Scheibenmitte liegt nicht auf halber Ständerhöhe, sondern nahe der Spitze (wie ein
	# echter Schießstand: die Beine stützen von unten, die Scheibe hängt oben am Pfosten).
	var center_y: float = h * 0.72

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Zielscheibe: Kreis-Fächer aus TARGET_SEGMENTS Dreiecken, Vorder- UND Rückseite (zwei
	# gegenläufig gewundene Dreiecke pro Segment), damit sie aus beiden Richtungen sichtbar
	# ist — ohne auf materialseitiges cull_mode verlassen zu müssen.
	var center := Vector3(0.0, center_y, 0.0)
	var prev := Vector3(r, center_y, 0.0)
	for i in range(1, TARGET_SEGMENTS + 1):
		var a: float = TAU * float(i) / float(TARGET_SEGMENTS)
		var cur := Vector3(cos(a) * r, center_y + sin(a) * r, 0.0)
		_add_tri(st, center, prev, cur)
		_add_tri(st, center, cur, prev)
		prev = cur

	# Senkrechter Pfosten: vom Boden bis knapp unter die Scheibenmitte (die Scheibe "sitzt"
	# vor der Pfostenspitze).
	_add_box_geom(st, Vector3(-post_half, 0.0, -post_half), Vector3(post_half, center_y - r * 0.15, post_half))

	# Zwei schräge Standbeine (Dreibock-Optik): von je einer Bodenkante vorn/seitlich zur
	# Pfostenmitte auf halber Höhe — reine Sichtgeometrie (Kollision bleibt die grobe Hüllbox
	# aus get_box_size()/get_box_center(), wie bei ROOF/STAIRS).
	var mid_y: float = center_y * 0.5
	_add_strut(st, Vector3(0.0, 0.0, r * 0.85), Vector3(0.0, mid_y, 0.0), post_half)
	_add_strut(st, Vector3(-r * 0.7, 0.0, -r * 0.5), Vector3(0.0, mid_y, 0.0), post_half)
	_add_strut(st, Vector3(r * 0.7, 0.0, -r * 0.5), Vector3(0.0, mid_y, 0.0), post_half)

	st.generate_normals()
	return st.commit()

## Wählt je PropShape die passende Sichtgeometrie eines TARGET-Bauteils. Gemeinsame Quelle für
## BuildPiece (fertiges Bauteil) UND BuildGhost (Vorschau) — siehe Kind.TARGET-Kommentar.
static func build_prop_mesh(height: float, prop_shape: int) -> ArrayMesh:
	match prop_shape:
		PropShape.WELL:
			return build_well_mesh(height)
		PropShape.TOWER_ROUND:
			return build_tower_mesh(height, true)
		PropShape.TOWER_SQUARE:
			return build_tower_mesh(height, false)
		PropShape.CROSS:
			return build_cross_mesh(height)
		PropShape.GRAVESTONE_STELE:
			return build_gravestone_stele_mesh(height)
		PropShape.GRAVESTONE_SLAB:
			return build_gravestone_slab_mesh(height)
		PropShape.CHAPEL:
			return build_chapel_mesh(height)
		PropShape.SIGNPOST:
			return build_signpost_mesh(height)
		PropShape.LAMP_POST:
			return build_lamp_post_mesh(height)
		PropShape.WINDMILL:
			return build_windmill_mesh(height)
		PropShape.SUNDIAL:
			return build_sundial_mesh(height)
		PropShape.GATEHOUSE:
			return build_gatehouse_mesh(height)
		PropShape.CATAPULT:
			return build_catapult_mesh(height)
		PropShape.FURNACE:
			return build_furnace_mesh(height)
		PropShape.ANVIL:
			return build_anvil_mesh(height)
		PropShape.BARREL:
			return build_barrel_mesh(height)
		PropShape.MARKET_STALL:
			return build_market_stall_mesh(height)
		PropShape.BAKE_OVEN:
			return build_bake_oven_mesh(height)
		PropShape.WORKBENCH:
			return build_workbench_mesh(height)
		PropShape.CRATE:
			return build_crate_mesh(height)
		PropShape.SACKS:
			return build_sacks_mesh(height)
		PropShape.BENCH:
			return build_bench_mesh(height)
		PropShape.TABLE:
			return build_table_mesh(height)
		PropShape.CART:
			return build_cart_mesh(height)
		PropShape.BANNER:
			return build_banner_mesh(height)
		PropShape.PILLAR:
			return build_pillar_mesh(height)
		PropShape.FIREPIT:
			return build_firepit_mesh(height)
		PropShape.TROUGH:
			return build_trough_mesh(height)
		PropShape.WOODPILE:
			return build_woodpile_mesh(height)
		PropShape.GARDEN_BED:
			return build_garden_bed_mesh(height)
		PropShape.SCARECROW:
			return build_scarecrow_mesh(height)
		PropShape.WEAPON_RACK:
			return build_weapon_rack_mesh(height)
		_:
			return build_target_mesh(height)

## Sichtbare Geometrie eines Brunnens (PropShape.WELL): zylindrische Ringmauer, zwei Pfosten
## mit Querbalken (Kurbelachse), ein kleines Satteldach (First entlang lokal Z) und ein Eimer
## am Seil über der Ringmitte. Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_well_mesh(height: float, with_bucket: bool = true) -> ArrayMesh:
	var h: float = maxf(height, 0.9)
	var r: float = WELL_RADIUS
	var ring_h: float = minf(h * 0.55, 0.9)
	var post_half: float = WELL_POST_HALF
	var post_x: float = r * 0.92
	var roof_base_y: float = maxf(h * 0.78, ring_h + 0.3)
	var roof_peak_y: float = maxf(h, roof_base_y + 0.2)
	var eave_z: float = WELL_ROOF_HALF_DEPTH

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Ringmauer: zylindrische Außenwand aus WELL_RING_SEGMENTS Quads (nur Außenhaut — von
	# innen schaut ohnehin niemand rein; Material ist trotzdem beidseitig sichtbar, siehe
	# BuildPiece._add_target).
	var prev_a := Vector3(r, 0.0, 0.0)
	var prev_b := Vector3(r, ring_h, 0.0)
	for i in range(1, WELL_RING_SEGMENTS + 1):
		var ang: float = TAU * float(i) / float(WELL_RING_SEGMENTS)
		var cur_a := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var cur_b := Vector3(cos(ang) * r, ring_h, sin(ang) * r)
		_add_quad(st, prev_a, cur_a, cur_b, prev_b)
		prev_a = cur_a
		prev_b = cur_b

	# Zwei Pfosten (gegenüberliegend entlang lokal X), vom Ringrand bis zur Dachtraufe.
	_add_box_geom(st, Vector3(post_x - post_half, ring_h, -post_half), Vector3(post_x + post_half, roof_base_y, post_half))
	_add_box_geom(st, Vector3(-post_x - post_half, ring_h, -post_half), Vector3(-post_x + post_half, roof_base_y, post_half))

	# Querbalken zwischen den Pfostenköpfen (Kurbelachse für das Seil).
	_add_box_geom(st, Vector3(-post_x, roof_base_y - post_half, -post_half), Vector3(post_x, roof_base_y + post_half, post_half))

	# Kleines Satteldach über den Pfosten, First entlang lokal Z (wie build_roof_mesh(), nur
	# kleiner und ohne Giebeldreiecke — offen an beiden Enden, es deckt nur den Brunnen ab).
	var e_near_l := Vector3(-post_x, roof_base_y, -eave_z)
	var e_far_l := Vector3(-post_x, roof_base_y, eave_z)
	var e_near_r := Vector3(post_x, roof_base_y, -eave_z)
	var e_far_r := Vector3(post_x, roof_base_y, eave_z)
	var ridge_near := Vector3(0.0, roof_peak_y, -eave_z)
	var ridge_far := Vector3(0.0, roof_peak_y, eave_z)
	_add_quad(st, e_near_l, e_far_l, ridge_far, ridge_near)
	_add_quad(st, e_far_r, e_near_r, ridge_near, ridge_far)

	# Eimer am Seil, mittig über dem Ring. Bei with_bucket=false (animierter Brunnen) baut
	# BuildPiece Eimer und Seil stattdessen als bewegliche Nodes (build_well_bucket_mesh()/
	# build_well_rope_mesh()).
	if with_bucket:
		var bucket_top: float = ring_h + 0.25
		var bh: float = WELL_BUCKET_HALF
		_add_box_geom(st, Vector3(-0.02, bucket_top, -0.02), Vector3(0.02, roof_base_y - post_half, 0.02))
		_add_box_geom(st, Vector3(-bh, bucket_top - 0.22, -bh), Vector3(bh, bucket_top, bh))

	st.generate_normals()
	return st.commit()

## Maße für Eimer-Animation und -Teile des Brunnens (gleiche Formeln wie build_well_mesh()):
## rest_y = Oberkante des Eimers in Ruhe, anchor_y = Aufhängung am Querbalken, rope_len = Seillänge
## in Ruhe, drop = wie tief der Eimer beim Schöpfen absinkt.
static func well_bucket_geometry(height: float) -> Dictionary:
	var h: float = maxf(height, 0.9)
	var ring_h: float = minf(h * 0.55, 0.9)
	var roof_base_y: float = maxf(h * 0.78, ring_h + 0.3)
	var rest_y: float = ring_h + 0.25
	var anchor_y: float = roof_base_y - WELL_POST_HALF
	return {
		"rest_y": rest_y,
		"anchor_y": anchor_y,
		"rope_len": maxf(anchor_y - rest_y, 0.05),
		"drop": ring_h * 0.85,
	}

## Eimer als eigener Körper, Ursprung = Oberkante (mittig) — Node-Position = rest_y bzw. darunter.
static func build_well_bucket_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bh: float = WELL_BUCKET_HALF
	_add_box_geom(st, Vector3(-bh, -0.22, -bh), Vector3(bh, 0.0, bh))
	st.generate_normals()
	return st.commit()

## Seil als eigener Körper, Ursprung = Aufhängung, hängt nach unten (−Y) — Node-Skalierung in Y
## streckt es, wenn der Eimer absinkt.
static func build_well_rope_mesh(height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rope_len: float = float(well_bucket_geometry(height)["rope_len"])
	_add_box_geom(st, Vector3(-0.02, -rope_len, -0.02), Vector3(0.02, 0.0, 0.02))
	st.generate_normals()
	return st.commit()

## Sichtbare Geometrie eines Kreuzes (PropShape.CROSS, Wunsch "Kirche & Friedhof"): senkrechter
## Balken von der Basis bis zur Spitze, waagerechter Querbalken bei CROSS_ARM_Y_RATIO der
## Gesamthöhe — dieselbe Funktion deckt Wegkreuz (großes `height`) und Grabkreuz (kleines
## `height`) ab, siehe PropShape-Kommentar. Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_cross_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, 0.2)
	var ph: float = CROSS_POST_HALF
	var arm_y: float = h * CROSS_ARM_Y_RATIO
	var arm_half: float = CROSS_ARM_HALF_LENGTH

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box_geom(st, Vector3(-ph, 0.0, -ph), Vector3(ph, h, ph))
	_add_box_geom(st, Vector3(-arm_half, arm_y - ph, -ph), Vector3(arm_half, arm_y + ph, ph))
	st.generate_normals()
	return st.commit()

## Sichtbare Geometrie eines stehenden Grabsteins (PropShape.GRAVESTONE_STELE): gerader Schaft
## (Quader) bis knapp unter die Gesamthöhe, gekrönt von einer gerundeten Kuppe — ein extrudierter
## Halbkreisbogen (Radius = halbe Schaftbreite, GRAVESTONE_ARCH_SEGMENTS Segmente) aus Vorder-/
## Rückfläche (Fächer, wie build_target_mesh()) plus Außenkante (Rand), damit der Bogen — anders
## als die Zielscheibe — auch eine sichtbare Dicke hat. Schaft + Bogenradius ergeben zusammen
## genau `height`. Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_gravestone_stele_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, 0.3)
	var hw: float = GRAVESTONE_WIDTH * 0.5
	var ht: float = GRAVESTONE_THICKNESS * 0.5
	var arch_r: float = hw
	var body_top: float = maxf(h - arch_r, 0.05)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_box_geom(st, Vector3(-hw, 0.0, -ht), Vector3(hw, body_top, ht))

	var segs: int = GRAVESTONE_ARCH_SEGMENTS
	var center_f := Vector3(0.0, body_top, ht)
	var center_b := Vector3(0.0, body_top, -ht)
	var prev_f := Vector3(-hw, body_top, ht)
	var prev_b := Vector3(-hw, body_top, -ht)
	for i in range(1, segs + 1):
		var a: float = PI * float(i) / float(segs)
		var x: float = -cos(a) * arch_r
		var y: float = body_top + sin(a) * arch_r
		var cur_f := Vector3(x, y, ht)
		var cur_b := Vector3(x, y, -ht)
		_add_tri(st, center_f, prev_f, cur_f)
		_add_tri(st, center_b, cur_b, prev_b)
		_add_quad(st, prev_f, cur_f, cur_b, prev_b)
		prev_f = cur_f
		prev_b = cur_b

	st.generate_normals()
	return st.commit()

## Sichtbare Geometrie einer liegenden Grabplatte (PropShape.GRAVESTONE_SLAB): eine flache Platte
## auf dem Boden, `height` ist die Plattendicke (siehe PropShape-Kommentar), nicht die Standhöhe.
## Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_gravestone_slab_mesh(height: float) -> ArrayMesh:
	var t: float = maxf(height, 0.05)
	var hw: float = GRAVESTONE_SLAB_WIDTH * 0.5
	var hl: float = GRAVESTONE_SLAB_LENGTH * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box_geom(st, Vector3(-hw, 0.0, -hl), Vector3(hw, t, hl))
	st.generate_normals()
	return st.commit()

## Gesamthöhe einer Kapelle (PropShape.CHAPEL) von der Basis bis zur Kreuzspitze des Dachreiters —
## Wandhöhe (`wall_height`) + Dach (CHAPEL_ROOF_RISE) + Dachreiter (CHAPEL_TURRET_HEIGHT). Einzige
## Quelle für get_box_size()/get_box_center() UND build_chapel_mesh().
static func chapel_total_height(wall_height: float) -> float:
	return maxf(wall_height, CHAPEL_MIN_WALL_HEIGHT) + CHAPEL_ROOF_RISE + CHAPEL_TURRET_HEIGHT

## Höhe der geraden Türöffnung (ohne Spitzbogen-Aufsatz) — knapp unter der Wandoberkante, aber
## höchstens 1,95 m, damit über dem Eingang immer ein Sturz bleibt.
static func _chapel_door_height(wall_height: float) -> float:
	return clampf(wall_height - 0.3, 1.2, 1.95)

## Sichtbare Geometrie einer Kapelle (PropShape.CHAPEL, Wunsch "Kapelle"): rechteckiger Baukörper
## (Fundament/Bodenplatte, drei geschlossene Wände, Frontwand mit spitzbogigem Eingang), Satteldach
## mit Überstand (First entlang lokal Z, Giebel vorn/hinten), Altar mit zwei Kerzen an der
## Rückwand, leuchtende Fenster (beide Seitenwände außen, Rückwand innen) sowie ein Dachreiter mit
## Glocke und Kreuz auf dem First. Eingang = lokal +Z. Drei Surfaces (prop_surface_roles()):
## 0 MAIN = Mauern/Altar/Dachreiter-Pfosten, 1 ACCENT = Dach/Haube/Kreuz/Glocke, 2 GLOW =
## Fenster + Kerzen. Kollision: get_prop_collision_boxes() (begehbar). Gemeinsame Quelle für
## BuildPiece UND BuildGhost.
static func build_chapel_mesh(wall_height: float) -> ArrayMesh:
	var h: float = maxf(wall_height, CHAPEL_MIN_WALL_HEIGHT)
	var hw: float = CHAPEL_HALF_WIDTH
	var hd: float = CHAPEL_HALF_DEPTH
	var t: float = CHAPEL_WALL_THICKNESS
	var f: float = CHAPEL_FOUNDATION
	var dw: float = CHAPEL_DOOR_HALF_WIDTH
	var dh: float = _chapel_door_height(h)
	var spring_y: float = dh - CHAPEL_DOOR_ARCH_RISE
	var ridge_y: float = h + CHAPEL_ROOF_RISE

	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var glow: SurfaceTool = _begin_flat_surface()

	# Bodenplatte (auch Schwelle im Eingang) + Fundament reicht unter die Wände.
	_add_box_geom(main, Vector3(-hw + t * 0.5, -f, -hd + t * 0.5), Vector3(hw - t * 0.5, CHAPEL_FLOOR_TOP, hd))

	# Wände: Seiten, Rückwand, Frontwand links/rechts vom Eingang, Sturz über dem Eingang.
	_add_box_geom(main, Vector3(-hw, -f, -hd), Vector3(-hw + t, h, hd))
	_add_box_geom(main, Vector3(hw - t, -f, -hd), Vector3(hw, h, hd))
	_add_box_geom(main, Vector3(-hw + t, -f, -hd), Vector3(hw - t, h, -hd + t))
	_add_box_geom(main, Vector3(-hw + t, -f, hd - t), Vector3(-dw, h, hd))
	_add_box_geom(main, Vector3(dw, -f, hd - t), Vector3(hw - t, h, hd))
	_add_box_geom(main, Vector3(-dw, dh, hd - t), Vector3(dw, h, hd))
	# Spitzbogen: zwei Dreiecke füllen den Raum zwischen dem geraden Türteil (bis spring_y) und
	# dem Scheitel (Mitte, dh) — die Öffnung darunter läuft oben spitz zu.
	_add_tri_prism_z(main, Vector2(-dw, spring_y), Vector2(-dw, dh), Vector2(0.0, dh), hd - t, hd)
	_add_tri_prism_z(main, Vector2(dw, spring_y), Vector2(0.0, dh), Vector2(dw, dh), hd - t, hd)

	# Giebeldreiecke vorn und hinten (Spitze knapp unter der Dachunterseite, damit nichts
	# durchsticht).
	var apex_y: float = ridge_y - CHAPEL_ROOF_THICKNESS
	_add_tri_prism_z(main, Vector2(-hw, h), Vector2(hw, h), Vector2(0.0, apex_y), hd - t, hd)
	_add_tri_prism_z(main, Vector2(-hw, h), Vector2(hw, h), Vector2(0.0, apex_y), -hd, -hd + t)

	# Satteldach: zwei Platten (First entlang Z) mit Überstand seitlich und vorn/hinten.
	var slope: float = CHAPEL_ROOF_RISE / hw
	var eave_x: float = hw + CHAPEL_ROOF_OVERHANG
	var eave_y: float = h - CHAPEL_ROOF_OVERHANG * slope
	var z0: float = -(hd + CHAPEL_ROOF_OVERHANG_Z)
	var z1: float = hd + CHAPEL_ROOF_OVERHANG_Z
	var th: float = CHAPEL_ROOF_THICKNESS
	for side: float in [-1.0, 1.0]:
		var l0 := Vector3(side * eave_x, eave_y - th, z0)
		var l1 := Vector3(0.0, ridge_y - th, z0)
		var l2 := Vector3(0.0, ridge_y - th, z1)
		var l3 := Vector3(side * eave_x, eave_y - th, z1)
		var u0 := Vector3(side * eave_x, eave_y, z0)
		var u1 := Vector3(0.0, ridge_y, z0)
		var u2 := Vector3(0.0, ridge_y, z1)
		var u3 := Vector3(side * eave_x, eave_y, z1)
		if side < 0.0:
			_add_hexahedron(accent, l0, l1, l2, l3, u0, u1, u2, u3)
		else:
			_add_hexahedron(accent, l1, l0, l3, l2, u1, u0, u3, u2)

	# Altar an der Rückwand mit zwei Kerzen (Leuchtfläche).
	var altar_z0: float = -hd + t
	_add_box_geom(main, Vector3(-0.35, CHAPEL_FLOOR_TOP, altar_z0), Vector3(0.35, 0.9, altar_z0 + 0.4))
	_add_box_geom(glow, Vector3(-0.28, 0.9, altar_z0 + 0.1), Vector3(-0.22, 1.05, altar_z0 + 0.16))
	_add_box_geom(glow, Vector3(0.22, 0.9, altar_z0 + 0.1), Vector3(0.28, 1.05, altar_z0 + 0.16))

	# Leuchtende Fenster: außen auf den Seitenwänden, innen auf der Rückwand.
	var win_y0: float = maxf(h * 0.5, 1.1)
	var win_y1: float = minf(win_y0 + 0.7, h - 0.35)
	_add_box_geom(glow, Vector3(-hw - 0.02, win_y0, -0.22), Vector3(-hw + 0.02, win_y1, 0.22))
	_add_box_geom(glow, Vector3(hw - 0.02, win_y0, -0.22), Vector3(hw + 0.02, win_y1, 0.22))
	_add_box_geom(glow, Vector3(-0.2, win_y0 + 0.1, -hd + t - 0.02), Vector3(0.2, win_y1 + 0.1, -hd + t + 0.02))

	# Dachreiter auf dem First: vier Pfosten + Deckplatte, Glocke, Zeltdach, Kreuz.
	var t_z: float = CHAPEL_TURRET_Z
	var t_post: float = CHAPEL_TURRET_POST_HALF
	var t_half: float = CHAPEL_TURRET_HALF
	var t_base: float = ridge_y - 0.25
	var t_top: float = ridge_y + CHAPEL_TURRET_POST_HEIGHT
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_box_geom(main,
				Vector3(sx * t_half - t_post, t_base, t_z + sz * t_half - t_post),
				Vector3(sx * t_half + t_post, t_top, t_z + sz * t_half + t_post))
	_add_box_geom(main, Vector3(-t_half - t_post, t_top - 0.06, t_z - t_half - t_post), Vector3(t_half + t_post, t_top, t_z + t_half + t_post))
	_add_box_geom(accent, Vector3(-0.07, ridge_y + 0.12, t_z - 0.07), Vector3(0.07, ridge_y + 0.4, t_z + 0.07))
	var cap_apex: float = t_top + CHAPEL_TURRET_CAP_HEIGHT
	_add_pyramid(accent, 0.0, t_z, t_half + 0.1, t_half + 0.1, t_top, cap_apex)
	_add_box_geom(accent, Vector3(-0.02, cap_apex, t_z - 0.02), Vector3(0.02, cap_apex + CHAPEL_TURRET_CROSS_HEIGHT, t_z + 0.02))
	_add_box_geom(accent, Vector3(-0.1, cap_apex + 0.16, t_z - 0.02), Vector3(0.1, cap_apex + 0.2, t_z + 0.02))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	_commit_surface(glow, mesh)
	return mesh

## Sichtbare Geometrie eines Wegweisers (PropShape.SIGNPOST, Wunsch "Wegweiser"): Pfosten auf
## einem kleinen Sockel mit Spitzhaube und drei pfeilförmigen Schildern (SIGNPOST_BOARDS), die in
## verschiedene Richtungen zeigen. `height` = Pfostenhöhe inkl. Haube. Zwei Surfaces: 0 MAIN =
## Sockel/Pfosten/Haube, 1 ACCENT = Schilder. Die Blickrichtung/Ausrichtung stellt der Spieler
## über die Drehung (axis) ein. Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_signpost_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, SIGNPOST_MIN_HEIGHT)
	var ph: float = SIGNPOST_POST_HALF
	var fh: float = SIGNPOST_FOOT_HALF

	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()

	_add_box_geom(main, Vector3(-fh, -SIGNPOST_BURY, -fh), Vector3(fh, SIGNPOST_FOOT_TOP, fh))
	_add_box_geom(main, Vector3(-ph, SIGNPOST_FOOT_TOP, -ph), Vector3(ph, h - 0.1, ph))
	_add_pyramid(main, 0.0, 0.0, ph + 0.03, ph + 0.03, h - 0.1, h)

	for entry: Vector4 in SIGNPOST_BOARDS:
		_add_arrow_board(accent, h - entry.x, entry.w, SIGNPOST_BOARD_HALF_HEIGHT, SIGNPOST_BOARD_TIP,
			SIGNPOST_BOARD_HALF_THICKNESS, entry.y, deg_to_rad(entry.z))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Unter-/Oberkante des Laternenglases einer Straßenlaterne (x = Unterkante, y = Oberkante) in
## lokalen Metern — einzige Quelle für build_lamp_post_mesh() UND die Lichtposition
## (prop_light_offset()), damit das Licht immer mitten im Glas sitzt.
static func lamp_glass_bounds(lamp_height: float) -> Vector2:
	var h: float = maxf(lamp_height, LAMP_MIN_HEIGHT)
	return Vector2(h - LAMP_LANTERN_SPAN + LAMP_BASE_PLATE, h - LAMP_CAP_DROP)

## Sichtbare Geometrie einer Straßenlaterne (PropShape.LAMP_POST, Wunsch "Straßenlaternen"):
## Sockel, schlanker Pfosten mit Leiterstrebe, Laterne aus Bodenplatte, vier Eckstreben um ein
## leuchtendes Glas (Surface GLOW), Deckplatte, Zeltdach und Zierspitze. `height` = Gesamthöhe
## bis zur Spitze. Zwei Surfaces: 0 MAIN = Gestell, 1 GLOW = Glas. Gemeinsame Quelle für
## BuildPiece UND BuildGhost.
static func build_lamp_post_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, LAMP_MIN_HEIGHT)
	var lantern_y: float = h - LAMP_LANTERN_SPAN
	var glass: Vector2 = lamp_glass_bounds(h)
	var fh: float = LAMP_FOOT_HALF

	var main: SurfaceTool = _begin_flat_surface()
	var glow: SurfaceTool = _begin_flat_surface()

	# Sockel (zweistufig) und Pfosten mit Leiterstrebe (Querholz, an dem früher die Leiter hing).
	_add_box_geom(main, Vector3(-fh, -0.3, -fh), Vector3(fh, 0.25, fh))
	_add_box_geom(main, Vector3(-0.12, 0.25, -0.12), Vector3(0.12, 0.4, 0.12))
	_add_box_geom(main, Vector3(-0.055, 0.4, -0.055), Vector3(0.055, lantern_y - 0.12, 0.055))
	_add_box_geom(main, Vector3(-0.22, lantern_y - 0.4, -0.02), Vector3(0.22, lantern_y - 0.36, 0.02))

	# Laterne: Kragen, Bodenplatte, Glas + vier Eckstreben, Deckplatte, Zeltdach, Zierspitze.
	_add_box_geom(main, Vector3(-0.08, lantern_y - 0.12, -0.08), Vector3(0.08, lantern_y, 0.08))
	_add_box_geom(main, Vector3(-0.17, lantern_y, -0.17), Vector3(0.17, lantern_y + LAMP_BASE_PLATE, 0.17))
	_add_box_geom(glow, Vector3(-0.13, glass.x, -0.13), Vector3(0.13, glass.y, 0.13))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_box_geom(main,
				Vector3(sx * 0.14 - 0.02, glass.x, sz * 0.14 - 0.02),
				Vector3(sx * 0.14 + 0.02, glass.y, sz * 0.14 + 0.02))
	_add_box_geom(main, Vector3(-0.22, glass.y, -0.22), Vector3(0.22, glass.y + 0.04, 0.22))
	_add_pyramid(main, 0.0, 0.0, 0.22, 0.22, glass.y + 0.04, h - 0.08)
	_add_box_geom(main, Vector3(-0.03, h - 0.08, -0.03), Vector3(0.03, h, 0.03))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(glow, mesh)
	return mesh

## Neuer SurfaceTool mit FLACHER Schattierung (smooth group -1) — die Requisiten mit mehreren
## Flächen bestehen aus vielen kleinen Quadern, bei denen die Standard-Glättung von
## generate_normals() die Kanten verwischen würde.
static func _begin_flat_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st

## Hängt die Geometrie eines SurfaceTools als NÄCHSTE Surface an `mesh` (Reihenfolge = Reihenfolge
## der Aufrufe = prop_surface_roles()).
static func _commit_surface(st: SurfaceTool, mesh: ArrayMesh) -> void:
	st.generate_normals()
	st.commit(mesh)

## Hexaeder aus acht beliebigen Punkten: Unterseite a-b-c-d (Umlauf), Oberseite e-f-g-h (e über a
## usw.) — wie _add_box_geom(), aber für schiefe Körper (Dachplatten).
static func _add_hexahedron(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		e: Vector3, f: Vector3, g: Vector3, h: Vector3) -> void:
	_add_quad(st, d, c, b, a)   # unten
	_add_quad(st, e, f, g, h)   # oben
	_add_quad(st, a, b, f, e)
	_add_quad(st, c, d, h, g)
	_add_quad(st, b, c, g, f)
	_add_quad(st, d, a, e, h)

## Dreiecksprisma: Dreieck (p0,p1,p2 in der XY-Ebene) zwischen z0 und z1 extrudiert — Giebel und
## Spitzbogen-Füllung der Kapelle.
static func _add_tri_prism_z(st: SurfaceTool, p0: Vector2, p1: Vector2, p2: Vector2, z0: float, z1: float) -> void:
	var a0 := Vector3(p0.x, p0.y, z0)
	var b0 := Vector3(p1.x, p1.y, z0)
	var c0 := Vector3(p2.x, p2.y, z0)
	var a1 := Vector3(p0.x, p0.y, z1)
	var b1 := Vector3(p1.x, p1.y, z1)
	var c1 := Vector3(p2.x, p2.y, z1)
	_add_tri(st, a1, b1, c1)
	_add_tri(st, c0, b0, a0)
	_add_quad(st, a0, b0, b1, a1)
	_add_quad(st, b0, c0, c1, b1)
	_add_quad(st, c0, a0, a1, c1)

## Vierseitige Pyramide mit beliebiger Mitte (cx,cz) und Halbkanten (hx,hz) — wie
## _add_pyramid_roof(), aber nicht auf den Ursprung festgelegt, plus Bodenfläche. Haube des
## Dachreiters, Zeltdach der Laterne, Spitzhaube des Wegweisers.
static func _add_pyramid(st: SurfaceTool, cx: float, cz: float, hx: float, hz: float, base_y: float, apex_y: float) -> void:
	var apex := Vector3(cx, apex_y, cz)
	var c0 := Vector3(cx - hx, base_y, cz - hz)
	var c1 := Vector3(cx + hx, base_y, cz - hz)
	var c2 := Vector3(cx + hx, base_y, cz + hz)
	var c3 := Vector3(cx - hx, base_y, cz + hz)
	_add_tri(st, c0, c1, apex)
	_add_tri(st, c1, c2, apex)
	_add_tri(st, c2, c3, apex)
	_add_tri(st, c3, c0, apex)
	_add_quad(st, c3, c2, c1, c0)

## Pfeilförmiges Schild (Fünfeck: Rechteck + Spitze) in der XY-Ebene, `length` vom Pfosten aus
## entlang lokal X (`dir_sign` = +1/-1 wählt die Seite), `tip` = Länge der Pfeilspitze, `half_t` =
## halbe Dicke (Z). Das fertige Schild wird um `yaw` (Radiant) um Y gedreht und auf Höhe
## `center_y` gesetzt. Vorder-/Rückseite als Fächer (konvexes Fünfeck) + fünf Randquads.
static func _add_arrow_board(st: SurfaceTool, center_y: float, length: float, half_h: float, tip: float,
		half_t: float, dir_sign: float, yaw: float) -> void:
	var outline: Array[Vector2] = [
		Vector2(0.0, -half_h),
		Vector2(length - tip, -half_h),
		Vector2(length, 0.0),
		Vector2(length - tip, half_h),
		Vector2(0.0, half_h),
	]
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for p: Vector2 in outline:
		front.append(Vector3(p.x * dir_sign, center_y + p.y, half_t).rotated(Vector3.UP, yaw))
		back.append(Vector3(p.x * dir_sign, center_y + p.y, -half_t).rotated(Vector3.UP, yaw))
	for i in range(1, 4):
		_add_tri(st, front[0], front[i], front[i + 1])
		_add_tri(st, back[0], back[i + 1], back[i])
	for i in 5:
		var j: int = (i + 1) % 5
		_add_quad(st, back[i], back[j], front[j], front[i])

## Gesamthöhe eines Turms (PropShape.TOWER_ROUND/TOWER_SQUARE) von der Basis bis zur
## Dachspitze — Schaft (`shaft_height`) + Zinnenkranz (TOWER_MERLON_HEIGHT) + Dach
## (shaft_height * TOWER_ROOF_RATIO). Einzige Quelle für get_box_size()/get_box_center()
## UND build_tower_mesh(), damit die Hüllbox nie kürzer ist als die sichtbare Geometrie.
static func tower_total_height(shaft_height: float) -> float:
	var h: float = maxf(shaft_height, 0.6)
	return h + TOWER_MERLON_HEIGHT + h * TOWER_ROOF_RATIO

## Sichtbare Geometrie eines Turms (PropShape.TOWER_ROUND/TOWER_SQUARE, Wunsch "Türme rund und
## eckig"): dünnwandiger Schaft (Ring bzw. Rahmen, siehe TOWER_WALL_THICKNESS) von y=0 bis zur
## Zinnenbasis, ein umlaufender Wehrgang (Ringboden) mit Zinnenkranz obendrauf, gekrönt von
## einem Kegeldach (rund) bzw. Zeltdach (eckig). Gemeinsame Quelle für BuildPiece (fertiges
## Bauteil) UND BuildGhost (Vorschau) — siehe build_prop_mesh().
static func build_tower_mesh(height: float, is_round: bool) -> ArrayMesh:
	var shaft_top: float = maxf(height, 0.6)
	var merlon_top: float = shaft_top + TOWER_MERLON_HEIGHT
	var roof_apex_y: float = merlon_top + shaft_top * TOWER_ROOF_RATIO
	var r_out: float = TOWER_RADIUS
	var r_in: float = maxf(TOWER_RADIUS - TOWER_WALL_THICKNESS, 0.15)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if is_round:
		_add_ring_wall(st, r_out, shaft_top, TOWER_ROUND_SEGMENTS)
		_add_ring_wall(st, r_in, shaft_top, TOWER_ROUND_SEGMENTS)
		_add_ring_annulus(st, r_out, r_in, shaft_top, TOWER_ROUND_SEGMENTS)
		_add_round_merlons(st, r_in, r_out, shaft_top, merlon_top)
		_add_cone_roof(st, r_out, merlon_top, roof_apex_y, TOWER_ROUND_SEGMENTS)
	else:
		_add_square_ring_wall(st, r_out, shaft_top)
		_add_square_ring_wall(st, r_in, shaft_top)
		_add_square_annulus(st, r_out, r_in, shaft_top)
		_add_square_merlons(st, r_in, r_out, shaft_top, merlon_top)
		_add_pyramid_roof(st, r_out, merlon_top, roof_apex_y)

	st.generate_normals()
	return st.commit()

## Gesamthöhe einer Windmühle (PropShape.WINDMILL) von der Basis bis zur Dachspitze — Schaft
## (`shaft_height`) + Kappe (shaft_height * WINDMILL_CAP_RATIO), ODER bis zur Flügelspitze, falls
## die Flügel (an der Nabe auf WINDMILL_HUB_Y_RATIO * shaft_height) höher hinausragen als das Dach
## — je nachdem, was größer ist. Einzige Quelle für get_box_size()/get_box_center() UND
## build_windmill_mesh(), wie tower_total_height() beim Turm.
static func windmill_total_height(shaft_height: float) -> float:
	var h: float = maxf(shaft_height, 1.0)
	var cap_apex: float = h + h * WINDMILL_CAP_RATIO
	var blade_apex: float = h * WINDMILL_HUB_Y_RATIO + WINDMILL_BLADE_LENGTH
	return maxf(cap_apex, blade_apex)

## Sichtbare Geometrie einer Windmühle (PropShape.WINDMILL, Wunsch "Strukturen und shapes ...
## große Struktur"): schlanker runder Schaft (einwandig, wie build_well_mesh()'s Ringmauer —
## keine begehbare Innenseite nötig, siehe Kind.TARGET-Kommentar) mit Kegeldach, plus ein
## Flügelkreuz aus Nabe (kleiner Würfel) und vier Armen (zwei gekreuzte Balken) an der Vorderseite
## (lokal +Z, dieselbe Blickrichtungs-Konvention wie build_target_mesh()/build_lamp_post_mesh()).
## Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_windmill_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, 1.0)
	var r: float = WINDMILL_RADIUS
	var cap_apex: float = h + h * WINDMILL_CAP_RATIO

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_ring_wall(st, r, h, WINDMILL_SEGMENTS)
	_add_cone_roof(st, r, h, cap_apex, WINDMILL_SEGMENTS)

	var hub_y: float = h * WINDMILL_HUB_Y_RATIO
	var hub_z: float = r + WINDMILL_HUB_HALF
	var hh: float = WINDMILL_HUB_HALF
	_add_box_geom(st, Vector3(-hh, hub_y - hh, hub_z - hh), Vector3(hh, hub_y + hh, hub_z + hh))

	var bw: float = WINDMILL_BLADE_HALF_WIDTH
	var bt: float = WINDMILL_BLADE_HALF_THICK
	var bl: float = WINDMILL_BLADE_LENGTH
	# Senkrechter Arm (oben/unten) + waagrechter Arm (links/rechts) — zusammen ein Flügelkreuz,
	# beide in derselben lotrechten Ebene bei hub_z stehend (kein Rotationscode nötig).
	_add_box_geom(st, Vector3(-bw, hub_y - bl, hub_z - bt), Vector3(bw, hub_y + bl, hub_z + bt))
	_add_box_geom(st, Vector3(-bl, hub_y - bw, hub_z - bt), Vector3(bl, hub_y + bw, hub_z + bt))

	st.generate_normals()
	return st.commit()

## Gesamthöhe einer Sonnenuhr (PropShape.SUNDIAL) von der Basis bis zur Gnomon-Spitze — Sockel
## bis Scheibenoberkante (`height`) plus die vertikale Auskragung des schrägen Gnomons (siehe
## build_sundial_mesh()). Einzige Quelle für get_box_size()/get_box_center() UND
## build_sundial_mesh(), wie windmill_total_height()/tower_total_height().
static func sundial_total_height(height: float) -> float:
	var h: float = maxf(height, 0.5)
	var gnomon_len: float = SUNDIAL_DIAL_RADIUS * SUNDIAL_GNOMON_LENGTH_RATIO
	return h + gnomon_len * 0.7

## Sichtbare Geometrie einer Sonnenuhr (PropShape.SUNDIAL, Wunsch "... kleine gimmicks"):
## zylindrischer Sockel, eine waagrechte Zifferblatt-Scheibe (Kreis-Fächer wie build_target_mesh(),
## nur in der XZ- statt der XY-Ebene, Normale nach oben) und ein schräger Gnomon von der
## Scheibenmitte zu einem Punkt über dem Scheibenrand (_add_strut(), derselbe Helfer wie die
## Standbeine der Zielscheibe). Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_sundial_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, 0.5)
	var base_r: float = SUNDIAL_BASE_RADIUS
	var dial_r: float = SUNDIAL_DIAL_RADIUS

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_ring_wall(st, base_r, h, SUNDIAL_BASE_SEGMENTS)

	# Zifferblatt: Kreis-Fächer bei y=h, beidseitig sichtbar wie die Zielscheibe.
	var center := Vector3(0.0, h, 0.0)
	var prev := Vector3(dial_r, h, 0.0)
	for i in range(1, SUNDIAL_DIAL_SEGMENTS + 1):
		var a: float = TAU * float(i) / float(SUNDIAL_DIAL_SEGMENTS)
		var cur := Vector3(cos(a) * dial_r, h, sin(a) * dial_r)
		_add_tri(st, center, prev, cur)
		_add_tri(st, center, cur, prev)
		prev = cur

	# Gnomon: schräger Balken von der Scheibenmitte zu einem Punkt über dem Rand (lokal -Z —
	# dieselbe Blickrichtungs-Konvention wie bei den anderen Requisiten).
	var gnomon_len: float = dial_r * SUNDIAL_GNOMON_LENGTH_RATIO
	var apex := Vector3(0.0, h + gnomon_len * 0.7, -gnomon_len * 0.5)
	_add_strut(st, Vector3(0.0, h, 0.0), apex, SUNDIAL_GNOMON_HALF_THICK)

	st.generate_normals()
	return st.commit()

## Gesamthöhe eines Torturms (PropShape.GATEHOUSE) von der Basis bis zur Dachspitze — `height`
## als Turmstumpf-Höhe bis zur Zinnenbasis (wie tower_total_height()), mindestens
## GATEHOUSE_MIN_HEIGHT (muss Durchfahrt + Sturz aufnehmen). Einzige Quelle für
## get_box_size()/get_box_center() UND build_gatehouse_mesh().
static func gatehouse_total_height(height: float) -> float:
	var h: float = maxf(height, GATEHOUSE_MIN_HEIGHT)
	return h + TOWER_MERLON_HEIGHT + h * TOWER_ROOF_RATIO

## Sichtbare Geometrie eines Torturms (PropShape.GATEHOUSE, Wunsch "Richtung Burg"): zwei
## Pfeiler + Sturzbalken bilden eine Durchfahrt an der Basis (offen entlang lokal Z — vorn UND
## hinten, siehe Klassenkommentar), darüber ein massiver quadratischer Turmstumpf mit
## Zinnenkranz (_add_square_merlons(), wie TOWER_SQUARE) und Zeltdach (_add_pyramid_roof()).
## Gemeinsame Quelle für BuildPiece UND BuildGhost.
static func build_gatehouse_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, GATEHOUSE_MIN_HEIGHT)
	var hw: float = GATEHOUSE_HALF_WIDTH
	var pw: float = GATEHOUSE_PASSAGE_HALF_WIDTH
	var ph: float = GATEHOUSE_PASSAGE_HEIGHT
	var lintel_top: float = ph + GATEHOUSE_LINTEL_THICKNESS
	var merlon_top: float = h + TOWER_MERLON_HEIGHT
	var roof_apex: float = merlon_top + h * TOWER_ROOF_RATIO

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Durchfahrt: zwei Pfeiler (links/rechts der Öffnung, volle Turmtiefe) + Sturz darüber —
	# die Öffnung selbst (|x| < pw) bleibt über die volle Tiefe frei, vorn UND hinten begehbar.
	_add_box_geom(st, Vector3(-hw, 0.0, -hw), Vector3(-pw, ph, hw))
	_add_box_geom(st, Vector3(pw, 0.0, -hw), Vector3(hw, ph, hw))
	_add_box_geom(st, Vector3(-hw, ph, -hw), Vector3(hw, lintel_top, hw))

	# Turmstumpf über dem Sturz (massiver Block statt hohler Schaft — er sitzt bereits auf der
	# Durchfahrt, ein zusätzlicher hohler Innenraum brächte hier keinen Mehrwert), Zinnenkranz
	# und Zeltdach obendrauf.
	_add_box_geom(st, Vector3(-hw, lintel_top, -hw), Vector3(hw, h, hw))
	_add_square_merlons(st, hw - TOWER_WALL_THICKNESS, hw, h, merlon_top)
	_add_pyramid_roof(st, hw, merlon_top, roof_apex)

	st.generate_normals()
	return st.commit()

## Gesamthöhe einer Belagerungswaffe (PropShape.CATAPULT) von der Basis bis zur höchsten Stelle
## (Wurfarm-Spitze) — Drehpunkt (halbe Gestellhöhe) + Wurfarm-Auskragung. Einzige Quelle für
## get_box_size()/get_box_center() UND build_catapult_mesh().
static func catapult_total_height(height: float) -> float:
	var h: float = maxf(height, 1.0)
	var pivot_y: float = h * 0.5
	return pivot_y + CATAPULT_ARM_LENGTH * 0.8 + CATAPULT_BUCKET_HALF

## Sichtbare Geometrie einer Belagerungswaffe (PropShape.CATAPULT, Wunsch "Richtung Burg"):
## vierbeiniges Gestell (vier Streben von den Bodenecken zu einem gemeinsamen Drehpunkt,
## _add_strut() wie die Standbeine von build_target_mesh()), eine Achse am Drehpunkt, ein
## Wurfarm nach vorn-oben mit Schleuderkorb an der Spitze sowie ein Gegengewichtsarm nach
## hinten-unten mit Gewichtsblock — eine feste "gespannte" Pose statt Animation. Gemeinsame
## Quelle für BuildPiece UND BuildGhost.
static func build_catapult_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, 1.0)
	var sw: float = CATAPULT_STAND_HALF_WIDTH
	var bh: float = CATAPULT_BEAM_HALF
	var pivot_y: float = h * 0.5
	var pivot := Vector3(0.0, pivot_y, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Vierbeiniges Gestell: von jeder Bodenecke schräg zum gemeinsamen Drehpunkt.
	_add_strut(st, Vector3(-sw, 0.0, -sw), pivot, bh)
	_add_strut(st, Vector3(sw, 0.0, -sw), pivot, bh)
	_add_strut(st, Vector3(-sw, 0.0, sw), pivot, bh)
	_add_strut(st, Vector3(sw, 0.0, sw), pivot, bh)
	# Achsblock am Drehpunkt.
	_add_box_geom(st, pivot - Vector3(bh * 1.5, bh, bh * 1.5), pivot + Vector3(bh * 1.5, bh, bh * 1.5))

	# Wurfarm: schräg nach vorn-oben (lokal +Z, dieselbe Blickrichtungs-Konvention wie bei den
	# anderen Requisiten) zum Schleuderkorb.
	var arm_len: float = CATAPULT_ARM_LENGTH
	var bucket := Vector3(0.0, pivot_y + arm_len * 0.8, arm_len * 0.5)
	_add_strut(st, pivot, bucket, bh * 0.8)
	var bkh: float = CATAPULT_BUCKET_HALF
	_add_box_geom(st, bucket - Vector3(bkh, bkh, bkh), bucket + Vector3(bkh, bkh, bkh))

	# Gegengewichtsarm: schräg nach hinten-unten (lokal -Z) zum Gewichtsblock.
	var counterweight := Vector3(0.0, pivot_y - arm_len * 0.35, -arm_len * 0.35)
	_add_strut(st, pivot, counterweight, bh * 0.8)
	var cwh: float = CATAPULT_COUNTERWEIGHT_HALF
	_add_box_geom(st, counterweight - Vector3(cwh, cwh, cwh), counterweight + Vector3(cwh, cwh, cwh))

	st.generate_normals()
	return st.commit()

## Unter-/Oberkante (y) der Feueröffnung eines Hochofens (PropShape.FURNACE). Einzige Quelle für
## build_furnace_mesh() UND prop_light_offset().
static func furnace_mouth_bounds(height: float) -> Vector2:
	var h: float = maxf(height, FURNACE_MIN_HEIGHT)
	return Vector2(h * FURNACE_MOUTH_LOW_RATIO, h * FURNACE_MOUTH_HIGH_RATIO)

## Sichtbare Geometrie eines Hochofens (PropShape.FURNACE, Schmelz-Station): Steinsockel + Körper
## mit umlaufendem Sims, Schornstein darüber, Feueröffnung in der +Z-Front (leuchtende Fläche, GLOW)
## mit eisernem Sturz und Pfosten (ACCENT) sowie eine Aschenschale vor der Öffnung. Drei Surfaces
## in der Reihenfolge MAIN, ACCENT, GLOW (siehe prop_surface_roles()). Gemeinsame Quelle für
## BuildPiece UND BuildGhost.
static func build_furnace_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, FURNACE_MIN_HEIGHT)
	var hw: float = FURNACE_HALF_WIDTH
	var hd: float = FURNACE_HALF_DEPTH
	var body_top: float = h * FURNACE_BODY_RATIO
	var ch: float = FURNACE_CHIMNEY_HALF
	var mouth: Vector2 = furnace_mouth_bounds(h)
	var mw: float = FURNACE_MOUTH_HALF_WIDTH

	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var glow: SurfaceTool = _begin_flat_surface()

	# Sockel (leicht breiter, taucht unter y=0 ein wie die anderen Requisiten) + Körper + Sims.
	_add_box_geom(main, Vector3(-hw - 0.06, -0.15, -hd - 0.06), Vector3(hw + 0.06, 0.1, hd + 0.06))
	_add_box_geom(main, Vector3(-hw, 0.1, -hd), Vector3(hw, body_top, hd))
	_add_box_geom(main, Vector3(-hw - 0.05, body_top, -hd - 0.05), Vector3(hw + 0.05, body_top + 0.07, hd + 0.05))
	# Schornstein: etwas nach hinten versetzt, mit schmalem Kragen.
	var cz: float = -hd * 0.3
	_add_box_geom(main, Vector3(-ch, body_top + 0.07, cz - ch), Vector3(ch, h - 0.08, cz + ch))
	_add_box_geom(main, Vector3(-ch - 0.04, h - 0.08, cz - ch - 0.04), Vector3(ch + 0.04, h, cz + ch + 0.04))

	# Eisenrahmen der Feueröffnung: Sturz + zwei Pfosten, leicht vor der Frontfläche.
	var fz: float = hd
	_add_box_geom(accent, Vector3(-mw - 0.08, mouth.y, fz - 0.01), Vector3(mw + 0.08, mouth.y + 0.08, fz + 0.05))
	_add_box_geom(accent, Vector3(-mw - 0.08, mouth.x, fz - 0.01), Vector3(-mw, mouth.y, fz + 0.05))
	_add_box_geom(accent, Vector3(mw, mouth.x, fz - 0.01), Vector3(mw + 0.08, mouth.y, fz + 0.05))
	# Aschenschale vor der Öffnung. Bewusst nur 0,08 m tief: die Hüllbox (±FURNACE_HALF_DEPTH) soll
	# die sichtbare Geometrie bis auf Kleinigkeiten abdecken, sonst läuft man durch die Schale.
	_add_box_geom(accent, Vector3(-mw, 0.1, fz), Vector3(mw, mouth.x, fz + 0.08))

	# Glut: Fläche in der Öffnung (minimal vor der Front, damit sie nicht z-fightet).
	_add_box_geom(glow, Vector3(-mw, mouth.x, fz - 0.02), Vector3(mw, mouth.y, fz + 0.02))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	_commit_surface(glow, mesh)
	return mesh

## Sichtbare Geometrie eines Ambosses (PropShape.ANVIL, Schmiede-Station): Holzstumpf (ACCENT) als
## Sockel, darauf Fuß, schmale Taille und die Bahn (MAIN); das Horn läuft stufenweise verjüngt nach
## +X aus. `height` = Gesamthöhe inkl. Stumpf. Zwei Surfaces: MAIN, ACCENT.
static func build_anvil_mesh(height: float) -> ArrayMesh:
	var h: float = maxf(height, ANVIL_MIN_HEIGHT)
	var stump_top: float = h * 0.5
	var fl: float = ANVIL_FACE_HALF_LENGTH
	var fd: float = ANVIL_FACE_HALF_DEPTH
	var sh: float = ANVIL_STUMP_HALF

	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()

	_add_box_geom(accent, Vector3(-sh, -0.05, -sh), Vector3(sh, stump_top, sh))

	var foot_top: float = stump_top + h * 0.1
	var waist_top: float = foot_top + h * 0.14
	var face_top: float = h
	_add_box_geom(main, Vector3(-fl * 0.7, stump_top, -fd * 0.9), Vector3(fl * 0.7, foot_top, fd * 0.9))
	_add_box_geom(main, Vector3(-fl * 0.35, foot_top, -fd * 0.55), Vector3(fl * 0.35, waist_top, fd * 0.55))
	_add_box_geom(main, Vector3(-fl, waist_top, -fd), Vector3(fl, face_top, fd))
	# Horn: zwei Stufen, jeweils schmaler und flacher.
	var horn: float = ANVIL_HORN_LENGTH
	_add_box_geom(main, Vector3(fl, waist_top + (face_top - waist_top) * 0.25, -fd * 0.7), Vector3(fl + horn * 0.55, face_top, fd * 0.7))
	_add_box_geom(main, Vector3(fl + horn * 0.55, waist_top + (face_top - waist_top) * 0.55, -fd * 0.4), Vector3(fl + horn, face_top, fd * 0.4))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## true für die Handwerks-/Kleinigkeiten-Requisiten (PropShape.BARREL ... FIREPIT, TROUGH ... WEAPON_RACK) — gemeinsame Quelle für
## die Hüllbox-Zweige in get_box_size()/get_box_center().
static func is_craft_prop(shape: int) -> bool:
	return shape in [
		PropShape.BARREL, PropShape.MARKET_STALL, PropShape.BAKE_OVEN, PropShape.WORKBENCH,
		PropShape.CRATE, PropShape.SACKS, PropShape.BENCH, PropShape.TABLE,
		PropShape.CART, PropShape.BANNER, PropShape.PILLAR, PropShape.FIREPIT,
		PropShape.TROUGH, PropShape.WOODPILE, PropShape.GARDEN_BED, PropShape.SCARECROW,
		PropShape.WEAPON_RACK,
	]

## Gesamthöhe einer Handwerks-Requisite: `height`, aber mindestens die Mindesthöhe der Form.
## Einzige Quelle für build_..._mesh() UND die Hüllbox (get_box_size()/get_box_center()).
static func craft_prop_height(shape: int, height: float) -> float:
	match shape:
		PropShape.BARREL:
			return maxf(height, CRAFT_BARREL_MIN_HEIGHT)
		PropShape.MARKET_STALL:
			return maxf(height, CRAFT_STALL_MIN_HEIGHT)
		PropShape.BAKE_OVEN:
			return maxf(height, CRAFT_OVEN_MIN_HEIGHT)
		PropShape.WORKBENCH:
			return maxf(height, CRAFT_BENCH_MIN_HEIGHT)
		PropShape.CRATE:
			return maxf(height, CRAFT_CRATE_MIN_HEIGHT)
		PropShape.SACKS:
			return maxf(height, CRAFT_SACKS_MIN_HEIGHT)
		PropShape.BENCH:
			return maxf(height, CRAFT_BENCH2_MIN_HEIGHT)
		PropShape.TABLE:
			return maxf(height, CRAFT_TABLE_MIN_HEIGHT)
		PropShape.CART:
			return maxf(height, CRAFT_CART_MIN_HEIGHT)
		PropShape.BANNER:
			return maxf(height, CRAFT_BANNER_MIN_HEIGHT)
		PropShape.PILLAR:
			return maxf(height, CRAFT_PILLAR_MIN_HEIGHT)
		PropShape.FIREPIT:
			return maxf(height, CRAFT_FIREPIT_MIN_HEIGHT)
		PropShape.TROUGH:
			return maxf(height, CRAFT_TROUGH_MIN_HEIGHT)
		PropShape.WOODPILE:
			return maxf(height, CRAFT_WOODPILE_MIN_HEIGHT)
		PropShape.GARDEN_BED:
			return maxf(height, CRAFT_GARDEN_BED_MIN_HEIGHT)
		PropShape.SCARECROW:
			return maxf(height, CRAFT_SCARECROW_MIN_HEIGHT)
		PropShape.WEAPON_RACK:
			return maxf(height, CRAFT_WEAPON_RACK_MIN_HEIGHT)
		_:
			return height

## Grundfläche einer Handwerks-Requisite als Hüllbox-Maß (x = Breite entlang lokal X, y = Tiefe
## entlang lokal Z), um den Ursprung zentriert. Das Mesh bleibt innerhalb dieser Fläche. Alle
## Maße passen in eine Zelle (BuildGrid.CELL = 2 m), damit Nachbarzellen frei bleiben.
static func craft_prop_footprint(shape: int) -> Vector2:
	match shape:
		PropShape.BARREL:
			return Vector2(0.75, 0.75)
		PropShape.MARKET_STALL:
			return Vector2(1.9, 1.4)
		PropShape.BAKE_OVEN:
			return Vector2(1.2, 1.1)
		PropShape.WORKBENCH:
			return Vector2(1.7, 0.75)
		PropShape.CRATE:
			return Vector2(1.1, 0.8)
		PropShape.SACKS:
			return Vector2(1.1, 0.6)
		PropShape.BENCH:
			return Vector2(1.5, 0.5)
		PropShape.TABLE:
			return Vector2(1.1, 1.4)
		PropShape.CART:
			return Vector2(1.1, 1.9)
		PropShape.BANNER:
			return Vector2(0.9, 0.4)
		PropShape.PILLAR:
			return Vector2(0.6, 0.6)
		PropShape.FIREPIT:
			return Vector2(1.0, 1.0)
		PropShape.TROUGH:
			return Vector2(1.6, 0.6)
		PropShape.WOODPILE:
			return Vector2(1.5, 0.9)
		PropShape.GARDEN_BED:
			return Vector2(1.6, 1.2)
		PropShape.SCARECROW:
			return Vector2(1.0, 0.5)
		PropShape.WEAPON_RACK:
			return Vector2(1.6, 0.5)
		_:
			return Vector2(TARGET_RADIUS * 2.2, TARGET_RADIUS * 1.4)

## Sichtbare Geometrie eines Fasses (PropShape.BARREL): bauchiger Körper aus BARREL_SLICES
## Bändern mit parabelförmigem Radiusverlauf (Enden BARREL_END_RADIUS, Mitte BARREL_MID_RADIUS),
## Deckel, dazu zwei Reifen leicht über der Außenhaut. Surfaces: 0 MAIN = Dauben + Deckel,
## 1 ACCENT = Reifen. `height` = Gesamthöhe.
static func build_barrel_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.BARREL, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var radii: Array[float] = []
	for i in BARREL_SLICES + 1:
		var t: float = 2.0 * float(i) / float(BARREL_SLICES) - 1.0
		radii.append(BARREL_END_RADIUS + (BARREL_MID_RADIUS - BARREL_END_RADIUS) * (1.0 - t * t))
	for i in BARREL_SLICES:
		var y0: float = h * float(i) / float(BARREL_SLICES)
		var y1: float = h * float(i + 1) / float(BARREL_SLICES)
		_add_ring_band(main, radii[i], y0, radii[i + 1], y1, BARREL_SEGMENTS)
		if i == 1 or i == BARREL_SLICES - 2:
			_add_ring_band(accent, radii[i] + BARREL_HOOP_GROW, y0,
				radii[i + 1] + BARREL_HOOP_GROW, y1, BARREL_SEGMENTS)
	_add_cone_roof(main, BARREL_END_RADIUS, h, h, BARREL_SEGMENTS)   # flacher Deckel

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Sichtbare Geometrie eines Marktstands (PropShape.MARKET_STALL, Wunsch "Händler"): Tresen aus
## Front-/Seitenbrettern mit Platte, drei Warenkisten, zwei hohe Hinterpfosten, zwei niedrigere
## Vorderpfosten und ein schräges Stoffdach (Surface 1 ACCENT), das vorn über den Tresen ragt.
## Surface 0 MAIN = Holz + Waren. `height` = Oberkante der hinteren Pfosten. Kundenseite = lokal +Z.
static func build_market_stall_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.MARKET_STALL, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var hx: float = 0.85
	var hz: float = 0.45
	var counter_h: float = 0.75
	var back_y: float = h - 0.06
	var front_y: float = h - 0.36

	# Tresen: Frontbrett, zwei Seitenbretter, Platte.
	_add_box_geom(main, Vector3(-hx, 0.0, hz - 0.1), Vector3(hx, counter_h - 0.05, hz))
	_add_box_geom(main, Vector3(-hx, 0.0, -hz), Vector3(-hx + 0.08, counter_h - 0.05, hz))
	_add_box_geom(main, Vector3(hx - 0.08, 0.0, -hz), Vector3(hx, counter_h - 0.05, hz))
	_add_box_geom(main, Vector3(-hx - 0.02, counter_h - 0.07, -hz), Vector3(hx + 0.02, counter_h, hz + 0.04))

	# Waren auf dem Tresen.
	_add_box_geom(main, Vector3(-0.65, counter_h, -0.15), Vector3(-0.3, counter_h + 0.2, 0.2))
	_add_box_geom(main, Vector3(-0.2, counter_h, -0.1), Vector3(0.1, counter_h + 0.13, 0.2))
	_add_box_geom(main, Vector3(0.3, counter_h, -0.2), Vector3(0.7, counter_h + 0.25, 0.25))

	# Pfosten: hinten bis zur Gesamthöhe, vorn bis zur Unterkante des Dachs.
	for px: float in [-hx + 0.04, hx - 0.04]:
		_add_box_geom(main, Vector3(px - 0.04, 0.0, -hz), Vector3(px + 0.04, h, -hz + 0.08))
		_add_box_geom(main, Vector3(px - 0.04, 0.0, 0.56), Vector3(px + 0.04, front_y, 0.64))

	# Schräges Stoffdach: hinten hoch, vorn tief, 0.05 dick.
	var q0 := Vector3(-0.95, back_y, -0.5)
	var q1 := Vector3(0.95, back_y, -0.5)
	var q2 := Vector3(0.95, front_y, 0.7)
	var q3 := Vector3(-0.95, front_y, 0.7)
	var lift := Vector3(0.0, 0.05, 0.0)
	_add_hexahedron(accent, q0, q1, q2, q3, q0 + lift, q1 + lift, q2 + lift, q3 + lift)

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Sichtbare Geometrie eines Backofens (PropShape.BAKE_OVEN, Wunsch "Bäcker"): gemauerter Sockel,
## darauf eine gestufte Kuppel (OVEN_DOME_SLICES Bänder, Radius nach Kreisbogen), Rauchabzug an
## der Rückseite und vorn eine glühende Ofenöffnung mit Sturz und Laibung. Surfaces: 0 MAIN =
## Stein, 1 GLOW = Glut. `height` = Spitze des Rauchabzugs. Öffnung = lokal +Z.
static func build_bake_oven_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.BAKE_OVEN, height)
	var main: SurfaceTool = _begin_flat_surface()
	var glow: SurfaceTool = _begin_flat_surface()
	var plinth: float = OVEN_PLINTH_HEIGHT
	var dome_top: float = maxf(h * 0.78, plinth + 0.5)
	var radius: float = OVEN_DOME_RADIUS

	_add_box_geom(main, Vector3(-0.6, 0.0, -0.55), Vector3(0.6, plinth, 0.55))

	var prev_r: float = radius
	var prev_y: float = plinth
	for k in range(1, OVEN_DOME_SLICES):
		var t: float = float(k) / float(OVEN_DOME_SLICES)
		var r: float = radius * sqrt(1.0 - t * t)
		var y: float = plinth + (dome_top - plinth) * t
		_add_ring_band(main, prev_r, prev_y, r, y, OVEN_DOME_SEGMENTS)
		prev_r = r
		prev_y = y
	_add_cone_roof(main, prev_r, prev_y, dome_top, OVEN_DOME_SEGMENTS)

	_add_box_geom(main, Vector3(-0.1, plinth + 0.3, -0.5), Vector3(0.1, h, -0.3))

	# Ofenöffnung: Glut, Sturz, zwei Laibungen.
	_add_box_geom(glow, Vector3(-0.17, plinth + 0.07, 0.43), Vector3(0.17, plinth + 0.3, 0.52))
	_add_box_geom(main, Vector3(-0.22, plinth + 0.3, 0.42), Vector3(0.22, plinth + 0.38, 0.54))
	_add_box_geom(main, Vector3(-0.22, plinth + 0.05, 0.42), Vector3(-0.17, plinth + 0.3, 0.54))
	_add_box_geom(main, Vector3(0.17, plinth + 0.05, 0.42), Vector3(0.22, plinth + 0.3, 0.54))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(glow, mesh)
	return mesh

## Sichtbare Geometrie einer Werkbank (PropShape.WORKBENCH, Wunsch "Zimmermann/Tischler"):
## Platte auf vier Beinen mit unterem Ablageboden; auf der Platte links ein Schraubstock, rechts ein
## Hammer (beides Surface 1 ACCENT). Surface 0 MAIN = Holz. `height` = Oberkante des Schraubstocks.
static func build_workbench_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.WORKBENCH, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var hx: float = 0.8
	var hz: float = 0.33
	var top_y: float = h * 0.8

	_add_box_geom(main, Vector3(-hx, top_y - 0.08, -hz), Vector3(hx, top_y, hz))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lx: float = sx * (hx - 0.1)
			var lz: float = sz * (hz - 0.07)
			_add_box_geom(main, Vector3(lx - 0.05, 0.0, lz - 0.05), Vector3(lx + 0.05, top_y - 0.08, lz + 0.05))
	_add_box_geom(main, Vector3(-hx + 0.1, h * 0.2, -hz + 0.04), Vector3(hx - 0.1, h * 0.2 + 0.04, hz - 0.04))

	# Schraubstock (Körper + Backe) und Hammer (Stiel + Kopf) als Werkzeug-Akzent.
	_add_box_geom(accent, Vector3(-hx + 0.02, top_y, -0.1), Vector3(-hx + 0.22, h, 0.1))
	_add_box_geom(accent, Vector3(-hx + 0.22, top_y + 0.05, -0.08), Vector3(-hx + 0.3, h - 0.03, 0.08))
	_add_box_geom(accent, Vector3(0.15, top_y, -0.04), Vector3(0.55, top_y + 0.04, 0.0))
	_add_box_geom(accent, Vector3(0.5, top_y, -0.08), Vector3(0.6, top_y + 0.1, 0.04))

	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Kistenstapel (PropShape.CRATE, Kleinigkeit für Lager/Hafen/Markt): große Kiste links, mittlere
## rechts, kleine oben auf der großen; Eckleisten der großen Kiste als Akzent. Surfaces: 0 MAIN =
## Kisten, 1 ACCENT = Eckleisten. `height` = Oberkante des Stapels.
static func build_crate_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.CRATE, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var big_top: float = h * 0.55
	_add_box_geom(main, Vector3(-0.35, 0.0, -0.3), Vector3(0.15, big_top, 0.2))
	_add_box_geom(main, Vector3(0.2, 0.0, -0.2), Vector3(0.55, h * 0.4, 0.25))
	_add_box_geom(main, Vector3(-0.3, big_top, -0.25), Vector3(0.05, h, 0.1))
	for cx: float in [-0.35, 0.15]:
		for cz: float in [-0.3, 0.2]:
			_add_box_geom(accent, Vector3(cx - 0.025, 0.0, cz - 0.025), Vector3(cx + 0.025, big_top, cz + 0.025))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Ein einzelner Sack aus drei verjüngten Quadern (Bauch, Schulter, Hals) — Hilfe für
## build_sacks_mesh(). `r` = halbe Bauchbreite, `y0` = Standhöhe, `hs` = Sackhöhe.
static func _add_sack(st: SurfaceTool, cx: float, cz: float, r: float, y0: float, hs: float) -> void:
	_add_box_geom(st, Vector3(cx - r, y0, cz - r), Vector3(cx + r, y0 + hs * 0.6, cz + r))
	_add_box_geom(st, Vector3(cx - r * 0.85, y0 + hs * 0.6, cz - r * 0.85), Vector3(cx + r * 0.85, y0 + hs * 0.88, cz + r * 0.85))
	_add_box_geom(st, Vector3(cx - r * 0.4, y0 + hs * 0.88, cz - r * 0.4), Vector3(cx + r * 0.4, y0 + hs, cz + r * 0.4))

## Sackstapel (PropShape.SACKS, Kleinigkeit für Mühle/Bäcker/Lager): zwei Säcke nebeneinander,
## einer obendrauf, Halsbinden als Akzent. Surfaces: 0 MAIN = Säcke, 1 ACCENT = Binden.
static func build_sacks_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.SACKS, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var sacks: Array[Vector4] = [
		Vector4(-0.28, 0.0, 0.24, 0.0),
		Vector4(0.24, -0.05, 0.24, 0.0),
		Vector4(-0.02, 0.0, 0.22, h * 0.45),
	]
	for s: Vector4 in sacks:
		var hs: float = h * 0.6 if s.w == 0.0 else h - s.w
		_add_sack(main, s.x, s.y, s.z, s.w, hs)
		_add_box_geom(accent, Vector3(s.x - s.z * 0.45, s.w + hs * 0.86, s.y - s.z * 0.45),
			Vector3(s.x + s.z * 0.45, s.w + hs * 0.92, s.y + s.z * 0.45))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Sitzbank mit Lehne (PropShape.BENCH): Sitzbrett auf zwei Wangen, zwei Lehnenpfosten, zwei
## Lehnenbretter. Eine Surface (MAIN). Lehne = lokal -Z (man sitzt mit Blick nach +Z).
## `height` = Oberkante der Lehne.
static func build_bench_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.BENCH, height)
	var main: SurfaceTool = _begin_flat_surface()
	var seat_y: float = h * 0.5
	_add_box_geom(main, Vector3(-0.7, seat_y - 0.06, -0.2), Vector3(0.7, seat_y, 0.2))
	for sx: float in [-1.0, 1.0]:
		_add_box_geom(main, Vector3(sx * 0.6 - 0.04, 0.0, -0.17), Vector3(sx * 0.6 + 0.04, seat_y - 0.06, 0.17))
		_add_box_geom(main, Vector3(sx * 0.62 - 0.03, seat_y, -0.2), Vector3(sx * 0.62 + 0.03, h, -0.14))
	_add_box_geom(main, Vector3(-0.7, seat_y + 0.1, -0.2), Vector3(0.7, seat_y + 0.16, -0.14))
	_add_box_geom(main, Vector3(-0.7, h - 0.07, -0.2), Vector3(0.7, h, -0.14))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	return mesh

## Tisch mit zwei Hockern (PropShape.TABLE): Platte auf vier Beinen, je ein Hocker (Surface 1
## ACCENT) vor und hinter der langen Seite. `height` = Tischplattenoberkante.
static func build_table_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.TABLE, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	_add_box_geom(main, Vector3(-0.5, h - 0.06, -0.28), Vector3(0.5, h, 0.28))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_box_geom(main, Vector3(sx * 0.42 - 0.04, 0.0, sz * 0.2 - 0.04),
				Vector3(sx * 0.42 + 0.04, h - 0.06, sz * 0.2 + 0.04))
	var stool_y: float = h * 0.5
	for sz: float in [-1.0, 1.0]:
		var zc: float = sz * 0.52
		_add_box_geom(accent, Vector3(-0.16, stool_y - 0.05, zc - 0.16), Vector3(0.16, stool_y, zc + 0.16))
		_add_box_geom(accent, Vector3(-0.06, 0.0, zc - 0.06), Vector3(0.06, stool_y - 0.05, zc + 0.06))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Scheibenrad mit Achse entlang lokal X von x0 bis x1 (Mitte cy/cz, Radius r) — Mantel aus
## Quads, zwei Fächer als Seitenflächen. Hilfe für build_cart_mesh().
static func _add_wheel_x(st: SurfaceTool, x0: float, x1: float, cy: float, cz: float, r: float, segments: int) -> void:
	for i in segments:
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var p0 := Vector3(x0, cy + cos(a0) * r, cz + sin(a0) * r)
		var p1 := Vector3(x0, cy + cos(a1) * r, cz + sin(a1) * r)
		var q0 := Vector3(x1, p0.y, p0.z)
		var q1 := Vector3(x1, p1.y, p1.z)
		_add_quad(st, p0, p1, q1, q0)
		_add_tri(st, Vector3(x0, cy, cz), p1, p0)
		_add_tri(st, Vector3(x1, cy, cz), q0, q1)

## Handkarren (PropShape.CART): Ladefläche mit vier niedrigen Bordwänden, Achse, zwei Räder
## (Surface 1 ACCENT) und zwei Deichselgriffe nach +Z. Ist `height` größer als die Bordwand
## (CRAFT_CART_MIN_HEIGHT), türmt sich Ladung bis `height` auf (Heu, Fässer ...).
static func build_cart_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.CART, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var bed_y: float = 0.42
	var rim: float = CRAFT_CART_MIN_HEIGHT
	_add_box_geom(main, Vector3(-0.4, bed_y, -0.6), Vector3(0.4, bed_y + 0.06, 0.6))
	_add_box_geom(main, Vector3(-0.4, bed_y + 0.06, -0.6), Vector3(-0.36, rim, 0.6))
	_add_box_geom(main, Vector3(0.36, bed_y + 0.06, -0.6), Vector3(0.4, rim, 0.6))
	_add_box_geom(main, Vector3(-0.36, bed_y + 0.06, 0.56), Vector3(0.36, rim, 0.6))
	_add_box_geom(main, Vector3(-0.36, bed_y + 0.06, -0.6), Vector3(0.36, rim, -0.56))
	if h > rim:
		_add_box_geom(main, Vector3(-0.34, bed_y + 0.06, -0.54), Vector3(0.34, h, 0.54))
	_add_box_geom(main, Vector3(-0.46, 0.27, -0.03), Vector3(0.46, 0.33, 0.03))
	for sx: float in [-1.0, 1.0]:
		_add_box_geom(main, Vector3(sx * 0.28 - 0.03, bed_y, 0.6), Vector3(sx * 0.28 + 0.03, bed_y + 0.06, 0.95))
		var xa: float = 0.42 if sx > 0.0 else -0.5
		_add_wheel_x(accent, xa, xa + 0.08, 0.3, 0.0, CART_WHEEL_RADIUS, CART_WHEEL_SEGMENTS)
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Fahnenmast (PropShape.BANNER): Sockel, Mast mit Spitze, Querstange und hängendes Tuch mit
## Schwalbenschwanz (Surface 1 ACCENT — Farbvarianten nur als Daten). `height` = Spitze.
static func build_banner_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.BANNER, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	_add_box_geom(main, Vector3(-0.15, 0.0, -0.15), Vector3(0.15, 0.15, 0.15))
	_add_box_geom(main, Vector3(-0.04, 0.15, -0.04), Vector3(0.04, h - 0.1, 0.04))
	_add_box_geom(main, Vector3(-0.4, h - 0.28, -0.03), Vector3(0.4, h - 0.22, 0.03))
	_add_pyramid(main, 0.0, 0.0, 0.07, 0.07, h - 0.1, h)
	var cloth_h: float = minf(1.1, h * 0.4)
	var cloth_top: float = h - 0.28
	_add_box_geom(accent, Vector3(-0.34, cloth_top - cloth_h, -0.015), Vector3(0.34, cloth_top, 0.015))
	_add_box_geom(accent, Vector3(-0.17, cloth_top - cloth_h - 0.2, -0.015), Vector3(0.17, cloth_top - cloth_h, 0.015))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Säule (PropShape.PILLAR, Grundform für Tore, Hallen, Kolonnaden): quadratischer Sockel,
## leicht verjüngter Rundschaft, Kapitell und Deckplatte. Eine Surface (MAIN); Stein oder Holz
## ergibt sich aus der Farbe der .tres. `height` = Oberkante der Deckplatte.
static func build_pillar_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.PILLAR, height)
	var main: SurfaceTool = _begin_flat_surface()
	_add_box_geom(main, Vector3(-0.28, 0.0, -0.28), Vector3(0.28, 0.15, 0.28))
	_add_ring_band(main, 0.2, 0.15, 0.17, h - 0.18, PILLAR_SEGMENTS)
	_add_box_geom(main, Vector3(-0.26, h - 0.18, -0.26), Vector3(0.26, h - 0.1, 0.26))
	_add_box_geom(main, Vector3(-0.3, h - 0.1, -0.3), Vector3(0.3, h, 0.3))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	return mesh

## Feuerstelle (PropShape.FIREPIT): Steinring, zwei gekreuzte Holzscheite (Surface 1 ACCENT),
## Glut und eine einfache Flamme (Surface 2 GLOW). Wirft KEIN Licht (light_range bleibt 0 — Lichter
## sind teuer, siehe Laternen-Kommentar), leuchtet aber emissiv. `height` = Flammenspitze.
static func build_firepit_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.FIREPIT, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var glow: SurfaceTool = _begin_flat_surface()
	var r: float = FIREPIT_RADIUS
	_add_ring_band(main, r, 0.0, r, 0.22, FIREPIT_SEGMENTS)
	_add_ring_annulus(main, r, r - 0.14, 0.22, FIREPIT_SEGMENTS)
	_add_ring_band(main, r - 0.14, 0.22, r - 0.14, 0.0, FIREPIT_SEGMENTS)
	_add_box_geom(accent, Vector3(-0.4, 0.07, -0.05), Vector3(0.4, 0.15, 0.05))
	_add_box_geom(accent, Vector3(-0.05, 0.15, -0.4), Vector3(0.05, 0.23, 0.4))
	_add_cone_roof(glow, r - 0.16, 0.08, 0.08, FIREPIT_SEGMENTS)
	_add_pyramid(glow, 0.0, 0.0, 0.16, 0.16, 0.15, h)
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	_commit_surface(glow, mesh)
	return mesh

## Futter-/Wassertrog (PropShape.TROUGH, Stall und Hof): offener Holzkasten auf zwei Kufen, darin
## eine Füllung (Surface 1 ACCENT — Wasserblau, Heugelb oder Korn, nur Daten). `height` = Trogrand.
static func build_trough_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.TROUGH, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var hx: float = 0.8
	var hz: float = 0.3
	var wall: float = 0.07
	var base_y: float = 0.1
	_add_box_geom(main, Vector3(-hx, base_y, -hz), Vector3(hx, base_y + 0.06, hz))
	_add_box_geom(main, Vector3(-hx, base_y + 0.06, -hz), Vector3(hx, h, -hz + wall))
	_add_box_geom(main, Vector3(-hx, base_y + 0.06, hz - wall), Vector3(hx, h, hz))
	_add_box_geom(main, Vector3(-hx, base_y + 0.06, -hz + wall), Vector3(-hx + wall, h, hz - wall))
	_add_box_geom(main, Vector3(hx - wall, base_y + 0.06, -hz + wall), Vector3(hx, h, hz - wall))
	for sx: float in [-1.0, 1.0]:
		_add_box_geom(main, Vector3(sx * (hx - 0.2) - 0.06, 0.0, -hz), Vector3(sx * (hx - 0.2) + 0.06, base_y, hz))
	_add_box_geom(accent, Vector3(-hx + wall, base_y + 0.06, -hz + wall), Vector3(hx - wall, h - 0.1, hz - wall))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Holzstapel (PropShape.WOODPILE, Zimmerei/Hof/Wachstube): drei Lagen Scheite quer zur Blickrichtung
## (3 / 2 / 1 Stück, wie ein Dreieck gestapelt), Schnittflächen als Akzent (Surface 1 ACCENT, helles
## Holz), seitliche Stützpfosten. `height` = Oberkante der obersten Lage.
static func build_woodpile_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.WOODPILE, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var t: float = h / 3.0
	var hx: float = 0.66
	var hz: float = 0.42
	for layer in 3:
		var count: int = 3 - layer
		var w: float = (hz * 2.0) / 3.0
		var z0: float = -hz + (3 - count) * w * 0.5
		for i in count:
			var zl: float = z0 + float(i) * w
			_add_box_geom(main, Vector3(-hx, t * layer, zl + 0.015), Vector3(hx, t * (layer + 1), zl + w - 0.015))
			# Schnittflächen als flache Kappen leicht vor den Enden (bleiben innerhalb der Grundfläche).
			_add_box_geom(accent, Vector3(hx - 0.02, t * layer + 0.03, zl + 0.04), Vector3(hx, t * (layer + 1) - 0.03, zl + w - 0.04))
	for sx: float in [-1.0, 1.0]:
		_add_box_geom(main, Vector3(sx * (hx + 0.04) - 0.04, 0.0, -hz), Vector3(sx * (hx + 0.04) + 0.04, h * 0.7, -hz + 0.08))
		_add_box_geom(main, Vector3(sx * (hx + 0.04) - 0.04, 0.0, hz - 0.08), Vector3(sx * (hx + 0.04) + 0.04, h * 0.7, hz))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Hochbeet (PropShape.GARDEN_BED, Kräuter-/Gemüsegarten): Holzrahmen mit Erde (MAIN) und je drei mal
## drei Pflanzbüschel (Surface 1 ACCENT — Kräutergrün, Blütenfarbe oder Kohlgrün über die .tres).
## `height` = Oberkante der höchsten Pflanze.
static func build_garden_bed_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.GARDEN_BED, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var hx: float = 0.8
	var hz: float = 0.6
	var rim: float = 0.22
	var wall: float = 0.06
	_add_box_geom(main, Vector3(-hx, 0.0, -hz), Vector3(hx, rim - 0.05, hz))
	_add_box_geom(main, Vector3(-hx, 0.0, -hz), Vector3(hx, rim, -hz + wall))
	_add_box_geom(main, Vector3(-hx, 0.0, hz - wall), Vector3(hx, rim, hz))
	_add_box_geom(main, Vector3(-hx, 0.0, -hz + wall), Vector3(-hx + wall, rim, hz - wall))
	_add_box_geom(main, Vector3(hx - wall, 0.0, -hz + wall), Vector3(hx, rim, hz - wall))
	for ix in 3:
		for iz in 3:
			var cx: float = (float(ix) - 1.0) * 0.45
			var cz: float = (float(iz) - 1.0) * 0.32
			# Mittlere Pflanze am höchsten, Rand niedriger — Oberkante exakt `h` in der Mitte.
			var top: float = h if (ix == 1 and iz == 1) else rim + (h - rim) * (0.55 + 0.15 * float((ix + iz) % 3))
			_add_pyramid(accent, cx, cz, 0.14, 0.12, rim - 0.05, top)
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Vogelscheuche (PropShape.SCARECROW, Feld/Hof): Pfahl mit Querholz, Strohkörper (MAIN), Kopf,
## Hut und Hemd-Fetzen (Surface 1 ACCENT). `height` = Hutspitze.
static func build_scarecrow_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.SCARECROW, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var arm_y: float = h * 0.68
	_add_box_geom(main, Vector3(-0.04, 0.0, -0.04), Vector3(0.04, h * 0.86, 0.04))
	_add_box_geom(main, Vector3(-0.48, arm_y - 0.03, -0.03), Vector3(0.48, arm_y + 0.03, 0.03))
	_add_box_geom(main, Vector3(-0.17, arm_y - 0.5, -0.1), Vector3(0.17, arm_y + 0.04, 0.1))
	_add_box_geom(main, Vector3(-0.1, h * 0.7, -0.1), Vector3(0.1, h * 0.86, 0.1))
	# Hut: breite Krempe + Spitze; Hemd als Tuch über Körper und Armen.
	_add_box_geom(accent, Vector3(-0.22, h * 0.86, -0.22), Vector3(0.22, h * 0.86 + 0.03, 0.22))
	_add_pyramid(accent, 0.0, 0.0, 0.12, 0.12, h * 0.86 + 0.03, h)
	_add_box_geom(accent, Vector3(-0.36, arm_y - 0.12, -0.05), Vector3(0.36, arm_y + 0.04, 0.05))
	_add_box_geom(accent, Vector3(-0.19, arm_y - 0.35, -0.12), Vector3(0.19, arm_y - 0.12, 0.12))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Waffenständer (PropShape.WEAPON_RACK, Wachposten/Kaserne): zwei Pfosten mit Querholmen, fünf
## Speere mit Eisenspitzen (Surface 1 ACCENT) und ein Rundschild-Brett in der Mitte. Blick = +Z.
## `height` = Spitze der Speere.
static func build_weapon_rack_mesh(height: float) -> ArrayMesh:
	var h: float = craft_prop_height(PropShape.WEAPON_RACK, height)
	var main: SurfaceTool = _begin_flat_surface()
	var accent: SurfaceTool = _begin_flat_surface()
	var hx: float = 0.75
	var post_top: float = h * 0.62
	for sx: float in [-1.0, 1.0]:
		_add_box_geom(main, Vector3(sx * hx - 0.05, 0.0, -0.2), Vector3(sx * hx + 0.05, post_top, -0.1))
	_add_box_geom(main, Vector3(-hx, post_top - 0.12, -0.2), Vector3(hx, post_top, -0.1))
	_add_box_geom(main, Vector3(-hx, h * 0.3, -0.2), Vector3(hx, h * 0.3 + 0.08, -0.1))
	_add_box_geom(main, Vector3(-hx, 0.0, -0.22), Vector3(hx, 0.08, 0.22))
	for i in 5:
		var sx2: float = (float(i) - 2.0) * 0.28
		if i == 2:
			continue
		var tip_y: float = h - 0.2 - 0.06 * float(i % 2)
		_add_box_geom(main, Vector3(sx2 - 0.02, 0.08, -0.05), Vector3(sx2 + 0.02, tip_y, -0.01))
		_add_pyramid(accent, sx2, -0.03, 0.04, 0.04, tip_y, tip_y + 0.2)
	# Mittlerer Speer ragt am höchsten und legt die Gesamthöhe fest.
	_add_box_geom(main, Vector3(-0.02, 0.08, -0.05), Vector3(0.02, h - 0.2, -0.01))
	_add_pyramid(accent, 0.0, -0.03, 0.04, 0.04, h - 0.2, h)
	# Schild vor der unteren Querstrebe.
	_add_box_geom(accent, Vector3(-0.3, h * 0.12, -0.08), Vector3(0.3, h * 0.12 + 0.55, -0.04))
	var mesh := ArrayMesh.new()
	_commit_surface(main, mesh)
	_commit_surface(accent, mesh)
	return mesh

## Seitenwand eines Kegelstumpfs (Außenhaut) von Radius `r0` bei y0 nach Radius `r1` bei y1 —
## wie _add_ring_wall(), nur mit wechselndem Radius. Fass (Bauch, Reifen) und Backofenkuppel.
static func _add_ring_band(st: SurfaceTool, r0: float, y0: float, r1: float, y1: float, segments: int) -> void:
	var prev_a := Vector3(r0, y0, 0.0)
	var prev_b := Vector3(r1, y1, 0.0)
	for i in range(1, segments + 1):
		var ang: float = TAU * float(i) / float(segments)
		var cur_a := Vector3(cos(ang) * r0, y0, sin(ang) * r0)
		var cur_b := Vector3(cos(ang) * r1, y1, sin(ang) * r1)
		_add_quad(st, prev_a, cur_a, cur_b, prev_b)
		prev_a = cur_a
		prev_b = cur_b

## Zylindrische Ringwand (Außenhaut, wie build_well_mesh()'s Ringmauer, nur allgemein für
## beliebigen Radius/Höhe) — zweimal genutzt (Außen-/Innenwand des Turmschafts).
static func _add_ring_wall(st: SurfaceTool, radius: float, top: float, segments: int) -> void:
	var prev_a := Vector3(radius, 0.0, 0.0)
	var prev_b := Vector3(radius, top, 0.0)
	for i in range(1, segments + 1):
		var ang: float = TAU * float(i) / float(segments)
		var cur_a := Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
		var cur_b := Vector3(cos(ang) * radius, top, sin(ang) * radius)
		_add_quad(st, prev_a, cur_a, cur_b, prev_b)
		prev_a = cur_a
		prev_b = cur_b

## Kreisring-Boden bei Höhe `y` zwischen Außen- und Innenradius — schließt den Schaft nach
## oben ab (Wehrgang, auf dem die Zinnen stehen).
static func _add_ring_annulus(st: SurfaceTool, r_out: float, r_in: float, y: float, segments: int) -> void:
	var prev_o := Vector3(r_out, y, 0.0)
	var prev_i := Vector3(r_in, y, 0.0)
	for i in range(1, segments + 1):
		var ang: float = TAU * float(i) / float(segments)
		var cur_o := Vector3(cos(ang) * r_out, y, sin(ang) * r_out)
		var cur_i := Vector3(cos(ang) * r_in, y, sin(ang) * r_in)
		_add_quad(st, prev_o, cur_o, cur_i, prev_i)
		prev_o = cur_o
		prev_i = cur_i

## Zinnenkranz (rund): TOWER_MERLON_COUNT radiale Blöcke, gleichmäßig verteilt, jeder nimmt
## TOWER_MERLON_DUTY seines Sektors ein (Rest = Zinnenlücke/Schießscharte).
static func _add_round_merlons(st: SurfaceTool, r_in: float, r_out: float, y0: float, y1: float) -> void:
	var sector: float = TAU / float(TOWER_MERLON_COUNT)
	var half_w: float = sector * TOWER_MERLON_DUTY * 0.5
	for i in TOWER_MERLON_COUNT:
		var center: float = sector * float(i)
		_add_radial_block(st, r_in, r_out, y0, y1, center - half_w, center + half_w)

## Ein einzelner Zinnenblock (rund) als radialer Keil zwischen zwei Winkeln — Außen-/Innen-/
## Ober-/zwei Stirnflächen, jeweils ein Quad.
static func _add_radial_block(st: SurfaceTool, r_in: float, r_out: float, y0: float, y1: float, a0: float, a1: float) -> void:
	var b0o := Vector3(cos(a0) * r_out, y0, sin(a0) * r_out)
	var b1o := Vector3(cos(a1) * r_out, y0, sin(a1) * r_out)
	var b0i := Vector3(cos(a0) * r_in, y0, sin(a0) * r_in)
	var b1i := Vector3(cos(a1) * r_in, y0, sin(a1) * r_in)
	var t0o := Vector3(cos(a0) * r_out, y1, sin(a0) * r_out)
	var t1o := Vector3(cos(a1) * r_out, y1, sin(a1) * r_out)
	var t0i := Vector3(cos(a0) * r_in, y1, sin(a0) * r_in)
	var t1i := Vector3(cos(a1) * r_in, y1, sin(a1) * r_in)
	_add_quad(st, b0o, b1o, t1o, t0o)   # außen
	_add_quad(st, b1i, b0i, t0i, t1i)   # innen
	_add_quad(st, t0o, t1o, t1i, t0i)   # oben
	_add_quad(st, b0i, b0o, t0o, t0i)   # Stirnseite a0
	_add_quad(st, b1o, b1i, t1i, t1o)   # Stirnseite a1

## Kegeldach (rund): Fächer aus Dreiecken von der Traufe (Kreis bei y=base) zur Spitze.
static func _add_cone_roof(st: SurfaceTool, radius: float, base_y: float, apex_y: float, segments: int) -> void:
	var apex := Vector3(0.0, apex_y, 0.0)
	var prev := Vector3(radius, base_y, 0.0)
	for i in range(1, segments + 1):
		var ang: float = TAU * float(i) / float(segments)
		var cur := Vector3(cos(ang) * radius, base_y, sin(ang) * radius)
		_add_tri(st, apex, prev, cur)
		prev = cur

## Quadratische Ringwand (Außenhaut, wie _add_ring_wall() nur eckig): vier Quads entlang der
## Kanten eines Quadrats mit halber Kantenlänge `half`.
static func _add_square_ring_wall(st: SurfaceTool, half: float, top: float) -> void:
	var c0 := Vector2(-half, -half)
	var c1 := Vector2(half, -half)
	var c2 := Vector2(half, half)
	var c3 := Vector2(-half, half)
	var corners: Array[Vector2] = [c0, c1, c2, c3, c0]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		_add_quad(st, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y),
			Vector3(b.x, top, b.y), Vector3(a.x, top, a.y))

## Quadratischer Rahmenboden bei Höhe `y` zwischen Außen- und Innenkante — der eckige
## Wehrgang, Gegenstück zu _add_ring_annulus().
static func _add_square_annulus(st: SurfaceTool, r_out: float, r_in: float, y: float) -> void:
	var eps: float = 0.02
	_add_box_geom(st, Vector3(-r_out, y - eps, -r_out), Vector3(r_out, y, -r_in))
	_add_box_geom(st, Vector3(-r_out, y - eps, r_in), Vector3(r_out, y, r_out))
	_add_box_geom(st, Vector3(-r_out, y - eps, -r_in), Vector3(-r_in, y, r_in))
	_add_box_geom(st, Vector3(r_in, y - eps, -r_in), Vector3(r_out, y, r_in))

## Zinnenkranz (eckig): TOWER_MERLON_COUNT Blöcke gleichmäßig auf die vier Seiten verteilt,
## als achsenausgerichtete Boxen (das Quadrat macht eine radiale Keil-Konstruktion wie beim
## runden Turm unnötig) — je Seite dieselbe Formel wie _add_square_annulus() für die Kanten.
static func _add_square_merlons(st: SurfaceTool, r_in: float, r_out: float, y0: float, y1: float) -> void:
	var per_side: int = maxi(1, TOWER_MERLON_COUNT / 4)
	var span: float = 2.0 * r_out
	var seg: float = span / float(per_side)
	var half_w: float = seg * TOWER_MERLON_DUTY * 0.5
	for i in per_side:
		var c: float = -r_out + seg * (float(i) + 0.5)
		_add_box_geom(st, Vector3(c - half_w, y0, -r_out), Vector3(c + half_w, y1, -r_in))   # Nord
		_add_box_geom(st, Vector3(c - half_w, y0, r_in), Vector3(c + half_w, y1, r_out))     # Süd
		_add_box_geom(st, Vector3(-r_out, y0, c - half_w), Vector3(-r_in, y1, c + half_w))   # West
		_add_box_geom(st, Vector3(r_in, y0, c - half_w), Vector3(r_out, y1, c + half_w))     # Ost

## Zeltdach (eckig): vier Dreiecke von den Traufecken (Quadrat bei y=base) zur Spitze —
## Gegenstück zu _add_cone_roof(), siehe auch RoofShape.PYRAMID für dieselbe Grundform als
## Dach-Bauteil (dort First statt Eckpunkt-Fächer, aber gleiche Silhouette bei ridge=1).
static func _add_pyramid_roof(st: SurfaceTool, half: float, base_y: float, apex_y: float) -> void:
	var apex := Vector3(0.0, apex_y, 0.0)
	var c0 := Vector3(-half, base_y, -half)
	var c1 := Vector3(half, base_y, -half)
	var c2 := Vector3(half, base_y, half)
	var c3 := Vector3(-half, base_y, half)
	_add_tri(st, c0, c1, apex)
	_add_tri(st, c1, c2, apex)
	_add_tri(st, c2, c3, apex)
	_add_tri(st, c3, c0, apex)

## Schräger Balken (Standbein/Strebe) zwischen zwei Punkten, als sechsseitiges Prisma mit
## quadratischem Querschnitt (Kantenlänge 2*half). Anders als eine achsenausgerichtete Box
## (_add_box_geom) erlaubt das schräge Stützen ohne Rotationsmatrix: Boden- und Kopf-Rechteck
## werden unabhängig um `from`/`to` aufgespannt, die Seitenflächen verbinden die passenden Ecken
## — bei geneigten Beinen (wie hier) ergibt das ein leicht verjüngtes, aber optisch einwandfreies
## Stützbein. Gemeinsame Hilfsfunktion, nur von build_target_mesh() benutzt (Kandidat für
## weitere Requisiten mit Beinen/Streben).
static func _add_strut(st: SurfaceTool, from: Vector3, to: Vector3, half: float) -> void:
	var fa := from + Vector3(-half, 0.0, -half)
	var fb := from + Vector3(half, 0.0, -half)
	var fc := from + Vector3(half, 0.0, half)
	var fd := from + Vector3(-half, 0.0, half)
	var ta := to + Vector3(-half, 0.0, -half)
	var tb := to + Vector3(half, 0.0, -half)
	var tc := to + Vector3(half, 0.0, half)
	var td := to + Vector3(-half, 0.0, half)
	_add_quad(st, fd, fc, fb, fa)   # Fuß
	_add_quad(st, ta, tb, tc, td)   # Kopf
	_add_quad(st, fa, fb, tb, ta)   # -Z Seite
	_add_quad(st, fc, fd, td, tc)   # +Z Seite
	_add_quad(st, fb, fc, tc, tb)   # +X Seite
	_add_quad(st, fd, fa, ta, td)   # -X Seite

## Kombinierte Box-Geometrie aus mehreren {size, center}-Einträgen (Tür-/Fensterrahmen, siehe
## get_door_boxes()/get_window_boxes()) — EIN Mesh für den Geist (BuildGhost benutzt nur eine
## MeshInstance3D); das fertige BuildPiece rendert dieselben Boxen einzeln (siehe
## BuildPiece._add_framed()), mit je eigener Kollision.
static func build_framed_mesh(boxes: Array[Dictionary]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in boxes:
		var size: Vector3 = b["size"]
		var center: Vector3 = b["center"]
		var half: Vector3 = size * 0.5
		_add_box_geom(st, center - half, center + half)
	st.generate_normals()
	return st.commit()

## Achsenausgerichtete Box aus zwei Eckpunkten (lo/hi) als sechs Quads. Hilfsfunktion für
## build_stairs_mesh()/build_framed_mesh(), benutzt dieselben _add_quad()/_add_tri() wie
## build_roof_mesh().
static func _add_box_geom(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var a := Vector3(lo.x, lo.y, lo.z)
	var b := Vector3(hi.x, lo.y, lo.z)
	var c := Vector3(hi.x, lo.y, hi.z)
	var d := Vector3(lo.x, lo.y, hi.z)
	var e := Vector3(lo.x, hi.y, lo.z)
	var f := Vector3(hi.x, hi.y, lo.z)
	var g := Vector3(hi.x, hi.y, hi.z)
	var h := Vector3(lo.x, hi.y, hi.z)
	_add_quad(st, d, c, b, a)   # unten
	_add_quad(st, e, f, g, h)   # oben
	_add_quad(st, a, b, f, e)   # -Z Seite
	_add_quad(st, c, d, h, g)   # +Z Seite
	_add_quad(st, b, c, g, f)   # +X Seite
	_add_quad(st, d, a, e, h)   # -X Seite

## Rückgabemenge für ein Item beim Abreißen (abgerundet, nie mehr als investiert).
func refund_for(item_id: String) -> int:
	var spent: int = int(cost.get(item_id, 0))
	return mini(spent, int(floor(float(spent) * refund_ratio)))
