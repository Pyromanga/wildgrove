class_name WorldEntityRegistry
extends RefCounted

## WorldEntityRegistry — Registriert Entity-Definitionen im EntityOrchestrator.
##
## Ausgelagert aus WorldService._register_entity_definitions() (v28).
## Zentrale Stelle für alle bekannten Entity-Typen der Spielwelt.
##
## Statisch nutzbar — kein State, keine Abhängigkeiten außer dem Orchestrator.

const LOG_CAT := "WorldEntityRegistry"

## Round 75 — Single Source of Truth für ChunkEntitySpawner: welche
## BiomeDefinition.prop_chances/enemy_chances-Keys tatsächlich einen
## registrierten Entity-Typ haben und deshalb wirklich spawnen dürfen. MUSS
## synchron mit register_all() unten gehalten werden (kein automatischer
## Abgleich — bewusst einfach gehalten, gleiche Konvention wie BiomeRegistry
## selbst: code-seitige statische Liste statt Reflection/Introspection).
## Fehlt ein Typ hier (z.B. "rock_boulder", "pine_tree", "fern",
## "fallen_tree", "mushroom_cluster" — alle in BiomeRegistry referenziert,
## keiner hier registriert), wird der jeweilige prop_chances/enemy_chances-
## Eintrag von ChunkEntitySpawner stillschweigend gefiltert (kein Spawn,
## kein Fehler) statt EntityRegistry.instantiate() mit einem Fehler-Log zu
## fluten. ("cactus" war hier bis Round 75 auch gefiltert — Round 76 hat den
## Entity-Typ nachgezogen, siehe Cactus.gd.)
const KNOWN_PROP_TYPES:   Array[String] = ["oak_tree", "willow_tree", "maple_tree", "iron_ore", "copper_ore", "cactus", "pine_tree", "ice_crystal", "rock_boulder", "mushroom_cluster", "fallen_tree", "fern", "fulgurite", "wild_beehive", "ant_hill", "termite_mound", "mole_hill", "wasp_nest", "hornet_nest", "meteorite", "sulfur_crust", "charcoal_kiln", "graveyard_gravestone", "goblin_campfire", "plant_chamomile", "plant_yarrow", "plant_nettle", "plant_dandelion", "plant_thyme", "plant_meadowsweet", "plant_poppy", "plant_cornflower", "plant_calendula", "plant_lavender", "bush_blackberry", "bush_hazel", "bush_elder", "bush_dogrose"]
## Wunsch "Special Bedingungen": werewolf/fog_wraith spawnen NICHT über
## BiomeDefinition.enemy_chances (daher nicht in dieser Liste nötig für
## ChunkEntitySpawner), sondern ausschließlich über
## ConditionalEncounterService.ENCOUNTERS. Trotzdem hier UND via
## register_definition() registriert, weil EntityOrchestrator.spawn_entity()
## für JEDEN type_id eine Definition braucht, unabhängig vom Spawn-Pfad.
const KNOWN_ENEMY_TYPES:  Array[String] = ["goblin", "skeleton"]
const KNOWN_SPECIAL_ENEMY_TYPES: Array[String] = ["werewolf", "fog_wraith"]

## Registriert alle Welt-Entities im angegebenen Orchestrator.
static func register_all(orchestrator: EntityOrchestrator) -> void:
	orchestrator.register_definition("player",      "res://scripts/entities/player/Player.gd",                   "player")
	# Bäume — alle extends HarvestableEntity
	orchestrator.register_definition("oak_tree",    "res://scripts/world/objects/OakTree.gd",           "trees")
	orchestrator.register_definition("willow_tree", "res://scripts/world/objects/WillowTree.gd",        "trees")
	orchestrator.register_definition("maple_tree",  "res://scripts/world/objects/MapleTree.gd",         "trees")
	orchestrator.register_definition("pine_tree",   "res://scripts/world/objects/PineTree.gd",          "trees")
	orchestrator.register_definition("fallen_tree", "res://scripts/world/objects/FallenTree.gd",        "trees")
	# Pflanzen — extends HarvestableEntity (Round 76/77/79)
	orchestrator.register_definition("cactus",      "res://scripts/world/objects/Cactus.gd",            "plants")
	orchestrator.register_definition("ice_crystal", "res://scripts/world/objects/IceCrystal.gd",        "plants")
	orchestrator.register_definition("mushroom_cluster", "res://scripts/world/objects/MushroomCluster.gd", "plants")
	orchestrator.register_definition("fern",          "res://scripts/world/objects/Fern.gd",              "plants")
	# Kräuter (herbalism) + wilde Blumen (gardening) — extends WildPlant, Daten: PlantCatalog.
	orchestrator.register_definition("plant_chamomile", "res://scripts/world/plants/PlantChamomile.gd", "plants")
	orchestrator.register_definition("plant_yarrow", "res://scripts/world/plants/PlantYarrow.gd", "plants")
	orchestrator.register_definition("plant_nettle", "res://scripts/world/plants/PlantNettle.gd", "plants")
	orchestrator.register_definition("plant_dandelion", "res://scripts/world/plants/PlantDandelion.gd", "plants")
	orchestrator.register_definition("plant_thyme", "res://scripts/world/plants/PlantThyme.gd", "plants")
	orchestrator.register_definition("plant_meadowsweet", "res://scripts/world/plants/PlantMeadowsweet.gd", "plants")
	orchestrator.register_definition("plant_poppy", "res://scripts/world/plants/PlantPoppy.gd", "plants")
	orchestrator.register_definition("plant_cornflower", "res://scripts/world/plants/PlantCornflower.gd", "plants")
	orchestrator.register_definition("plant_calendula", "res://scripts/world/plants/PlantCalendula.gd", "plants")
	orchestrator.register_definition("plant_lavender", "res://scripts/world/plants/PlantLavender.gd", "plants")
	# Sträucher (Pflücken + Roden) — extends WildBush, Daten: BushCatalog.
	orchestrator.register_definition("bush_blackberry", "res://scripts/world/plants/BushBlackberry.gd", "plants")
	orchestrator.register_definition("bush_hazel", "res://scripts/world/plants/BushHazel.gd", "plants")
	orchestrator.register_definition("bush_elder", "res://scripts/world/plants/BushElder.gd", "plants")
	orchestrator.register_definition("bush_dogrose", "res://scripts/world/plants/BushDogrose.gd", "plants")
	# Erze — alle extends HarvestableEntity
	orchestrator.register_definition("iron_ore",    "res://scripts/world/objects/IronOre.gd",           "ores")
	orchestrator.register_definition("copper_ore",  "res://scripts/world/objects/CopperOre.gd",         "ores")
	orchestrator.register_definition("rock_boulder","res://scripts/world/objects/RockBoulder.gd",       "ores")
	# Hain-Skills (Sturmkunde/Imkerei/Sternkunde/Alchemie/Köhlerei) — je ein Weltobjekt, extends
	# HarvestableEntity. XP-Quelle für stormlore/beekeeping/stargazing/alchemy/charcoal_burning.
	# Respawn-Zeiten: WorldService.configure(). Biome: BiomeRegistry.
	orchestrator.register_definition("fulgurite",     "res://scripts/world/objects/Fulgurite.gd",         "ores")
	orchestrator.register_definition("meteorite",     "res://scripts/world/objects/Meteorite.gd",         "ores")
	orchestrator.register_definition("sulfur_crust",  "res://scripts/world/objects/SulfurCrust.gd",       "ores")
	orchestrator.register_definition("wild_beehive",  "res://scripts/world/objects/WildBeehive.gd",       "trees")
	orchestrator.register_definition("charcoal_kiln", "res://scripts/world/objects/CharcoalKiln.gd",      "trees")
	# Nester (Insektenkunde/Graben) — extends HarvestableEntity, siehe docs/nests.md. Biome: BiomeRegistry.
	orchestrator.register_definition("ant_hill",      "res://scripts/world/objects/AntHill.gd",           "trees")
	orchestrator.register_definition("termite_mound", "res://scripts/world/objects/TermiteMound.gd",      "ores")
	orchestrator.register_definition("mole_hill",     "res://scripts/world/objects/MoleHill.gd",          "ores")
	orchestrator.register_definition("wasp_nest",     "res://scripts/world/objects/WaspNest.gd",          "trees")
	orchestrator.register_definition("hornet_nest",   "res://scripts/world/objects/HornetNest.gd",        "trees")
	# Tiere
	orchestrator.register_definition("deer",        "res://scripts/entities/animals/Deer.gd",              "animals")
	orchestrator.register_definition("rabbit",      "res://scripts/entities/animals/Rabbit.gd",            "animals")
	orchestrator.register_definition("boar",        "res://scripts/entities/animals/Boar.gd",              "animals")
	# Wunsch "ein paar mehr Tiere einbauen": ALLE vier neuen Zeilen unten MÜSSEN auch in
	# ChunkEntitySpawner.CURATED_LAND_ANIMAL_TYPES eingetragen sein, sonst spawnen sie nie im Chunk —
	# siehe dortigen Kommentar (bisher ein hartkodiertes randi_range(0,2), das bei jeder
	# Erweiterung dieser Liste hätte manuell nachgezogen werden müssen; jetzt aus der
	# Array-Größe abgeleitet).
	orchestrator.register_definition("fox",         "res://scripts/entities/animals/Fox.gd",               "animals")
	orchestrator.register_definition("squirrel",    "res://scripts/entities/animals/Squirrel.gd",          "animals")
	orchestrator.register_definition("sheep",       "res://scripts/entities/animals/Sheep.gd",              "animals")
	# Wunsch "mehr Körper für Tiere einbauen — Insekten, Spinnen, Schlangen, Fische, große
	# Säugetiere" (siehe AnimalVisualProfile.BodyPlan). Bee/Spider/Snake/Bear laufen über
	# dieselbe landgebundene ChunkEntitySpawner.CURATED_LAND_ANIMAL_TYPES-Liste wie die bisherigen
	# Tiere (siehe dortigen Kommentar) und MÜSSEN deshalb auch dort eingetragen sein. Fish ist
	# die EINZIGE Ausnahme — läuft über die separate ChunkEntitySpawner._spawn_fish() (Wasser
	# statt Land), taucht deshalb bewusst NICHT in CURATED_LAND_ANIMAL_TYPES auf.
	orchestrator.register_definition("bee",         "res://scripts/entities/animals/Bee.gd",               "animals")
	orchestrator.register_definition("spider",      "res://scripts/entities/animals/Spider.gd",            "animals")
	orchestrator.register_definition("snake",       "res://scripts/entities/animals/Snake.gd",              "animals")
	orchestrator.register_definition("bear",        "res://scripts/entities/animals/Bear.gd",               "animals")
	orchestrator.register_definition("fish",        "res://scripts/entities/animals/Fish.gd",               "animals")
	# Wunsch "nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen": ALLE
	# AnimalSpeciesDB-Einträge über GenericAnimal.gd registrieren — EIN Script für beliebig
	# viele Tierarten, statt pro Art eine eigene .gd-Datei + eine eigene Zeile hier. Neue
	# Tierart = neuer AnimalSpeciesDB-Eintrag (siehe tools/animal_species/
	# generate_animal_species_db.py), KEINE Änderung an dieser Funktion nötig. Die zehn
	# handgeschriebenen Arten oben bleiben bewusst bestehen (siehe GenericAnimal.gd-
	# Klassenkommentar) — AnimalSpeciesDB enthält deshalb bewusst KEINE IDs, die mit denen
	# oben kollidieren.
	for species_id in AnimalSpeciesDB.SPECIES:
		orchestrator.register_definition(species_id, "res://scripts/entities/animals/GenericAnimal.gd", "animals")
	# Pets — gezähmte Tiere, spielergebunden statt fungibel (siehe EntityOrchestrator._ready(): kein Pooling).
	orchestrator.register_definition("pet",         "res://scripts/entities/animals/pets/PetComponent.gd",         "pets")
	# NPCs
	orchestrator.register_definition("quest_npc",   "res://scripts/progression/quests/QuestNPC.gd",              "npcs")
	# BUGFIX ("Erik gibt nie eine zweite Quest"): Erik lief bisher über den
	# generischen "quest_npc"-Typ (next_quest_id nie gesetzt). Eigene
	# Subklasse analog Mira/Senna, siehe WoodcutterNPC.gd Klassenkommentar.
	# "quest_npc" bleibt registriert (Basisklasse, von Tests direkt
	# instanziiert — siehe test_quest_npc.gd), wird aber nicht mehr gespawnt.
	orchestrator.register_definition("woodcutter_npc", "res://scripts/progression/quests/WoodcutterNPC.gd",       "npcs")
	# Neue Quest-Geber (Wunsch "Quests weiter ausbauen + NPCs"): Mira gibt
	# quest_miner_defense (existierte bereits als Daten-Ressource, hatte aber
	# nie einen NPC-Träger, siehe MinerNPC.gd) + Folgequest quest_miner_gratitude.
	orchestrator.register_definition("miner_npc",     "res://scripts/progression/quests/MinerNPC.gd",           "npcs")
	# Senna gibt den neuen Foraging-Questchain quest_herbalist_request →
	# quest_herbalist_secret, siehe HerbalistNPC.gd.
	orchestrator.register_definition("herbalist_npc", "res://scripts/progression/quests/HerbalistNPC.gd",       "npcs")
	# Wunsch "Quests ausbauen, aber nicht nur kill/deliver" — zwei neue
	# Questgeber für die bis dahin offenen Kulturkreis-Lücken aus
	# docs/quest-writing-guide.md Abschnitt 1: Wei (chinesische Wudang-
	# Tradition, SKILL-Kette statt Kill-Count) und Babatunde (Yoruba-Egungun-
	# Tradition, TALK-Kette statt Collect/Kill). Siehe WudangMasterNPC.gd /
	# AncestorSpiritNPC.gd Klassenkommentare.
	orchestrator.register_definition("wudang_master_npc", "res://scripts/progression/quests/WudangMasterNPC.gd", "npcs")
	orchestrator.register_definition("ancestor_spirit_npc", "res://scripts/progression/quests/AncestorSpiritNPC.gd", "npcs")
	# Wunsch "ein wirklicher Quest mit Pfiff" — mehrstufige Diebstahl-
	# Geschichte ("Der Dieb im Pelz"), siehe GuardNPC.gd Klassenkommentar.
	orchestrator.register_definition("guard_npc", "res://scripts/progression/quests/GuardNPC.gd", "npcs")
	# ADR-051 Stufe 3 Demo: reagiert im Dialog auf eine fremde Quest
	# (quest_babatunde_tale) — siehe VillageElderNPC.gd Klassenkommentar.
	orchestrator.register_definition("village_elder_npc", "res://scripts/progression/quests/VillageElderNPC.gd", "npcs")
	# Nest-NPCs (docs/nests.md): je ein Quest-Geber pro Nest-Typ, Dialogbaum via quest_npc_scaffold.py.
	orchestrator.register_definition("myrmex_npc", "res://scripts/progression/quests/MyrmexNPC.gd", "npcs")
	orchestrator.register_definition("rudo_builder_npc", "res://scripts/progression/quests/RudoBuilderNPC.gd", "npcs")
	orchestrator.register_definition("surveyor_npc", "res://scripts/progression/quests/SurveyorNPC.gd", "npcs")
	orchestrator.register_definition("zeidler_npc", "res://scripts/progression/quests/ZeidlerNPC.gd", "npcs")
	orchestrator.register_definition("papermaker_npc", "res://scripts/progression/quests/PapermakerNPC.gd", "npcs")
	orchestrator.register_definition("hornet_oracle_npc", "res://scripts/progression/quests/HornetOracleNPC.gd", "npcs")
	orchestrator.register_definition("shop_npc",    "res://scripts/economy/shop/ShopNPC.gd",                     "npcs")
	# Försterei (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen") — eigener
	# Händler-NPC, siehe ForesterNPC.gd Klassenkommentar.
	orchestrator.register_definition("forester_npc", "res://scripts/economy/shop/ForesterNPC.gd",                "npcs")
	orchestrator.register_definition("bank_npc",    "res://scripts/economy/bank/BankNPC.gd",                     "npcs")
	orchestrator.register_definition("auction_house_npc", "res://scripts/economy/trading/AuctionHouseNPC.gd",    "npcs")
	# ADR-048 Round 106: Tutorial-Teil 2 — erklärt UI/UX nahe dem Spawnpunkt,
	# siehe TutorialGuideNPC.gd Klassenkommentar.
	orchestrator.register_definition("tutorial_guide_npc", "res://scripts/onboarding/TutorialGuideNPC.gd",       "npcs")
	# Wunsch "es fehlt ein NPC den ich beklauen kann" — stationärer,
	# beklaubarer Dorfbewohner, siehe VillagerNPC.gd Klassenkommentar.
	orchestrator.register_definition("villager_npc", "res://scripts/entities/theft/VillagerNPC.gd",              "npcs")
	# Zufällige Gebäude (ChunkStructurePlanner/ChunkStructureBuilder): je Gebäudetyp eine Rolle,
	# gespawnt von ChunkEntitySpawner (NICHT in KNOWN_PROP_TYPES — kein Biom-Prop).
	orchestrator.register_definition("settler_npc",       "res://scripts/entities/theft/SettlerNPC.gd",       "npcs")
	orchestrator.register_definition("farmer_npc",        "res://scripts/entities/theft/FarmerNPC.gd",        "npcs")
	orchestrator.register_definition("water_carrier_npc", "res://scripts/entities/theft/WaterCarrierNPC.gd",  "npcs")
	# Berufs-NPCs der Dorfgebäude (ProfessionCatalog): Tagesablauf, Arbeitsbewegung, Tausch.
	# Eigener Skriptpfad je Beruf, weil der MultiplayerSpawner Skriptpfad → type_id auflöst.
	for prof: Dictionary in ProfessionCatalog.all():
		orchestrator.register_definition(String(prof["npc_type"]), String(prof["script"]), "npcs")
	# Farming (Wunsch "Samen pflanzen + ernten") — siehe FarmPlot.gd Klassenkommentar.
	orchestrator.register_definition("farm_plot", "res://scripts/world/farming/FarmPlot.gd",                     "farming")
	# Bausystem: Ansicht eines gebauten Bauteils (Boden/Wand) — gespawnt von WorldBuildHandler pro
	# geladenem Chunk, nicht vom ChunkEntitySpawner (kein Biome-Prop) — daher bewusst NICHT in
	# KNOWN_PROP_TYPES. Siehe BuildPiece.gd Klassenkommentar.
	orchestrator.register_definition("build_piece", "res://scripts/world/building/BuildPiece.gd", "building")
	# Graben in die Tiefe: Leiter-Ansicht und sichtbarer Erz-/Edelstein-Fund — gespawnt von
	# WorldDigHandler pro geladenem Chunk (wie build_piece), daher NICHT in KNOWN_PROP_TYPES.
	# Tier-Zoo am Spawn (siehe ZooPlacer): Glaskasten mit Namensschild. Die Tiere darin sind
	# ganz normale Tier-Entities (oben registriert), nur mit Spawn-Config {"captive": true}.
	orchestrator.register_definition("glass_case", "res://scripts/world/zoo/GlassCase.gd", "zoo")
	orchestrator.register_definition("ladder",   "res://scripts/world/objects/Ladder.gd",  "building")
	orchestrator.register_definition("dig_find", "res://scripts/world/objects/DigFind.gd", "ores")
	# ADR-037: Gravestone — PvE-Tod-Loot (Grab-Hybrid-Timer), gespawnt von
	# DeathLootService, nicht vom ChunkEntitySpawner (kein Biome-Prop) — daher
	# bewusst NICHT in KNOWN_PROP_TYPES/KNOWN_ENEMY_TYPES oben eingetragen.
	orchestrator.register_definition("gravestone", "res://scripts/entities/death/Gravestone.gd", "death")
	# Wunsch "zu wenig Gegner, Friedhöfe als Skelett-Spawner" — DRITTER, klar
	# getrennter Grabstein-Typ (siehe GraveyardGravestone.gd Klassenkommentar
	# für die Abgrenzung zu "gravestone" oben UND zum dekorativen Bau-Grabstein
	# PropShape.GRAVESTONE_STELE/SLAB): NUR dieser Typ hier + der quest-
	# freigeschaltete Spawner-Bau-Grabstein spawnen Skelette. Bewusst DOCH in
	# KNOWN_PROP_TYPES (anders als "gravestone" direkt darüber) — er wird über
	# BiomeDefinition.prop_chances/ChunkEntitySpawner._spawn_graveyard()
	# natürlich in der Welt platziert, nicht von einem Service wie DeathLootService.
	orchestrator.register_definition("graveyard_gravestone", "res://scripts/world/objects/GraveyardGravestone.gd", "graveyard")
	# Analog zu graveyard_gravestone direkt darüber (siehe GoblinCampfire.gd
	# Klassenkommentar) — ebenfalls in KNOWN_PROP_TYPES, weil natürlich über
	# BiomeDefinition.prop_chances/ChunkEntitySpawner platziert, nicht über
	# einen Service wie DeathLootService.
	orchestrator.register_definition("goblin_campfire", "res://scripts/world/objects/GoblinCampfire.gd", "goblin_camp")
	# Feinde
	orchestrator.register_definition("goblin",   "res://scripts/entities/combat/EnemyNPC.gd",    "enemies")
	orchestrator.register_definition("skeleton", "res://scripts/entities/combat/SkeletonNPC.gd", "enemies")
	# Special-Bedingungs-Gegner (siehe KNOWN_SPECIAL_ENEMY_TYPES-Kommentar oben
	# und ConditionalEncounterService.ENCOUNTERS für die Spawn-Bedingungen).
	orchestrator.register_definition("werewolf",   "res://scripts/entities/combat/WerewolfNPC.gd",  "enemies")
	orchestrator.register_definition("fog_wraith", "res://scripts/entities/combat/FogWraithNPC.gd", "enemies")
	AppLogger.log_info("Entity-Definitionen registriert.", LOG_CAT)
