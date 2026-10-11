class_name ProfessionCatalog
extends RefCounted

## ProfessionCatalog — EINE Datenquelle für alle Dorf-Berufe (Recherche: docs/professions.md).
##
## Jeder Eintrag verbindet vier Dinge, die sonst auseinanderlaufen würden:
##   1. Das GEBÄUDE   (`building` = BuildingRecipes-Typ, in dem der Beruf arbeitet)
##   2. Den NPC       (`npc_type` + `script` = WorldEntityRegistry-Eintrag, Titel, Name, Look, Requisit)
##   3. Das SKRIPT    (`work` = Arbeits-Animation, `shift` = Tagesablauf, `trade` = Tausch-Angebot)
##   4. Die WAHRHEIT  (`years_ago` + `fact` = "Wusstest du?"-Fakt nach docs/skill-writing-guide.md)
##
## Neuer Beruf = ein Eintrag hier + ein dünnes NPC-Skript (`XyzNPC.gd`, nur `_profession_id()`) +
## Registrierung in WorldEntityRegistry + Gebäude in BuildingRecipes. `test_professions.gd` prüft die
## Verdrahtung (Gebäude existiert, Slot-Typ stimmt, Look/Requisit/Tausch-Items sind gültig).
##
## Warum `building`/`npc_type` hier als reine Strings stehen (statt BuildingRecipes.T_*): BuildingRecipes
## verweist selbst auf die NPC-Typen — ein Konstanten-Zirkel zwischen zwei Skripten wäre fragil. Der
## Test hält beide Seiten zusammen.
##
## Felder:
##   id, npc_type, script   Identität (npc_type = type_id im EntityOrchestrator, script = Skriptpfad;
##                          der MultiplayerSpawner löst Skriptpfad → type_id auf, daher ein Skript je Beruf)
##   title_m / title_f      Berufsbezeichnung, gegendert (Anzeigename: "Töpferin Berta")
##   building               BuildingRecipes-Typ-ID
##   years_ago              ältester belegter Fund in Jahren vor heute (gerundet, Richtwert)
##   era                    Epoche in Worten (Wiki/Doku)
##   fact                   "Wusstest du?"-Fakt, ein Satz, überprüfbar (Belege: docs/professions.md)
##   work                   Stil aus WorkAnimator.STYLES
##   work_verb              Kurzbeschreibung der Tätigkeit ("formt Gefäße auf der Töpferscheibe")
##   shift                  Tagesablauf, siehe WorkSchedule
##   gold                   Beutel-Inhalt für Taschendiebe (Vector2i min/max)
##   body_color, look, prop Aussehen (CharacterLook-IDs, NPCProps-ID)
##   battle                 bevorzugter Pet-Kampf-Typ ("hoofed"/"aqua"/"" = keiner)
##   lines                  Alltags-Sätze (kein Popkultur, kein Sarkasmus — docs/quest-writing-guide.md)
##   trade (optional)       Tausch am NPC: label, consumes, gives, duration, cooldown, offer (Text)

const PROFESSIONS: Array = [
	# ───────────── Neue Handwerksbetriebe ─────────────
	{
		"id": "potter", "npc_type": "potter_npc", "script": "res://scripts/entities/profession/PotterNPC.gd",
		"title_m": "Töpfer", "title_f": "Töpferin", "building": "pottery",
		"years_ago": 20000, "era": "Altsteinzeit",
		"fact": "Wusstest du? In der Xianrendong-Höhle in China fand man Tonscherben, die rund 20.000 Jahre alt sind – zu den ältesten bekannten Gefäßen der Welt (Keramik).",
		"work": "knead", "work_verb": "formt Gefäße aus feuchtem Ton",
		"shift": {"start": 7.0, "break": [12.0, 13.0], "end": 18.0, "free_until": 21.0},
		"gold": Vector2i(8, 45),
		"body_color": Color(0.62, 0.42, 0.28),
		"look": {"hat": "none", "shirt_style": "tunic", "belt": "brown", "pants": "brown", "shoes": "tan", "build": "broad"},
		"prop": "pot", "battle": "",
		"lines": [
			"Im Ofen wird aus weichem Ton ein hartes Gefäß – dafür braucht es viele Stunden Feuer.",
			"Jeder Krug klingt anders, wenn man mit dem Fingernagel dagegen tippt.",
			"Ton ist Erde, Wasser und Geduld. Mehr nicht.",
		],
		"trade": {
			"label": "Krug brennen lassen", "consumes": {"dirt": 4, "charcoal": 1}, "gives": {"clay_jug": 1},
			"duration": 2.4, "cooldown": 4.0, "offer": "Bring mir 4× Erde und 1× Holzkohle – ich brenne dir einen Tonkrug.",
		},
	},
	{
		"id": "weaver", "npc_type": "weaver_npc", "script": "res://scripts/entities/profession/WeaverNPC.gd",
		"title_m": "Weber", "title_f": "Weberin", "building": "weavery",
		"years_ago": 30000, "era": "Altsteinzeit",
		"fact": "Wusstest du? In einer Höhle in Georgien fand man gesponnene und geknotete Flachsfasern, über 30.000 Jahre alt – einige wohl gefärbt (Dzudzuana, Flachs).",
		"work": "weave", "work_verb": "schiebt das Schiffchen durch den Webstuhl",
		"shift": {"start": 7.0, "break": [12.0, 13.0], "end": 17.0, "free_until": 20.0},
		"gold": Vector2i(6, 35),
		"body_color": Color(0.55, 0.62, 0.46),
		"look": {"hat": "none", "shirt_style": "tunic", "belt": "none", "pants": "sand", "shoes": "tan", "build": "slim"},
		"prop": "shuttle", "battle": "",
		"lines": [
			"Aus Nesselfasern wird ein erstaunlich feiner Stoff – man muss sie nur geduldig spinnen.",
			"Ein Faden allein reißt. Tausende zusammen tragen dich durch den Winter.",
			"Kette und Schuss: Wer das Muster im Kopf hat, webt ohne hinzusehen.",
		],
		"trade": {
			"label": "Stoff weben lassen", "consumes": {"nettle_fiber": 4}, "gives": {"linen_cloth": 1},
			"duration": 2.4, "cooldown": 4.0, "offer": "Bring mir 4× Nesselfaser – ich webe dir einen Ballen Nesselstoff.",
		},
	},
	{
		"id": "dyer", "npc_type": "dyer_npc", "script": "res://scripts/entities/profession/DyerNPC.gd",
		"title_m": "Färber", "title_f": "Färberin", "building": "dyehouse",
		"years_ago": 3200, "era": "Bronze-/Eisenzeit",
		"fact": "Wusstest du? Für Tyrischen Purpur brauchte man tausende Meeresschnecken: Rund 12.000 Stück lieferten nur etwa ein Gramm Farbstoff (Murex).",
		"work": "stir", "work_verb": "rührt Stoff in der Farbküpe",
		"shift": {"start": 8.0, "break": [12.5, 13.5], "end": 17.0, "free_until": 20.0},
		"gold": Vector2i(8, 50),
		"body_color": Color(0.50, 0.28, 0.52),
		"look": {"hat": "beanie", "hat_color": "red", "shirt_style": "vest", "belt": "black", "pants": "gray", "shoes": "black"},
		"prop": "cloth", "battle": "",
		"lines": [
			"Gelb von Ringelblumen, Blau von Waid – und Purpur war zeitweise mehr wert als Gold.",
			"Der Stoff nimmt die Farbe nur an, wenn er vorher gut gewaschen wurde.",
			"Meine Hände sind seit Jahren bunt. Das geht nie mehr ganz ab.",
		],
		"trade": {
			"label": "Stoff färben lassen", "consumes": {"linen_cloth": 1, "calendula_blossoms": 3}, "gives": {"dyed_cloth": 1},
			"duration": 2.6, "cooldown": 4.0, "offer": "Bring mir 1× Nesselstoff und 3× Ringelblumenblüten – ich färbe ihn gelb.",
		},
	},
	{
		"id": "brewer", "npc_type": "brewer_npc", "script": "res://scripts/entities/profession/BrewerNPC.gd",
		"title_m": "Brauer", "title_f": "Brauerin", "building": "brewery",
		"years_ago": 13000, "era": "Mittelsteinzeit",
		"fact": "Wusstest du? In der Raqefet-Höhle in Israel zeigen Rückstände in Steinmörsern: Die Natufier brauten vor etwa 13.000 Jahren ein Getränk aus Getreide (Mälzen).",
		"work": "stir", "work_verb": "rührt die Maische im Kessel",
		"shift": {"start": 6.0, "break": [11.0, 12.0], "end": 16.0, "free_until": 21.0},
		"gold": Vector2i(10, 55),
		"body_color": Color(0.70, 0.52, 0.22),
		"look": {"hat": "cap", "hat_color": "tan", "shirt_style": "longsleeve", "belt": "brown", "pants": "olive", "shoes": "brown", "beard": "full"},
		"prop": "paddle", "battle": "",
		"lines": [
			"Keimen lassen, trocknen, mischen, gären – Geduld ist die wichtigste Zutat.",
			"Auch wilde Hefe aus der Luft kann einen Sud zum Gären bringen.",
			"Fass und Kessel müssen sauber sein – sonst verdirbt der ganze Sud.",
		],
		"trade": {
			"label": "Honigtrunk ansetzen", "consumes": {"honeycomb": 2, "water_bucket": 1}, "gives": {"honey_drink": 1, "bucket": 1},
			"duration": 2.4, "cooldown": 5.0, "offer": "Bring mir 2× Honigwabe und 1× Wassereimer – ich setze dir einen Honigtrunk an (den Eimer bekommst du zurück).",
		},
	},
	{
		"id": "tanner", "npc_type": "tanner_npc", "script": "res://scripts/entities/profession/TannerNPC.gd",
		"title_m": "Gerber", "title_f": "Gerberin", "building": "tannery",
		"years_ago": 5300, "era": "Kupferzeit",
		"fact": "Wusstest du? Ötzis Kleidung bestand vor 5.300 Jahren aus Leder und Fell von mindestens fünf Tierarten – Schaf, Ziege, Rind, Reh und Bär (Genanalyse).",
		"work": "scrape", "work_verb": "schabt ein Fell auf dem Gerberbock",
		"shift": {"start": 7.0, "break": [12.0, 12.75], "end": 16.0, "free_until": 19.0},
		"gold": Vector2i(6, 40),
		"body_color": Color(0.45, 0.32, 0.20),
		"look": {"hat": "none", "shirt_style": "vest", "belt": "black", "pants": "brown", "shoes": "brown", "build": "broad", "height": "tall"},
		"prop": "scraper", "battle": "",
		"lines": [
			"Gute Gerber wohnen am Dorfrand – frag nicht, warum.",
			"Aus Haut wird erst Leder, wenn sie lange gegerbt wurde. Eile verdirbt alles.",
			"Ziegenleder ist weich und biegsam – ideal für Beinlinge und Handschuhe.",
		],
	},
	{
		"id": "cheesemaker", "npc_type": "cheesemaker_npc", "script": "res://scripts/entities/profession/CheesemakerNPC.gd",
		"title_m": "Käser", "title_f": "Käserin", "building": "dairy",
		"years_ago": 7000, "era": "Jungsteinzeit",
		"fact": "Wusstest du? Siebartige Tongefäße mit Milchfett-Resten aus Polen, über 7.000 Jahre alt, sind der früheste direkte Beleg für Käse (Milchfett-Analyse).",
		"work": "press", "work_verb": "presst frischen Käsebruch in die Form",
		"shift": {"start": 5.0, "break": [10.0, 10.75], "end": 15.0, "free_until": 19.0},
		"gold": Vector2i(8, 45),
		"body_color": Color(0.90, 0.88, 0.80),
		"look": {"hat": "cap", "hat_color": "gray", "shirt_style": "tunic", "belt": "brown", "pants": "sand", "shoes": "tan"},
		"prop": "paddle", "battle": "hoofed",
		"lines": [
			"Beim Käsen läuft die Molke ab – darum steckt weniger Milchzucker im Käse als in der Milch.",
			"Je länger der Laib reift, desto kräftiger wird der Geschmack.",
			"Frühmorgens ist die Milch am besten. Wer schläft, verpasst den Käse.",
		],
	},
	{
		"id": "salter", "npc_type": "salter_npc", "script": "res://scripts/entities/profession/SalterNPC.gd",
		"title_m": "Salzsieder", "title_f": "Salzsiederin", "building": "saltworks",
		"years_ago": 3350, "era": "Bronzezeit",
		"fact": "Wusstest du? Im Salzbergwerk Hallstatt (Österreich) fand man eine Holztreppe von etwa 1344 v. Chr. – die älteste bekannte Treppe Europas (Salzbergbau).",
		"work": "rake", "work_verb": "wendet die Sole in den Siedepfannen",
		"shift": {"start": 6.0, "break": [12.0, 13.0], "end": 18.0, "free_until": 20.0},
		"gold": Vector2i(12, 60),
		"body_color": Color(0.78, 0.78, 0.74),
		"look": {"hat": "straw", "hat_color": "tan", "shirt_style": "longsleeve", "belt": "brown", "pants": "olive", "shoes": "brown", "build": "broad"},
		"prop": "rake", "battle": "aqua",
		"lines": [
			"Salz hielt früher das Fleisch den ganzen Winter frisch – es war weißes Gold.",
			"Das Feuer unter den Pfannen darf nie ausgehen, sonst fängt die Arbeit von vorn an.",
			"Wer Salz hat, hat Vorrat. Wer Vorrat hat, hat Ruhe.",
		],
		"trade": {
			"label": "Salz sieden lassen", "consumes": {"water_bucket": 2, "charcoal": 1}, "gives": {"salt": 1, "bucket": 2},
			"duration": 2.6, "cooldown": 5.0, "offer": "Bring mir 2× Wassereimer und 1× Holzkohle – ich siede dir Salz (die Eimer bekommst du zurück).",
		},
	},
	{
		"id": "glassmaker", "npc_type": "glassmaker_npc", "script": "res://scripts/entities/profession/GlassmakerNPC.gd",
		"title_m": "Glasbläser", "title_f": "Glasbläserin", "building": "glassworks",
		"years_ago": 3500, "era": "Bronzezeit",
		"fact": "Wusstest du? Die ersten Glasgefäße entstanden vor rund 3.500 Jahren in Mesopotamien: Glasmacher formten sie um einen Kern, der später entfernt wurde (Kernformverfahren).",
		"work": "blow", "work_verb": "bläst Glas an der Pfeife",
		"shift": {"start": 8.0, "break": [13.0, 14.0], "end": 19.0, "free_until": 21.0},
		"gold": Vector2i(15, 70),
		"body_color": Color(0.30, 0.52, 0.60),
		"look": {"hat": "none", "shirt_style": "tshirt", "belt": "black", "pants": "gray", "shoes": "black", "glasses": "shades"},
		"prop": "blowpipe", "battle": "",
		"lines": [
			"Sand, Asche und Kalk – mehr braucht es nicht. Nur sehr viel Hitze.",
			"Ein Blitz kann Sand zu Glas schmelzen. Ich brauche dafür einen Ofen.",
			"Glas ist flüssig, solange es glüht. Dann musst du schnell sein.",
		],
		"trade": {
			"label": "Flasche blasen lassen", "consumes": {"sand": 3, "brushwood": 2}, "gives": {"glass_bottle": 1},
			"duration": 2.6, "cooldown": 5.0, "offer": "Bring mir 3× Sand und 2× Reisig (die Asche ist mein Flussmittel) – ich blase dir eine Glasflasche.",
		},
	},
	{
		"id": "wheelwright", "npc_type": "wheelwright_npc", "script": "res://scripts/entities/profession/WheelwrightNPC.gd",
		"title_m": "Wagner", "title_f": "Wagnerin", "building": "wheelwright",
		"years_ago": 5100, "era": "Kupferzeit",
		"fact": "Wusstest du? Das Rad aus dem Laibacher Moor (Slowenien) ist rund 5.100 Jahre alt: Rad aus Esche, Achse aus Eiche – für jede Aufgabe das passende Holz (Radmacher).",
		"work": "carve", "work_verb": "passt Speichen in eine Radnabe ein",
		"shift": {"start": 7.0, "break": [12.0, 13.0], "end": 17.0, "free_until": 20.0},
		"gold": Vector2i(10, 55),
		"body_color": Color(0.58, 0.40, 0.22),
		"look": {"hat": "cap", "hat_color": "brown", "shirt_style": "vest", "belt": "brown", "pants": "olive", "shoes": "brown", "build": "broad"},
		"prop": "wheel", "battle": "hoofed",
		"lines": [
			"Esche für das Rad, Eiche für die Achse – das Holz muss zum Zweck passen.",
			"Ein Rad ist rund, weil jemand es sehr genau gemessen hat.",
			"Der eiserne Reifen wird heiß aufgezogen und zieht sich beim Abkühlen fest.",
		],
		"trade": {
			"label": "Wagenrad fertigen lassen", "consumes": {"log_normal": 4, "iron_ingot": 1}, "gives": {"wagon_wheel": 1},
			"duration": 2.8, "cooldown": 6.0, "offer": "Bring mir 4× Holzstamm und 1× Eisenbarren – ich fertige dir ein Wagenrad.",
		},
	},
	{
		"id": "scribe", "npc_type": "scribe_npc", "script": "res://scripts/entities/profession/ScribeNPC.gd",
		"title_m": "Schreiber", "title_f": "Schreiberin", "building": "scriptorium",
		"years_ago": 5300, "era": "Kupferzeit",
		"fact": "Wusstest du? Die frühesten Schrifttafeln aus Uruk (heute Irak) sind über 5.000 Jahre alt – es sind meist Verzeichnisse von Vorräten und Lieferungen (Keilschrift).",
		"work": "write", "work_verb": "schreibt Listen in ein Buch",
		"shift": {"start": 8.0, "break": [12.0, 13.0], "end": 17.0, "free_until": 21.0},
		"gold": Vector2i(14, 65),
		"body_color": Color(0.30, 0.34, 0.52),
		"look": {"hat": "none", "shirt_style": "longsleeve", "belt": "black", "pants": "black", "shoes": "black", "glasses": "round", "build": "slim"},
		"prop": "quill", "battle": "",
		"lines": [
			"Die ersten Texte der Welt waren meist Listen über Vorräte. Nichts Schlimmes daran.",
			"Wer aufschreibt, was er schuldet, streitet später weniger.",
			"Tinte trocknet schnell. Gedanken nicht – darum schreibe ich sie auf.",
		],
		"trade": {
			"label": "Papier schöpfen lassen", "consumes": {"nettle_fiber": 2, "water_bucket": 1}, "gives": {"paper_sheet": 3, "bucket": 1},
			"duration": 2.4, "cooldown": 5.0, "offer": "Bring mir 2× Nesselfaser und 1× Wassereimer – ich schöpfe dir 3 Bogen Papier (den Eimer bekommst du zurück).",
		},
	},
	{
		"id": "fisher", "npc_type": "fisher_npc", "script": "res://scripts/entities/profession/FisherNPC.gd",
		"title_m": "Fischer", "title_f": "Fischerin", "building": "fishery",
		"years_ago": 10000, "era": "Mittelsteinzeit",
		"fact": "Wusstest du? Der Einbaum von Pesse (Niederlande) wurde aus einem einzigen Kiefernstamm gefertigt und ist rund 10.000 Jahre alt – das älteste bekannte Boot (Einbaum).",
		"work": "fish", "work_verb": "flickt ein Fischernetz",
		"shift": {"start": 4.5, "break": [9.5, 10.25], "end": 14.0, "free_until": 18.0},
		"gold": Vector2i(6, 40),
		"body_color": Color(0.28, 0.46, 0.58),
		"look": {"hat": "cap", "hat_color": "blue", "shirt_style": "longsleeve", "belt": "brown", "pants": "navy", "shoes": "brown", "beard": "stubble"},
		"prop": "net", "battle": "aqua",
		"lines": [
			"Früh am Morgen sind die Fische oft am aktivsten.",
			"Ein Netz flickt man am besten, solange man noch weiß, wo das Loch war.",
			"Der Wind dreht, bevor das Wetter kippt. Man muss nur hinsehen.",
		],
	},
	# ───────────── Bestehende Gebäude bekommen echte Berufe ─────────────
	{
		"id": "smith", "npc_type": "smith_npc", "script": "res://scripts/entities/profession/SmithNPC.gd",
		"title_m": "Schmied", "title_f": "Schmiedin", "building": "smithy",
		"years_ago": 7000, "era": "Kupferzeit",
		"fact": "Wusstest du? Im serbischen Belovode fand man Kupferschlacke, rund 7.000 Jahre alt – einer der frühesten gesicherten Belege für Kupferverhüttung (Schmelzen im Feuer um 1.100 °C).",
		"work": "hammer", "work_verb": "schlägt glühendes Metall auf dem Amboss",
		"shift": {"start": 7.0, "break": [12.0, 13.0], "end": 17.0, "free_until": 20.0},
		"gold": Vector2i(15, 80),
		"body_color": Color(0.32, 0.30, 0.30),
		"look": {"hat": "none", "shirt_style": "vest", "belt": "black", "pants": "black", "shoes": "black", "build": "broad", "height": "tall", "beard": "full"},
		"prop": "hammer", "battle": "",
		"lines": [
			"Erz in den Ofen, Hitze drauf, Geduld dazu – so wird aus Stein Metall.",
			"Ein guter Schlag sitzt beim ersten Mal. Der zweite macht es nur schlimmer.",
			"Kupfer ist weich, Bronze ist hart. Wer beides mischt, gewinnt.",
		],
	},
	{
		"id": "baker", "npc_type": "baker_npc", "script": "res://scripts/entities/profession/BakerNPC.gd",
		"title_m": "Bäcker", "title_f": "Bäckerin", "building": "bakery",
		"years_ago": 14400, "era": "Mittelsteinzeit",
		"fact": "Wusstest du? In Jordanien fand man verkohlte Fladenbrot-Reste, etwa 14.400 Jahre alt – gebacken von Jägern und Sammlern, lange vor dem Ackerbau (Natufien).",
		"work": "knead", "work_verb": "knetet Teig für das Morgenbrot",
		"shift": {"start": 3.5, "break": [8.0, 8.5], "end": 11.0, "free_until": 17.0},
		"gold": Vector2i(8, 50),
		"body_color": Color(0.94, 0.92, 0.86),
		"look": {"hat": "cap", "hat_color": "gray", "shirt_style": "tunic", "belt": "none", "pants": "sand", "shoes": "white", "build": "broad"},
		"prop": "paddle", "battle": "",
		"lines": [
			"Wenn du den Ofen riechst, bin ich schon seit drei Stunden wach.",
			"Schon vor dem Ackerbau haben Menschen Brot gebacken – ich bin in guter Gesellschaft.",
			"Heißer Ofen, kalte Hände, warmes Brot. So muss das sein.",
		],
	},
	{
		"id": "miller", "npc_type": "miller_npc", "script": "res://scripts/entities/profession/MillerNPC.gd",
		"title_m": "Müller", "title_f": "Müllerin", "building": "mill",
		"years_ago": 14400, "era": "Mittelsteinzeit",
		"fact": "Wusstest du? Die Natufier mahlten wilde Getreidekörner schon vor 14.400 Jahren zu Mehl und buken daraus Fladen, bevor es Ackerbau gab (Mahlstein).",
		"work": "press", "work_verb": "schüttet Korn in den Mahlgang",
		"shift": {"start": 6.0, "break": [12.0, 13.0], "end": 17.0, "free_until": 20.0},
		"gold": Vector2i(10, 55),
		"body_color": Color(0.86, 0.84, 0.78),
		"look": {"hat": "cap", "hat_color": "tan", "shirt_style": "tunic", "belt": "brown", "pants": "sand", "shoes": "brown"},
		"prop": "sack", "battle": "hoofed",
		"lines": [
			"Bei gutem Wind mahlen die Flügel den ganzen Tag. Bei Flaute hilft nur Warten.",
			"Mehl liegt in der Luft, im Haar, im Bart – sogar im Tee.",
			"Der Mahlstein dreht sich langsam und sehr gründlich.",
		],
	},
]

## id → Index in PROFESSIONS (einmal gebaut, damit get_profession() nicht jedes Mal sucht).
static var _index: Dictionary = {}

static func all() -> Array:
	return PROFESSIONS

static func get_profession(id: String) -> Dictionary:
	if _index.is_empty():
		for i in range(PROFESSIONS.size()):
			_index[String((PROFESSIONS[i] as Dictionary)["id"])] = i
	if not _index.has(id):
		return {}
	return PROFESSIONS[int(_index[id])] as Dictionary

static func ids() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in PROFESSIONS:
		out.append(String(p["id"]))
	return out

## Beruf, der in Gebäudetyp `building_id` arbeitet ({} wenn keiner).
static func for_building(building_id: String) -> Dictionary:
	for p: Dictionary in PROFESSIONS:
		if String(p["building"]) == building_id:
			return p
	return {}

## Eintrag zum NPC-Typ (type_id im EntityOrchestrator).
static func for_npc_type(npc_type: String) -> Dictionary:
	for p: Dictionary in PROFESSIONS:
		if String(p["npc_type"]) == npc_type:
			return p
	return {}

## Alle NPC-Typen der Berufe (für Registry/Tests).
static func npc_types() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in PROFESSIONS:
		out.append(String(p["npc_type"]))
	return out

## Berufsstil zu einem Anzeigenamen ("Töpferin Berta" → Töpfer-Eintrag) über GANZE Wörter des Titels,
## damit alle Berufs-NPCs erkennbar nach ihrem Beruf aussehen (Look + Requisit), aber trotzdem je nach
## Namen anders (Gesicht, Haare). {} wenn der Name keinem Beruf entspricht.
static func style_for_name(display_name: String) -> Dictionary:
	var words: PackedStringArray = display_name.to_lower().split(" ", false)
	for p: Dictionary in PROFESSIONS:
		if words.has(String(p["title_m"]).to_lower()) or words.has(String(p["title_f"]).to_lower()):
			return {
				"look": (p["look"] as Dictionary).duplicate(),
				"overrides": {},
				"prop": String(p["prop"]),
				"body_color": p["body_color"],
			}
	return {}
