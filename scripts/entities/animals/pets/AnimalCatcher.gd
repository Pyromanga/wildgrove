class_name AnimalCatcher
extends RefCounted

## AnimalCatcher — Utility zum Umwandeln eines gefangenen Tieres in ein Pet.
## Wird von der Fangen-Aktion in AnimalBase aufgerufen.
##
## Spawnt das Pet über EntityOrchestrator.spawn_entity("pet", ...) statt per
## direktem PetComponent.new() + add_child() — sonst ist das Pet für andere
## Peers unsichtbar (MultiplayerSpawner kennt nur registrierte EntityRegistry-
## Typen) und bekommt keinen owner_peer_id für die Folge-Logik.
##
## owner_peer_id = peer_id, Pflichtparameter vom Aufrufer (AnimalBase._on_interacted()).
## ADR-015 Phase 5: das war zuvor animal.get_multiplayer().get_unique_id() —
## eine Näherung, weil das Interaktionssystem (InteractableComponent.interacted-
## Signal) keine Spieler-Identität trug. Seit Phase 4 trägt es sie echt, also
## wird hier nicht mehr geraten, sondern der reale Wert entgegengenommen.

const LOG_CAT := "AnimalCatcher"

static func catch_animal(animal: AnimalBase, peer_id: int) -> PetComponent:
	if not is_instance_valid(animal):
		return null

	# BUG-FIX: 'animal' kann durch einen zeitgleichen Despawn/Respawn-Zyklus
	# (RespawnService) exakt im Moment des Fangens kurzzeitig aus dem
	# SceneTree entfernt sein. global_position (-> get_global_transform())
	# crasht dann mit "!is_inside_tree()" und liefert eine korrupte
	# Transform3D()-Position für das neue Pet. Sauber abbrechen statt mit
	# falscher Position weiterzumachen.
	if not animal.is_inside_tree():
		AppLogger.log_warn(
			"catch_animal(): '%s' war beim Fangen nicht im SceneTree (Despawn-Race) — abgebrochen." % animal.name,
			LOG_CAT
		)
		return null

	var ctx: IEntityContext = animal.get_context()
	var world: WorldService = ctx.get_world() if is_instance_valid(ctx) else null
	if not is_instance_valid(world):
		AppLogger.log_error(
			"catch_animal(): kein WorldService im EntityContext — Fangen abgebrochen (kein AutoLoad-Fallback).",
			LOG_CAT
		)
		return null

	# Alles vor queue_free() einsammeln — 'animal' ist danach zur Freigabe vorgemerkt.
	var owner_peer_id := peer_id
	var pet_name := "Zahmes " + animal.name
	var pos := animal.global_position
	var bus: IEventBus = ctx.get_event_bus()
	var animal_name := animal.name

	# BUGFIX (2026-09-17, "Dinge werden nicht gesynct"): dieselbe Lücke wie bei
	# EnemyNPC._die()/HarvestableEntity._on_interacted()/Gravestone._request_despawn()
	# — animal.queue_free() unten läuft nur lokal auf der Autorität, kein
	# anderer Peer erfuhr je davon (dessen eigene, lokal gespawnte Kopie des
	# Tieres blieb als Leiche stehen). network kommt bewusst vom Animal selbst
	# (get_context()), nicht vom neu gespawnten Pet — das Pet existiert zu
	# diesem Zeitpunkt noch gar nicht.
	var network: NetworkBridge = ctx.get_network_bridge() if is_instance_valid(ctx) else null
	if is_instance_valid(network):
		network.broadcast_to_all_peers("entity_despawned", {"name": animal_name})
	else:
		AppLogger.log_warn(
			"catch_animal(): kein NetworkBridge verfügbar — Despawn von '%s' wird anderen Peers nicht gemeldet." % animal_name,
			LOG_CAT
		)

	# FEATURE (2026-09-17, "Pets cross-peer sichtbar"): owner_player_id (statt
	# nur owner_peer_id) für EntityOrchestrator.spawn_entity()'s deterministische
	# Namensvergabe — siehe dortiger Kommentar. Leerer String (kein
	# NetworkBridge, z.B. Solo/Tests) → Fallback auf peer_id dort, unverändertes
	# Verhalten.
	var owner_player_id := network.get_player_id_for_peer(owner_peer_id) if is_instance_valid(network) else ""

	# FEATURE (Pet-Fähigkeiten): welche Fähigkeiten (Sammeln/Bergbau/Fällen/
	# Kampf/Graben, siehe PetAbilities) das Pet standardmäßig bekommt, richtet
	# sich nach der gefangenen Tierart. get_script().get_global_name() liefert
	# den class_name-String ("Boar", "Fox", ...) — get_class() liefert hier nur
	# die eingebaute Basisklasse ("CharacterBody3D"), nicht die GDScript-
	# Unterklasse. Leerer/unbekannter Name → PetAbilities.DEFAULT_FALLBACK.
	var species_script: Script = animal.get_script()
	# BUGFIX (Compile-Fehler "variable type is being inferred from a Variant
	# value"): Script.get_global_name() liefert hier als Ergebnis eines
	# ternären Ausdrucks (`... if ... else ""`) einen von Godot nicht statisch
	# auflösbaren Typ, wenn per `:=` inferiert wird — mit "Warnungen als
	# Fehler" bricht das den Compile von AnimalCatcher.gd komplett ab (siehe
	# Log: kaskadiert bis zu Rabbit.gd "Compilation failed", wodurch
	# catch_animal() zur Laufzeit als "Nonexistent function" erscheint,
	# obwohl es die Methode gibt). Fix: explizite Typannotation statt `:=`
	# — vermeidet die Inferenz-Warnung unabhängig von der Ternary-Typprüfung.
	var species_name: String = species_script.get_global_name() if is_instance_valid(species_script) else ""
	# Wunsch "nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen": für ein über
	# GenericAnimal.gd gespawntes Tier liefert get_global_name() immer "GenericAnimal" —
	# unbrauchbar als Unterscheidung für PetAbilities.default_for_species() (alle 39+ neuen
	# Arten bekämen sonst dieselben Default-Fähigkeiten). animal.get_species_id() (nur auf
	# GenericAnimal vorhanden, siehe dort) liefert die tatsächliche, eindeutige Art
	# ("wolf", "trout", ...) und hat deshalb Vorrang, falls vorhanden.
	if animal.has_method("get_species_id"):
		var generic_species_id: String = animal.get_species_id()
		if not generic_species_id.is_empty():
			species_name = generic_species_id
	var config := {
		"name":            pet_name,
		"color":           animal._color,
		"body_size":       animal._body_size,
		"speed":           animal._speed * 0.85,
		# BUGFIX ("Nach dem Fangen ist das ursprüngliche Modell weg"): bisher gingen die
		# kosmetischen Silhouette-Felder (Ohren/Schwanz/Schnauze/Kopfschmuck) beim Fangen
		# verloren — PetComponent baute nur eine schlichte Kapsel mit der übernommenen
		# Farbe/Größe. Jetzt reicht catch_animal() dieselben Felder durch, aus denen das
		# Tier selbst gebaut wurde (siehe AnimalVisualProfile/AnimalVisualBuilder), damit
		# das Pet wie das ursprüngliche Tier aussieht.
		"ear_style":       animal._ear_style,
		"tail_style":      animal._tail_style,
		"snout_style":     animal._snout_style,
		"headgear_style":  animal._headgear_style,
		"tail_scale":      animal._tail_scale,
		"body_plan":       animal._body_plan,
		"wing_style":      animal._wing_style,
		"back_style":      animal._back_style,
		"body_shape":      animal._body_shape,
		"leg_style":       animal._leg_style,
		"pattern_style":   animal._pattern_style,
		"pattern_color":   animal._pattern_color,
		"accent_style":    animal._accent_style,
		"species_id":      species_name,
		"owner_peer_id":   owner_peer_id,
		"owner_player_id": owner_player_id,
		"abilities":       PetAbilities.default_for_species(species_name),
	}

	animal.queue_free()

	var pet := world.spawn_entity("pet", pos, config, owner_peer_id) as PetComponent
	if not is_instance_valid(pet):
		AppLogger.log_error("catch_animal(): spawn_entity('pet') fehlgeschlagen.", LOG_CAT)
		return null

	AppLogger.log_info(
		"Tier gefangen → Pet '%s' erstellt (Besitzer: peer %d)." % [pet_name, owner_peer_id], LOG_CAT
	)
	if is_instance_valid(bus):
		bus.world().emit_interaction_reward_text("Du hast ein %s gefangen!" % pet_name)

	# FEATURE (Quest-Hook fürs Fangen einer BESTIMMTEN Tierart, siehe
	# quest_mira_thief.tres): "catch_animal" (der Interactable-Action-Id, mit
	# der jede Tierart gefangen wird, siehe AnimalBase._setup_catch_interaction())
	# ist für ein INTERACT-Objective zu grob — es würde auf JEDE gefangene Art
	# feuern, nicht nur auf eine bestimmte. Stattdessen ein CUSTOM-Objective-
	# Signal pro Art ("caught_fox", "caught_rabbit", ...), analog zu
	# QuestCustomTrigger._on_body_entered() — hier bewusst per
	# report_domain_event() statt direktem bus.quest()-Emit, weil catch_animal()
	# zwar nur auf der Autorität läuft, QuestService.on_ready() aber laut
	# ADR-021 (R-5) custom_objective_triggered ausschließlich über
	# NetworkBridge.domain_event_received konsumiert (kein Direct-Connect mehr,
	# siehe dortiger Kommentar) — ohne diesen Umweg würde das Signal von
	# QuestService nie ankommen.
	if not species_name.is_empty() and is_instance_valid(network):
		network.report_domain_event(
			"custom_objective_triggered",
			{"signal_key": "caught_" + species_name.to_lower()},
			owner_peer_id
		)

	return pet
