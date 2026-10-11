class_name AnimalVisualProfile
extends RefCounted

## AnimalVisualProfile — datengetriebene Beschreibung, wie EIN Tier aussieht.
##
## VORHER: AnimalVisualBuilder.build(color, body_size) baute für jede Tierart exakt
## dieselbe Silhouette (stehende Kapsel + Kugelkopf + 4 identische Beine, nur skaliert/
## eingefärbt) — Reh, Wildschwein und Hase unterschieden sich nur durch Größe und Farbe,
## nicht durch Form. Dieses Profil macht Kopf-/Schwanzmerkmale je Unterklasse
## konfigurierbar, OHNE dass jede Tierart ihre eigene Kopie der Geometrie-Erzeugung
## braucht — analog zu BuildPieceDefinition.PropShape (EIN Bauteil-Kind, viele
## Erscheinungsformen über ein Formfeld statt über Subklassen mit eigenem Zeichencode).
##
## AnimalBase-Unterklassen setzen in _on_ready_extended() weiterhin nur `_color` und
## `_body_size` (Kollisionsform bleibt unverändert!) und zusätzlich die Stil-Felder unten
## (`_ear_style` etc.) — AnimalBase baut daraus dieses Profil und reicht es an
## AnimalVisualBuilder.build() durch.

enum EarStyle { NONE, ROUND, POINTY, LONG, FLOPPY }
## THIN = langer, dünner Peitschenschwanz (Maus/Ratte) — ANS ENDE angehängt (Pet-Saves, s.u.).
enum TailStyle { NONE, STUB, BUSHY, FLUFFY, THIN }
enum SnoutStyle { NONE, SHORT, LONG }
## NEUE Enum-Mitglieder immer ANS ENDE anhängen: die Werte landen als int in Pet-Saves
## (PetComponent.get_save_state()) — ein Einfügen in der Mitte würde alte Saves umdeuten.
enum HeadgearStyle { NONE, ANTLERS, TUSKS, HORNS, BROAD_ANTLERS }

## Grundbauplan des Körpers (Wunsch "mehr Körper für Tiere: Insekten, Spinnen, Schlangen,
## Fische, große Säugetiere"). QUADRUPED ist der bisherige Vierbeiner (Rumpf + Kopf +
## 4 Beine) und bleibt der Default — damit ändert sich für alle bestehenden Tiere und alte
## Saves nichts. Die anderen Pläne haben eine komplett eigene Anatomie (siehe
## AnimalVisualBuilder._build_insect() usw.); Ohren/Schnauze/Kopfschmuck/Schwanz gelten nur
## für QUADRUPED.
enum BodyPlan { QUADRUPED, INSECT, SPIDER, SNAKE, FISH }

## Flügel für BodyPlan.INSECT: TRANSLUCENT (Biene/Libelle), SHELL (Käfer-Deckflügel),
## BROAD (Schmetterling).
enum WingStyle { NONE, TRANSLUCENT, SHELL, BROAD }

## Rückenmerkmal für BodyPlan.QUADRUPED: HUMP (Schulterbuckel: Bär/Elch/Bison),
## MANE (Nackenkamm/Mähne: Wolf).
enum BackStyle { NONE, HUMP, MANE }

## Wunsch "neue Shapes/Formen/Gliedmaßen für Tiere — Variationen": VORHER hatten alle
## QUADRUPED-Tiere exakt dieselben Rumpf-/Bein-PROPORTIONEN (nur über body_size skaliert,
## nicht in der FORM unterschieden) — ein Wolf und ein Bison unterschieden sich nur in
## Größe/Farbe, nie in Statur. BodyShape/LegStyle unten sind reine Proportions-Multiplikatoren
## (siehe AnimalVisualBuilder._body_shape_mults()/_leg_style_mults()), WIRKEN NUR auf
## BodyPlan.QUADRUPED (die anderen Baupläne haben ihre eigene, bereits arttypische Anatomie,
## siehe BodyPlan-Kommentar oben) und verändern wie body_plan/wing_style/back_style NIE die
## Kollisionskapsel (AnimalBase._body_size bleibt alleinige Quelle dafür).
## NORMAL = bisheriges Verhalten, unverändert für alle Tiere ohne expliziten Wert.
enum BodyShape { NORMAL, SLENDER, STOCKY, ROUND }
enum LegStyle { NORMAL, THIN, THICK, SHORT, LONG }

## Wunsch "ein bisschen um die Textur von Tieren kümmern": VORHER war jedes Tier einfarbig
## (StandardMaterial3D nur mit albedo_color, siehe ProcGenShapes.mat()) — ein Zebra und ein
## Pferd unterschieden sich nur in Farbe/Proportion, nie in der Fellzeichnung. pattern_style
## lässt AnimalVisualBuilder._build_body_material() zur Laufzeit eine kleine, prozedurale
## Textur erzeugen (Image/ImageTexture, KEINE externe Bilddatei nötig — siehe dortige
## Funktion) und auf den Rumpf legen, statt der reinen Flächenfarbe. Wirkt bewusst NUR auf
## BodyPlan.QUADRUPED (dieselbe Begründung wie bei BodyShape/LegStyle: die Rumpfkapsel ist
## die einzige Fläche, auf der sich ein Muster auf diesen kleinen, stilisierten Tieren
## überhaupt erkennbar abzeichnet). NONE = bisheriges Verhalten (reine Flächenfarbe).
enum PatternStyle { NONE, STRIPES, SPOTS, PATCHES }

## Wunsch "die Tiere sehen alle irgendwie gleich aus": VORHER hatten alle Fische/Schlangen/
## Spinnen/Insekten INNERHALB ihres Bauplans exakt dieselbe Form (nur Farbe/Größe anders) —
## eine Viper, eine Kobra und eine Ringelnatter waren dieselbe Röhre. AccentStyle ist EIN
## zusätzliches Merkmal je Tier, dessen Bedeutung vom body_plan abhängt (wie PropShape bei
## BuildPieceDefinition: ein Feld, viele Erscheinungsformen). Kombinationen, die für den
## jeweiligen Bauplan nichts bedeuten, werden ignoriert (kein Fehler). NONE = bisheriges
## Verhalten. NEUE Mitglieder immer ANS ENDE anhängen (Wert landet als int in Pet-Saves).
##   SNAKE:  TRIANGLE_HEAD (Viper: flacher Dreieckskopf), HOOD (Kobra: Nackenschild),
##           RATTLE (Klapperschlange: Dreieckskopf + Rassel am Schwanzende)
##   FISH:   BARBELS (Wels: Barteln), LONG_JAW (Hecht: Entenschnabel, Rückenflosse hinten),
##           RIBBON (Aal: langer Flossensaum statt Schwanz-/Rückenflosse)
##   SPIDER: BIG_EYES (Springspinne), ABDOMEN_MARK (Kreuzspinne: helle Hinterleibszeichnung),
##           STOUT (Vogelspinne: massive Beine)
##   INSECT: SPOTS (Marienkäfer: Punkte auf den Deckflügeln), STRIPES (Wespe: dunkle Ringe)
enum AccentStyle {
	NONE, TRIANGLE_HEAD, HOOD, RATTLE, BARBELS, LONG_JAW, RIBBON,
	BIG_EYES, ABDOMEN_MARK, STOUT, SPOTS, STRIPES,
}

var color: Color = Color(0.7, 0.5, 0.3)
## x = Körperbreite (Durchmesser), y = Höhe, z = Tiefe — dieselbe Konvention wie bisher.
## Für die neuen Bauplänen: INSECT/SPIDER x = Rumpfbreite (Brustabschnitt), y = Gesamthöhe;
## SNAKE x = Dicke, z = Gesamtlänge; FISH x = Breite, y = Höhe, z = Länge.
## AnimalBase._body_size (bleibt zusätzlich alleinige Quelle für die Kollisionskapsel,
## siehe AnimalBase._build_collision() — rein kosmetische Merkmale unten beeinflussen die
## Kollision bewusst nicht).
var body_size: Vector3 = Vector3(0.4, 0.6, 0.4)

var ear_style: int = EarStyle.ROUND
var tail_style: int = TailStyle.STUB
var snout_style: int = SnoutStyle.SHORT
var headgear_style: int = HeadgearStyle.NONE

## Zusätzlicher Größenfaktor nur für den Schwanz (z.B. Eichhörnchen: ikonischer,
## überproportional großer Schwanz) — ohne eigenes TailStyle-Enum-Mitglied pro Spezies.
var tail_scale: float = 1.0

var body_plan: int = BodyPlan.QUADRUPED
var wing_style: int = WingStyle.NONE
var back_style: int = BackStyle.NONE

var body_shape: int = BodyShape.NORMAL
var leg_style: int = LegStyle.NORMAL

var pattern_style: int = PatternStyle.NONE
var accent_style: int = AccentStyle.NONE
## Zweitfarbe des Musters (Streifen/Flecken/Flächen) — `color` bleibt die Grundfarbe/der
## Untergrund. Default dunkelgrau statt Schwarz: bei PatternStyle.NONE irrelevant (nie
## gelesen), bei versehentlich gesetztem Style ohne eigene pattern_color trotzdem ein
## plausibler Kontrast statt eines reinen Schwarz-Weiß-Klischees.
var pattern_color: Color = Color(0.12, 0.10, 0.09)

func _init(p_color: Color = Color(0.7, 0.5, 0.3), p_body_size: Vector3 = Vector3(0.4, 0.6, 0.4)) -> void:
	color = p_color
	body_size = p_body_size
