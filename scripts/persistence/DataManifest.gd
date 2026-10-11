class_name DataManifest

## DataManifest — Explizite Liste aller statischen Ressourcen-Pfade.
##
## WARUM: DirAccess.open("res://...") funktioniert auf Android nicht —
## Godot-PCK-Archive erlauben keine Verzeichnisauflistung zur Laufzeit.
## Außerdem erkennt der Godot-Exporter mit export_filter="all_resources"
## nur Ressourcen die im SceneTree oder via preload() referenziert sind.
## Ressourcen die nur per DirAccess-Scan geladen werden, landen NICHT im APK.
##
## LÖSUNG: Alle Pfade hier als Konstanten auflisten.
##   - Der Exporter sieht die String-Literals und packt die Dateien ein.
##   - DataService nutzt diese Listen statt DirAccess.
##   - Neue Items/Quests: Pfad hier ergänzen → automatisch exportiert.

const ITEMS: Array[String] = [
	"res://data/items/LogNormal.tres",
	"res://data/items/LogOak.tres",
	"res://data/items/LogMaple.tres",
	"res://data/items/LogWillow.tres",
	"res://data/items/IronOre.tres",
	"res://data/items/CopperOre.tres",
	# Goblin-Drop Items
	"res://data/items/GoblinEar.tres",
	# Special-Bedingungs-Gegner-Drops (Werwolf/Nebelgeist, siehe ConditionalEncounterService)
	"res://data/items/WolfFang.tres",
	"res://data/items/WraithEssence.tres",
	"res://data/items/weapons/PoisonDagger.tres",
	# Skeleton-Drop Items
	"res://data/items/BoneFragment.tres",
	# Cactus-Drop Items (Round 76)
	"res://data/items/CactusFiber.tres",
	# PineTree-/IceCrystal-Drop Items (Round 77)
	"res://data/items/LogPine.tres",
	"res://data/items/IceCrystalShard.tres",
	# RockBoulder-Drop Item (Round 78)
	"res://data/items/Stone.tres",
	# MushroomCluster-Drop Item (Round 79) — FallenTree nutzt log_normal (bereits oben registriert)
	"res://data/items/WildMushroom.tres",
	# Fern-Drop Item (Fern-Rollout)
	"res://data/items/FernFiber.tres",
	# Gathering-Werkzeuge (Shop-Kauf, Round 88): +50% Abbaugeschwindigkeit
	"res://data/items/tools/WoodAxe.tres",
	"res://data/items/tools/Pickaxe.tres",
	# Graben/Aufschütten (Gelände-Umbau): Schaufel + das Material, das dabei entsteht/verbraucht wird
	"res://data/items/tools/Shovel.tres",
	# Mähen (2026-10-06, "Gras mit der Sense abbauen"): Sense + ihre Erträge Heu/Wildblume
	"res://data/items/tools/Scythe.tres",
	"res://data/items/Hay.tres",
	"res://data/items/Wildflower.tres",
	"res://data/items/Dirt.tres",
	# Boden-Material-System (2026-09-26, "natürlich Erde/Sand je nach Biom + Kiesschicht"):
	# analog zu Dirt.tres, siehe BiomeDefinition.surface_material/TerrainField.get_material_at().
	"res://data/items/Sand.tres",
	"res://data/items/Gravel.tres",
	# Graben in die Tiefe: Leiter + Funde (Erze/Edelsteine, siehe DigFindTable)
	"res://data/items/Ladder.tres",
	"res://data/items/SilverOre.tres",
	"res://data/items/GoldOre.tres",
	"res://data/items/GemAmethyst.tres",
	"res://data/items/GemEmerald.tres",
	"res://data/items/GemSapphire.tres",
	"res://data/items/GemRuby.tres",
	"res://data/items/GemDiamond.tres",
	# ADR-038: Item-Schutz-Dreiklang — drei Schutz-Scrolls
	"res://data/items/ScrollPveProtection.tres",
	"res://data/items/ScrollTheftProtection.tres",
	"res://data/items/ScrollPvpProtection.tres",
	# ADR-039: Pickpocketing — drei Diebstahl-Kristall-Stufen
	"res://data/items/TheftCrystalWeak.tres",
	"res://data/items/TheftCrystalNormal.tres",
	"res://data/items/TheftCrystalStrong.tres",
	# Farming — Samen + Ernte-Item (Wunsch "Samen pflanzen + ernten")
	"res://data/items/CarrotSeed.tres",
	"res://data/items/Carrot.tres",
	# Försterei — Setzling (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen").
	# log_oak selbst ist schon länger als Bau-Material registriert (OakWall,
	# TowerWoodSquare, …), hatte aber bisher keine Erntequelle im Spiel — die
	# Försterei ist jetzt genau das. Ausgebaut auf alle vier Wild-Baumarten
	# (Wunsch "für alle Baumarten ausbauen") — je ein Setzling-Item pro
	# HarvestableEntity-Baum (OakTree/MapleTree/PineTree/WillowTree).
	"res://data/items/OakSapling.tres",
	"res://data/items/MapleSapling.tres",
	"res://data/items/PineSapling.tres",
	"res://data/items/WillowSapling.tres",
	# Hain-Skills (Sturmkunde/Imkerei/Sternkunde/Alchemie/Köhlerei): je ein Sammel-Item.
	"res://data/items/LightningGlass.tres",
	"res://data/items/Honeycomb.tres",
	"res://data/items/MeteoriteIron.tres",
	"res://data/items/Sulfur.tres",
	"res://data/items/Charcoal.tres",
	"res://data/items/FoxTailTalisman.tres",
	"res://data/items/CopperIngot.tres",
	"res://data/items/IronIngot.tres",
	"res://data/items/SteelIngot.tres",
	"res://data/items/SilverIngot.tres",
	"res://data/items/GoldIngot.tres",
	"res://data/items/tools/ToolTongs.tres",
	"res://data/items/tools/ToolHammer.tres",
	"res://data/items/weapons/CopperDagger.tres",
	"res://data/items/weapons/CopperSword.tres",
	"res://data/items/weapons/CopperAxe.tres",
	"res://data/items/armor/CopperHelmet.tres",
	"res://data/items/armor/CopperChestplate.tres",
	"res://data/items/armor/CopperGreaves.tres",
	"res://data/items/armor/CopperBoots.tres",
	"res://data/items/weapons/IronDagger.tres",
	"res://data/items/weapons/IronSword.tres",
	"res://data/items/weapons/IronAxe.tres",
	"res://data/items/armor/IronHelmet.tres",
	"res://data/items/armor/IronChestplate.tres",
	"res://data/items/armor/IronGreaves.tres",
	"res://data/items/armor/IronBoots.tres",
	"res://data/items/weapons/SteelDagger.tres",
	"res://data/items/weapons/SteelSword.tres",
	"res://data/items/weapons/SteelAxe.tres",
	"res://data/items/armor/SteelHelmet.tres",
	"res://data/items/armor/SteelChestplate.tres",
	"res://data/items/armor/SteelGreaves.tres",
	"res://data/items/armor/SteelBoots.tres",
	"res://data/items/weapons/MeteoriteDagger.tres",
	"res://data/items/ChamomileFlowers.tres",
	"res://data/items/ChamomileSeed.tres",
	"res://data/items/YarrowHerb.tres",
	"res://data/items/YarrowSeed.tres",
	"res://data/items/NettleFiber.tres",
	"res://data/items/NettleSeed.tres",
	"res://data/items/DandelionRoot.tres",
	"res://data/items/DandelionSeed.tres",
	"res://data/items/ThymeSprigs.tres",
	"res://data/items/ThymeSeed.tres",
	"res://data/items/MeadowsweetBlossoms.tres",
	"res://data/items/MeadowsweetSeed.tres",
	"res://data/items/PoppyPetals.tres",
	"res://data/items/PoppySeed.tres",
	"res://data/items/CornflowerBlossoms.tres",
	"res://data/items/CornflowerSeed.tres",
	"res://data/items/CalendulaBlossoms.tres",
	"res://data/items/CalendulaSeed.tres",
	"res://data/items/LavenderSprigs.tres",
	"res://data/items/LavenderSeed.tres",
	"res://data/items/SunflowerHead.tres",
	"res://data/items/SunflowerSeed.tres",
	"res://data/items/TulipBlossoms.tres",
	"res://data/items/TulipBulb.tres",
	"res://data/items/Blackberries.tres",
	"res://data/items/Hazelnuts.tres",
	"res://data/items/Elderberries.tres",
	"res://data/items/Rosehips.tres",
	"res://data/items/Brushwood.tres",
	"res://data/items/HazelRods.tres",
	"res://data/items/Bucket.tres",
	"res://data/items/WaterBucket.tres",
	"res://data/items/FormicAcid.tres",
	"res://data/items/TermiteClay.tres",
	"res://data/items/MolehillSoil.tres",
	"res://data/items/WaspPaper.tres",
	"res://data/items/HornetPaper.tres",
	# Berufe (ProfessionCatalog): Tausch-Ergebnisse der Handwerker-NPCs, siehe docs/professions.md
	"res://data/items/ClayJug.tres",
	"res://data/items/LinenCloth.tres",
	"res://data/items/DyedCloth.tres",
	"res://data/items/HoneyDrink.tres",
	"res://data/items/Salt.tres",
	"res://data/items/GlassBottle.tres",
	"res://data/items/WagonWheel.tres",
	"res://data/items/PaperSheet.tres",
]

const LOOT_TABLES: Array[String] = [
	"res://data/loot_tables/goblin_loot.tres",
	"res://data/loot_tables/skeleton_loot.tres",
	"res://data/loot_tables/werewolf_loot.tres",
	"res://data/loot_tables/fog_wraith_loot.tres",
	"res://data/loot_tables/loot_carrot.tres",
	"res://data/loot_tables/loot_chamomile_field.tres",
	"res://data/loot_tables/loot_yarrow_field.tres",
	"res://data/loot_tables/loot_nettle_field.tres",
	"res://data/loot_tables/loot_dandelion_field.tres",
	"res://data/loot_tables/loot_thyme_field.tres",
	"res://data/loot_tables/loot_meadowsweet_field.tres",
	"res://data/loot_tables/loot_poppy_field.tres",
	"res://data/loot_tables/loot_cornflower_field.tres",
	"res://data/loot_tables/loot_calendula_field.tres",
	"res://data/loot_tables/loot_lavender_field.tres",
	"res://data/loot_tables/loot_sunflower_field.tres",
	"res://data/loot_tables/loot_tulip_field.tres",
	"res://data/loot_tables/loot_ant_hill.tres",
	"res://data/loot_tables/loot_termite_mound.tres",
	"res://data/loot_tables/loot_mole_hill.tres",
	"res://data/loot_tables/loot_wasp_nest.tres",
	"res://data/loot_tables/loot_hornet_nest.tres",
]

## Farming (Wunsch "Samen pflanzen + ernten") — siehe FarmCropDefinition.gd/
## FarmPlot.gd. Neue Feldfrucht: neue .tres hier + passende Samen-/Ernte-
## Items oben in ITEMS + eigene LootTable — kein Code-Änderung an FarmPlot
## nötig (siehe dortiger Klassenkommentar).
## FarmPlot trägt inzwischen auch Baum-Setzlinge (skill_id="forestry" statt
## "farming", siehe FarmCropDefinition.gd) — "CROPS" ist historisch benannt,
## bedeutet hier "alles, was ein FarmPlot bepflanzen kann".
const CROPS: Array[String] = [
	"res://data/crops/carrot.tres",
	"res://data/crops/oak_sapling.tres",
	"res://data/crops/maple_sapling.tres",
	"res://data/crops/pine_sapling.tres",
	"res://data/crops/willow_sapling.tres",
	# Kräuter (herbalism) + Blumen (gardening): Felder im Dorf, siehe PlantCatalog/WorldSpawner
	"res://data/crops/chamomile.tres",
	"res://data/crops/yarrow.tres",
	"res://data/crops/nettle.tres",
	"res://data/crops/dandelion.tres",
	"res://data/crops/thyme.tres",
	"res://data/crops/meadowsweet.tres",
	"res://data/crops/poppy.tres",
	"res://data/crops/cornflower.tres",
	"res://data/crops/calendula.tres",
	"res://data/crops/lavender.tres",
	"res://data/crops/sunflower.tres",
	"res://data/crops/tulip.tres",
]

## Bauteile (Bausystem): neues Bauteil = neue .tres hier — solange es ein bekannter Kind ist
## (BuildPieceDefinition.Kind), ist kein Code nötig. Kosten verweisen auf Item-IDs aus ITEMS.
const BUILD_PIECES: Array[String] = [
	"res://data/building/WoodFloor.tres",
	"res://data/building/WoodWall.tres",
	"res://data/building/StoneWall.tres",
	"res://data/building/WoodDoor.tres",
	"res://data/building/WoodWindow.tres",
	"res://data/building/WoodRoof.tres",
	"res://data/building/WoodStairs.tres",
	# Mehr Auswahl fürs Bauen (Wunsch "damit man wirklich gut bauen kann"): Stein-Set
	# komplettiert (bisher nur Wand — jetzt auch Boden/Dach/Treppe, ein reines Steinhaus
	# ist damit möglich), plus Eichenwand (stabilere Holz-Stufe, log_oak bisher ungenutzt),
	# verstärkte Tür und niedrige Mauern/Zäune (WALL mit geringerer height — Balkone/
	# Gärten/Sichtschutz ohne gleich ein ganzes Zimmer abzuschließen).
	"res://data/building/StoneFloor.tres",
	"res://data/building/StoneRoof.tres",
	"res://data/building/StoneStairs.tres",
	"res://data/building/OakWall.tres",
	"res://data/building/IronDoor.tres",
	"res://data/building/WoodFence.tres",
	"res://data/building/StoneFence.tres",
	# Bogenschießstand (Wunsch "mehr shapes und Strukturen"): neuer Kind TARGET (freistehende
	# Requisiten, siehe BuildPieceDefinition.Kind) für die Zielscheibe, plus Strohballen als
	# niedrige, breite WALL-Variante (Pfeilfang/Absperrung — kein neuer Code nötig, nur Daten).
	"res://data/building/ArcheryTarget.tres",
	"res://data/building/HayBale.tres",
	# Brunnen (Wunsch "als nächstes ein Brunnen"): zweite Requisite auf Kind TARGET, über den
	# neuen Schalter BuildPieceDefinition.PropShape (kein neuer Kind/Platzierungscode nötig,
	# nur ein neuer build_..._mesh() — siehe BuildPieceDefinition.Kind-Klassenkommentar).
	"res://data/building/Well.tres",
	# Türme rund/eckig (Wunsch "Türme rund und eckig"): zwei weitere PropShape-Werte auf
	# demselben Kind TARGET wie Zielscheibe/Brunnen — kein neuer Kind/Platzierungscode nötig.
	"res://data/building/TowerStoneRound.tres",
	"res://data/building/TowerWoodSquare.tres",
	# Mehr Dachformen, First adjustierbar (Wunsch "Dächer in mehr Formen ... adjustierend"):
	# neuer Schalter BuildPieceDefinition.RoofShape auf demselben Kind ROOF — Satteldach
	# (bisheriges Verhalten, WoodRoof/StoneRoof bleiben unverändert GABLE) bekommt zwei
	# Geschwister (Walmdach/Zeltdach, beide dieselbe First-Einzug-Formel wie GABLE, nur mit
	# roof_ridge > 0 — siehe RoofShape-Kommentar) sowie ein Flachdach ohne First.
	"res://data/building/HipRoof.tres",
	"res://data/building/PyramidRoof.tres",
	"res://data/building/FlatRoof.tres",
	# Wendeltreppen (Wunsch "Wendeltreppen, sollen in Große Häuser & Türme passen"): neuer
	# Schalter BuildPieceDefinition.StairsShape auf demselben Kind STAIRS wie WoodStairs/
	# StoneStairs — kein neuer Kind/Platzierungscode nötig, nur ein neuer build_..._mesh() +
	# eigene Kollisionsform. Grundfläche bleibt EINE Zelle (wie bei der geraden Treppe), passt
	# also in Turmschäfte (TOWER_ROUND/TOWER_SQUARE) und mehrstöckige Häuser, wo eine gerade
	# Treppe zu viel Platz braucht.
	"res://data/building/WoodSpiralStairs.tres",
	"res://data/building/StoneSpiralStairs.tres",
	# Kirche & Friedhof (Wunsch "Kirche & Friedhof"): Kreuz und Grabsteine als drei weitere
	# PropShape-Werte auf Kind TARGET (wie Zielscheibe/Brunnen/Türme — kein neuer Kind/
	# Platzierungscode nötig). CemeteryGate ist Kind DOOR (dieselbe Öffnungs-Mechanik wie
	# WoodDoor/IronDoor, nur dunklere Optik/andere Kosten) — die niedrige Friedhofsmauer
	# braucht kein neues Bauteil, StoneFence (oben) deckt das schon ab.
	"res://data/building/WaysideCross.tres",
	"res://data/building/GraveCross.tres",
	"res://data/building/GravestoneStele.tres",
	"res://data/building/GravestoneSlab.tres",
	"res://data/building/CemeteryGate.tres",
	# Kapelle, Wegweiser, Straßenlaternen (Wunsch "als nächstes Kapelle, Wegweiser und Straßen-
	# laternen"): drei weitere PropShape-Werte auf Kind TARGET (CHAPEL/SIGNPOST/LAMP_POST) — kein neuer
	# Kind/Platzierungscode. Neu gegenüber den älteren Requisiten: mehrere Mesh-Flächen mit
	# Zweitfarbe (accent_color) und Leuchtfläche, begehbare Kapelle (get_prop_collision_boxes()) und
	# optionales Licht (light_range) — siehe BuildPieceDefinition.PropShape/PropSurface. Je zwei
	# Materialvarianten für Kapelle und Laterne, nur Daten.
	"res://data/building/ChapelStone.tres",
	"res://data/building/ChapelWood.tres",
	"res://data/building/WoodSignpost.tres",
	"res://data/building/StreetLampIron.tres",
	"res://data/building/StreetLampWood.tres",
	# Windmühle & Sonnenuhr (Wunsch "Strukturen und shapes ... kleine gimmicks und große
	# Struktur"): zwei weitere PropShape-Werte auf demselben Kind TARGET wie Zielscheibe/Brunnen/
	# Turm/Laterne — kein neuer Kind/Platzierungscode nötig, nur zwei neue build_..._mesh().
	"res://data/building/Windmill.tres",
	"res://data/building/Sundial.tres",
	# Torturm & Katapult (Wunsch "Richtung Burg"): wie oben zwei weitere PropShape-Werte auf
	# Kind TARGET — kein neuer Kind/Platzierungscode nötig, nur zwei neue build_..._mesh().
	"res://data/building/Gatehouse.tres",
	"res://data/building/Catapult.tres",
	# Wach-Grabstein (Spieler-Spawner-Grab, quest-freigeschaltet über quest_talia_graveyard_watch):
	# BUGFIX ("Spawnen von Graves für Skelette hat nicht geklappt"): fehlte hier komplett — ohne
	# Manifest-Eintrag lädt DataService die Definition nie (auch im Android-Export), das Bauteil
	# war nicht baubar und BuildPiece hätte nie register_point() beim AmbientSpawnService gerufen.
	"res://data/building/GravestoneSpawner.tres",
	# Schmiede-Stationen (Schmelzen & Schmieden): station_kind koppelt sie an die Rezepte aus
	# SMITHING_RECIPES — kein Code nötig, siehe docs/smithing-and-crafting.md.
	"res://data/building/Furnace.tres",
	"res://data/building/Anvil.tres",
	# Handwerks-Requisiten (Wunsch "mehr Strukturen, was es im Mittelalter so an Berufen gab — klein
	# anfangen, daraus große Strukturen bauen"): vier weitere PropShape-Werte auf Kind TARGET
	# (BARREL/MARKET_STALL/BAKE_OVEN/WORKBENCH) neben den Schmiede-Stationen Hochofen/Amboss — kein
	# neuer Kind/Platzierungscode, nur vier neue build_..._mesh(). Der Marktstand hat zwei
	# Farbvarianten (nur Daten). Die Berufs-Gebäude daraus stehen unten in HOUSE_TEMPLATES.
	"res://data/building/Barrel.tres",
	"res://data/building/MarketStallRed.tres",
	"res://data/building/MarketStallBlue.tres",
	"res://data/building/BakeOven.tres",
	"res://data/building/Workbench.tres",
	# Torbögen, Zinnenmauer und Kleinigkeiten (Wunsch "mehr Kleinigkeiten und grundlegende Shapes für
	# Torbögen usw. — am Ende ganze Dörfer, Städte und Königreiche füllen"): Bogen-Öffnungen sind normale
	# DOOR/WINDOW-Bauteile mit opening_shape = ARCH (Breite/Scheitelhöhe als Daten), die Zinnenmauer ein
	# WALL mit wall_top = CRENELLATED; dazu acht Requisiten-Formen (Kiste, Sack, Bank, Tisch, Karren,
	# Fahne, Säule, Feuerstelle) mit Farb-/Materialvarianten nur als Daten.
	"res://data/building/StoneGateArch.tres",
	"res://data/building/StoneArchDoor.tres",
	"res://data/building/WoodArchDoor.tres",
	"res://data/building/StoneArchWindow.tres",
	"res://data/building/WoodArchWindow.tres",
	"res://data/building/StoneWallCrenel.tres",
	"res://data/building/Crate.tres",
	"res://data/building/Sacks.tres",
	"res://data/building/Bench.tres",
	"res://data/building/Table.tres",
	"res://data/building/Cart.tres",
	"res://data/building/BannerRed.tres",
	"res://data/building/BannerBlue.tres",
	"res://data/building/PillarStone.tres",
	"res://data/building/PillarWood.tres",
	"res://data/building/Firepit.tres",
	# Hof- und Wehr-Requisiten (Wunsch "Strukturen und Gebäude weiter ausbauen — klein anfangen, dann hoch-
	# bauen"): fünf weitere PropShape-Werte auf Kind TARGET (TROUGH/WOODPILE/GARDEN_BED/SCARECROW/
	# WEAPON_RACK) — Grundlage für Stall, Kräutergarten, Scheune, Kaserne. Wasser-/Futtertrog und
	# Kräuter-/Blumenbeet sind Farbvarianten nur als Daten. Die Gebäude daraus stehen unten in HOUSE_TEMPLATES.
	"res://data/building/WaterTrough.tres",
	"res://data/building/FeedTrough.tres",
	"res://data/building/Woodpile.tres",
	"res://data/building/GardenBedHerbs.tres",
	"res://data/building/GardenBedFlowers.tres",
	"res://data/building/Scarecrow.tres",
	"res://data/building/WeaponRack.tres",
	# Torflügel, breiter Bogen, Wehrgang (Wunsch "breite Tore, Torflügel, Treppen auf Mauerkronen, Wehrgänge"):
	# DOOR-Bauteile mit leaf_state (OPEN/CLOSED) für Tür UND Tor, ein breiterer Torbogen, die Zinnenbrüstung
	# (niedriges WALL mit wall_top = CRENELLATED für Ebene 1) und der Wehrgang (FLOOR mit tiefem skirt =
	# massiver Mauerkörper unter dem Gang). Treppe auf die Mauerkrone = vorhandene stone_stairs.
	"res://data/building/WoodDoorOpen.tres",
	"res://data/building/WoodDoorClosed.tres",
	"res://data/building/WoodGateOpen.tres",
	"res://data/building/WoodGateClosed.tres",
	"res://data/building/StoneGateOpen.tres",
	"res://data/building/StoneGateClosed.tres",
	"res://data/building/StoneGateArchWide.tres",
	"res://data/building/StoneParapet.tres",
	"res://data/building/StoneWalkway.tres",
]

## Komplette Häuser (HouseTemplateDefinition): mehrere BUILD_PIECES-Einträge als eine Vorlage,
## siehe HouseTemplateDefinition-Klassenkommentar. Neues Haus = neue .tres hier — solange sie
## nur vorhandene BUILD_PIECES referenziert, ist kein Code nötig.
const HOUSE_TEMPLATES: Array[String] = [
	"res://data/building/houses/SimpleCabin.tres",
	"res://data/building/houses/StarterHut.tres",
	"res://data/building/houses/ForestLodge.tres",
	"res://data/building/houses/ArcheryRange.tres",
	# Kirche & Friedhof (Wunsch "Kirche & Friedhof"): kein neuer Code nötig — nur vorhandene
	# BUILD_PIECES referenziert (Stein-Set, Turm, Wegkreuz), siehe HouseTemplateDefinition-
	# Klassenkommentar.
	"res://data/building/houses/VillageChurch.tres",
	"res://data/building/houses/VillageCemetery.tres",
	# Müllerhäuschen (Wunsch "Strukturen und shapes ... große Struktur"): kein neuer Code nötig —
	# nur vorhandene BUILD_PIECES referenziert (Stein-Set der Steinhütte) plus die neue Windmühle/
	# Sonnenuhr von oben.
	"res://data/building/houses/WindmillCottage.tres",
	# Kleine Burg (Wunsch "Richtung Burg"): kein neuer Code nötig — nur vorhandene BUILD_PIECES
	# referenziert (Steinmauer, Rundturm, Brunnen) plus Torturm/Katapult von oben.
	"res://data/building/houses/SmallCastle.tres",
	# Wachposten (Wunsch "Strukturen: klein anfangen, dann groß ausbauen"): kleiner Startpunkt
	# für spätere Befestigungen, nur vorhandene BUILD_PIECES referenziert.
	"res://data/building/houses/Watchpost.tres",
	# Schmiede (Wunsch \"Bau schmieden weiter aus — keine echte Integration\"): Haus mit Hochofen +
	# Amboss als funktionierende Stationen, nur vorhandene BUILD_PIECES referenziert.
	"res://data/building/houses/Smithy.tres",
	# Berufs-Gebäude (Wunsch "mehr Strukturen, was es im Mittelalter so an Berufen gab — klein anfangen,
	# daraus große Strukturen bauen"): kein neuer Code — vorhandene BUILD_PIECES plus die neuen
	# Handwerks-Requisiten und die Schmiede-Stationen (Smithy steht oben). Reihenfolge = klein nach
	# groß; erzeugt/validiert von tools/building_templates/generate_craft_templates.py.
	"res://data/building/houses/Bakery.tres",
	"res://data/building/houses/CarpenterShop.tres",
	"res://data/building/houses/MarketSquare.tres",
	"res://data/building/houses/Tavern.tres",
	"res://data/building/houses/Farmstead.tres",
	"res://data/building/houses/CraftQuarter.tres",
	# Tore und Plätze (Wunsch "Torbögen ... Dörfer, Städte und Königreiche"): Torbogen (5 Felder Mauer),
	# Stadttor (zwei Türme, Zinnenmauer, Gassenpflaster) und Dorfplatz (Brunnen, Bänke, Stände, Lager).
	"res://data/building/houses/GateArch.tres",
	"res://data/building/houses/CityGate.tres",
	"res://data/building/houses/VillageSquare.tres",
	# Hof und Wehr (Wunsch "Strukturen und Gebäude weiter ausbauen — klein anfangen, dann hochbauen"): Reihenfolge
	# klein nach groß — Kräutergarten, Stall (Reittiere), Scheune, Mauereck mit Eckturm, Kaserne (großer Bruder
	# des Wachpostens), Wehrhof (Festungshof mit Torturm). Kein neuer Code: neue Requisiten (Trog, Holzstapel,
	# Beet, Vogelscheuche, Waffenständer) + vorhandene Teile; erzeugt/validiert von
	# tools/building_templates/generate_craft_templates.py.
	"res://data/building/houses/HerbGarden.tres",
	"res://data/building/houses/Stable.tres",
	"res://data/building/houses/Barn.tres",
	"res://data/building/houses/WallCorner.tres",
	"res://data/building/houses/Barracks.tres",
	# Festhalle: ein Dach über 7×5 Zellen, nur die Langseiten sind Wand — nutzt den Dach-Überhang mit Reichweite 2.
	"res://data/building/houses/FeastHall.tres",
	"res://data/building/houses/FortressYard.tres",
	# Wehrgang und Großtor (Vorlagen mit Ebenen-Einträgen "storey": Mauerkrone = Ebene 1).
	"res://data/building/houses/WallWalk.tres",
	"res://data/building/houses/CityGateGrand.tres",
]

const QUESTS: Array[String] = [
	"res://data/quests/quest_woodcutter_intro.tres",
	# BUG-FIX: die folgenden drei .tres existierten bereits, fehlten aber hier —
	# DataService._load_quests() liest ausschließlich aus dieser Liste (kein
	# DirAccess-Scan, siehe Klassenkommentar oben), sie wurden also nie
	# geladen und waren im Spiel faktisch nicht vorhanden.
	"res://data/quests/quest_erik_friendship.tres",
	"res://data/quests/quest_miner_defense.tres",
	"res://data/quests/quest_woodcutter_master.tres",
	"res://data/quests/quest_miner_gratitude.tres",
	"res://data/quests/quest_herbalist_request.tres",
	"res://data/quests/quest_herbalist_secret.tres",
	"res://data/quests/quest_wei_patience.tres",
	"res://data/quests/quest_babatunde_tale.tres",
	"res://data/quests/quest_wei_mastery.tres",
	"res://data/quests/quest_babatunde_legacy.tres",
	"res://data/quests/quest_talia_investigation.tres",
	"res://data/quests/quest_talia_verdict.tres",
	# BUGFIX ("Skelette töten lässt die Friedhof-Quest nicht fortschreiten"):
	# dieselbe Lücke wie bei den drei .tres oben — die Ressource existierte
	# bereits (GuardNPC._add_extra_quest_slot() referenziert ihre id, und
	# BuildPieceDefinition.requires_quest_id auf GravestoneSpawner.tres
	# prüft dagegen), war aber nie hier eingetragen. DataService._load_quests()
	# liest ausschließlich aus dieser Liste, also blieb QuestService._definitions
	# ohne sie. Symptom passte exakt dazu: request_start_quest()/
	# on_quest_start_confirmed() starten eine Quest auch OHNE Definition (sie
	# bauen dann nur einen leeren QuestProgressRecord ohne echte Objectives) —
	# "Quest gestartet" erschien im Log und im Wiki. Aber update_objective()
	# UND QuestObjectiveHandler.resolve_kill() brechen beide sofort ab, sobald
	# `definitions.get(quest_id)` null liefert — kein einziges getötetes
	# Skelett (egal wie viele) konnte das Objective je erhöhen, und die Quest
	# blieb für immer bei 0/5 hängen, ohne jede Fehlermeldung.
	"res://data/quests/quest_talia_graveyard_watch.tres",
	"res://data/quests/quest_myrmex_acid.tres",
	"res://data/quests/quest_myrmex_scholar.tres",
	"res://data/quests/quest_rudo_clay.tres",
	"res://data/quests/quest_rudo_wall.tres",
	"res://data/quests/quest_lucius_boundary.tres",
	"res://data/quests/quest_lucius_survey.tres",
	"res://data/quests/quest_gerlinde_combs.tres",
	"res://data/quests/quest_gerlinde_master.tres",
	"res://data/quests/quest_lian_wasp_paper.tres",
	"res://data/quests/quest_lian_fibre.tres",
	"res://data/quests/quest_sigrun_myth.tres",
	"res://data/quests/quest_sigrun_scholar.tres",
]

const SKILLS: Array[String] = [
	"res://data/skills/woodcutting.tres",
	"res://data/skills/mining.tres",
	"res://data/skills/farming.tres",
	"res://data/skills/combat.tres",
	"res://data/skills/foraging.tres",
	# FIX: digging.tres existierte, fehlte aber hier — WorldService vergibt DIG_XP über
	# request_add_xp("digging", …), SkillSystem verwarf die XP als "Unbekannter Skill".
	"res://data/skills/digging.tres",
	# ADR-039: uncapped (max_level=-1), lineare XP-Kurve (xp_scaling_factor=1.0)
	# — rein datengetrieben, kein SkillSystem-Code-Umbau nötig (siehe ADR
	# "Lineare statt exponentieller XP-Kurve").
	"res://data/skills/pickpocketing.tres",
	# Hain-Skills: XP kommen aus den Weltobjekten Fulgurite/WildBeehive/Meteorite/SulfurCrust/CharcoalKiln
	# (InteractableData.xp_type == Skill-ID).
	"res://data/skills/stormlore.tres",
	"res://data/skills/beekeeping.tres",
	"res://data/skills/stargazing.tres",
	"res://data/skills/alchemy.tres",
	"res://data/skills/charcoal_burning.tres",
	# Försterei (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen") — XP kommt
	# aus FarmPlot._refresh_interactable_data() über FarmCropDefinition.skill_id
	# (siehe data/crops/oak_sapling.tres), analog zu farming.tres oben.
	"res://data/skills/forestry.tres",
	"res://data/skills/smithing.tres",
	"res://data/skills/herbalism.tres",
	"res://data/skills/gardening.tres",
	"res://data/skills/entomology.tres",
]

const COMBAT_PROFILES: Array[String] = [
	"res://data/combat_profiles/goblin.tres",
	"res://data/combat_profiles/player.tres",
	"res://data/combat_profiles/skeleton.tres",
	"res://data/combat_profiles/werewolf.tres",
	"res://data/combat_profiles/fog_wraith.tres",
]

## Round 103 (ADR-046 "Umsetzungsstand (Round 103)"): datengetriebene
## Achievement-Definitionen, ergänzen/überschreiben
## AchievementService.DEFAULT_DEFINITIONS (der eingebaute Fallback bleibt
## bestehen, siehe dortiger Klassenkommentar).
const ACHIEVEMENTS: Array[String] = [
	"res://data/achievements/first_blood.tres",
	"res://data/achievements/pvp_veteran.tres",
	"res://data/achievements/first_sale.tres",
	"res://data/achievements/auctioneer.tres",
	"res://data/achievements/community_watch.tres",
	"res://data/achievements/wanderer.tres",
	"res://data/achievements/high_jumper.tres",
	"res://data/achievements/gravity_defier.tres",
	"res://data/achievements/monster_hunter.tres",
]

## Schmelz-/Schmiede-Rezepte (SmithingRecipe): Hochofen- und Amboss-Rezepte des Skills "smithing".
## Neues Rezept = neue .tres hier (content_forge.py, Typ "smithing_recipe") — kein Code nötig,
## solange alle referenzierten Items in ITEMS stehen (prüft test_smithing_content.gd).
const SMITHING_RECIPES: Array[String] = [
	# (von content_forge.py befüllt)
	"res://data/smithing_recipes/smelt_copper.tres",
	"res://data/smithing_recipes/smelt_iron.tres",
	"res://data/smithing_recipes/smelt_silver.tres",
	"res://data/smithing_recipes/smelt_gold.tres",
	"res://data/smithing_recipes/smelt_steel.tres",
	"res://data/smithing_recipes/forge_copper_dagger.tres",
	"res://data/smithing_recipes/forge_copper_sword.tres",
	"res://data/smithing_recipes/forge_copper_axe.tres",
	"res://data/smithing_recipes/forge_copper_helmet.tres",
	"res://data/smithing_recipes/forge_copper_chestplate.tres",
	"res://data/smithing_recipes/forge_copper_greaves.tres",
	"res://data/smithing_recipes/forge_copper_boots.tres",
	"res://data/smithing_recipes/forge_iron_dagger.tres",
	"res://data/smithing_recipes/forge_iron_sword.tres",
	"res://data/smithing_recipes/forge_iron_axe.tres",
	"res://data/smithing_recipes/forge_iron_helmet.tres",
	"res://data/smithing_recipes/forge_iron_chestplate.tres",
	"res://data/smithing_recipes/forge_iron_greaves.tres",
	"res://data/smithing_recipes/forge_iron_boots.tres",
	"res://data/smithing_recipes/forge_steel_dagger.tres",
	"res://data/smithing_recipes/forge_steel_sword.tres",
	"res://data/smithing_recipes/forge_steel_axe.tres",
	"res://data/smithing_recipes/forge_steel_helmet.tres",
	"res://data/smithing_recipes/forge_steel_chestplate.tres",
	"res://data/smithing_recipes/forge_steel_greaves.tres",
	"res://data/smithing_recipes/forge_steel_boots.tres",
	"res://data/smithing_recipes/forge_meteorite_dagger.tres",
]
