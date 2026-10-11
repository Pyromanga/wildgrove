# res://scripts/economy/equipment/EquipmentService.gd
extends Service
class_name EquipmentService

## EquipmentService — Verwaltet ausgerüstete Items pro Slot.
##
## DESIGN: Slot-basiert (String-Key wie "weapon"), nicht hart auf "die eine
## Waffe" verdrahtet. Jeder Slot bekommt seine eigene StatModifier-source_id
## ("equipment_<slot>") und sein eigenes optionales 3D-Visual — verschiedene
## Slots überschreiben sich dadurch nie gegenseitig, sie koexistieren parallel.
##
## MULTI-TENANCY (Prio 3):
##   _equipped:  { player_id (String): { slot: ItemDefinition } }
##   _visuals:   { player_id (String): { slot: WeaponVisual3D } }
##   ADR-029 Plan-Schritt 4 (Round 66): player_id ist Pflichtparameter (String),
##   kein Default mehr — vierter und letzter der vier Session-Services nach
##   InventorySystem (Round 63), QuestService (Round 64), SkillSystem (Round 65).
##   Kein stiller Fallback auf einen falschen Bucket, siehe InventorySystem-
##   Klassenkommentar für dieselbe Begründung. Kein Parameter-Reordering nötig,
##   player_id stand überall bereits als letzter Parameter.
##
##   Eigenheit gegenüber den drei vorherigen Migrationen: EquipmentService rief
##   ursprünglich in zwei noch unmigrierte Nachbarn hinein — StatModifierService
##   und WorldService.get_player_visuals() erwarteten beide weiterhin peer_id: int
##   (ADR-019/ADR-027). Round 69: StatModifierService ist jetzt ebenfalls
##   migriert (siehe TODO-offene-probleme.md) — add_modifier()/remove_modifier()
##   bekommen player_id direkt, keine Übersetzung mehr. WorldService.
##   get_player_visuals() bleibt der letzte unmigrierte Nachbar; diese Klasse
##   übersetzt dafür weiterhin an ihrer eigenen Aufrufgrenze zurück von String
##   nach int (_resolve_peer_id() unten) — das Gegenstück zu
##   _resolve_player_uuid() (int → String), das SkillSystem/QuestService für
##   EINGEHENDE Aufrufe von noch nicht migrierten Quellen nutzen. Dritter
##   Nachbar: CombatSystem.get_equipped_weapon()-Aufrufer (player_melee_damage()/
##   apply_weapon_on_hit()) — die übersetzen selbst nach String, über dieselbe
##   _resolve_player_uuid()-Stelle, die Round 65 bereits für den Skill-Level-
##   Lookup eingeführt hat (nicht dupliziert).
##
##   _resolve_player_uuid() (int → String, für den has_item()-Aufruf aus
##   Round 63) entfällt komplett — EquipmentService führt jetzt selbst String,
##   direkter Pass-through statt Übersetzung.
##
## PERSISTENZ (Prio 3):
##   Implementiert ISaveProvider. Save-Key: "equipment".
##   Format: { "player_id": { "weapon": "item_id", "helmet": null, ... } }
##   Benötigt DataService in deps für ItemDefinition-Lookup beim Load.
##   Migration: SaveMigrationService v3 ergänzt leeres "equipment"-Objekt für Saves < v3.
##   Save-Migration (ADR-029 Plan-Schritt 5) entfällt — siehe TODO-offene-probleme.md,
##   keine nennenswerten Bestandsdaten in existierenden Coop-Saves.
##
## VERANTWORTUNG:
##   equip()/unequip()        → Item in einen Slot setzen/entfernen.
##   get_equipped_weapon()    → Bequemlichkeits-Accessor für CombatSystem.
##
## NICHT VERANTWORTLICH für:
##   - Inventar-Abzug beim Equip (InventorySystem bleibt Quelle der Wahrheit
##     über Item-Besitz — Verdrahtung "equip aus Inventar" ist UI-/Interaction-
##     Schicht, nicht dieser Service)
##
## VERWENDUNG:

const LOG_CAT := "Equipment"

## Präfix für StatModifier-source_ids — Komplett-Cleanup via remove_modifiers_with_prefix().
const SOURCE_PREFIX := "equipment_"
const SLOT_WEAPON   := "weapon"
const SLOT_TOOL      := "tool"  ## Axt/Spitzhacke — Gathering-Werkzeuge (ToolDefinition)
## Rüstungs-Slots (ArmorDefinition) — gleiche Strings wie EquipmentUIController.SLOT_LABELS.
const SLOT_HELMET := "helmet"
const SLOT_CHEST  := "chest"
const SLOT_LEGS   := "legs"
const SLOT_BOOTS  := "boots"
## Stat, auf den ausgerüstete Rüstung wirkt (FLAT_ADD je Slot) — CombatSystem.equipped_armor_bonus().
const STAT_ARMOR  := "armor"
## XP-Bonus-Stats (PERCENT_ADD): "xp_gain" für alle Skills, "xp_gain_<skill_id>" je Skill —
## gelesen von SkillSystem.add_action_xp(). Quelle: ItemDefinition.xp_bonus.
const STAT_XP_GAIN := "xp_gain"
const XP_ALL_KEY   := "all"

var _stat_modifiers: StatModifierService = null
var _save_system: SaveSystem = null
var _data: DataService = null
var _network: NetworkBridge = null
## ADR-027: für has_item()-Besitzprüfung in on_equip_confirmed() (schließt R-4).
var _inventory: InventorySystem = null
## ADR-027: löst PlayerVisuals für player_id selbst auf statt sie entgegen-
## zunehmen. Late-Inject statt configure()-Dep — WorldService deklariert
## "equipment" bereits als eigenen Dep, ein Rückweg über BootstrapConfig.tres
## wäre ein zirkulärer Dep-Fehler im Resolver (siehe inject_world_service()).
var _world: WorldService = null

## Anziehbare Kleidung (WearableCatalog-Slots wie "shirt") lebt NICHT in _equipped, sondern im
## replizierten Look des Spielers (CharacterCreationService) — der ist schon gespeichert, gesynct
## und für alle sichtbar. Dieser Service prüft nur Besitz/Slot und bucht Inventar ↔ Look um.
## Rüstung (helmet/chest/legs/boots) bleibt hier die Wahrheit und wird in den Look GESPIEGELT,
## damit sie am Körper erscheint. Late-Inject (siehe inject_wearables()).
var _wearables: CharacterCreationService = null
## true während clear_player(): Session-Ende räumt nur den Laufzeit-State ab und darf den
## gespeicherten Look (Rüstungs-Spiegel) nicht mit leeren.
var _mirror_paused: bool = false

## _equipped:  { player_id (String): { slot (String): ItemDefinition } }
var _equipped: Dictionary = {}

## BUGFIX (2026-09-25, "PvE-Schutz-Scroll überlebt Equip/Unequip nicht"):
## { player_id (String): { slot (String): ItemInstance } } — Parallel-Ablage
## NUR für on_equip_confirmed()/on_unequip_confirmed() (siehe dort). _equipped
## selbst bleibt bewusst ItemDefinition (Item-TYP — get_equipped_weapon() für
## CombatSystem etc. braucht nur den Typ, keine Instanz-Identität). Die
## is_pve_death_protected/is_theft_protected/is_pvp_protected/durability/uuid-
## Felder leben aber auf der ItemInstance in InventorySystem, nicht auf
## ItemDefinition — ohne diese Ablage würde remove_item() beim Equip die
## einzige Instanz mit diesem Zustand zerstören, und ein simples
## request_add_item() beim Unequip würde beim Zurücklegen eine NEUE, wieder
## ungeschützte Instanz erzeugen.
var _equipped_instances: Dictionary = {}

## _visuals:   { player_id (String): { slot (String): WeaponVisual3D } }
var _visuals: Dictionary = {}

## Emittiert wenn ein Slot equipped/unequipped wurde. item_def == null bei unequip.
## R-7 (ADR-022): `player_id` ergänzt — fehlte bisher komplett. Ohne dieses
## Argument konnte kein Listener unterscheiden, FÜR WEN sich Equipment geändert
## hat — `EquipmentUIController`/`InventoryUIController` aktualisierten sich bei
## JEDER Änderung irgendeines Spielers und lasen dann trotzdem nur Spieler 1s
## Daten (siehe R-7-Fund in TODO-offene-probleme.md).
## ADR-029 Round 66: player_id jetzt String (siehe Klassenkommentar).
signal equipment_changed(slot: String, item_def: ItemDefinition, player_id: String)

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_stat_modifiers = deps.get_optional(ServiceKeys.STAT_MODIFIERS) as StatModifierService
	_save_system = deps.require(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	_data = deps.get_optional(ServiceKeys.DATA) as DataService
	_network = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	_inventory = deps.get_optional(ServiceKeys.INVENTORY) as InventorySystem
	## R-7 (ADR-022): siehe identischer Kommentar in InventorySystem.configure().
	_connect_economy_sync()
	if not is_instance_valid(_stat_modifiers):
		AppLogger.log_debug("StatModifierService nicht in deps — Equipment-Boni nicht verfügbar.", LOG_CAT)
	if is_instance_valid(_save_system):
		_save_system.register_save_provider(self)
		load_data(_save_system.get_state_for("equipment"))
	else:
		AppLogger.log_warn("SaveSystem nicht in deps — Equipment wird nicht gespeichert/geladen.", LOG_CAT)
	AppLogger.log_info("EquipmentService konfiguriert (Multi-Tenant + Persistenz).", LOG_CAT)

## Phase S8.6 Late-Inject — NetworkBridge wird nach vollem Session-Boot injiziert.
## R-7 (ADR-022): siehe identischer Kommentar in InventorySystem.inject_network_bridge()
## — Phase C6 (on_ready) läuft vor Phase C8 (dieser Late-Inject), `_network`
## ist zum Zeitpunkt von on_ready() garantiert noch null.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_economy_sync()

## R-7 (ADR-022): gemeinsamer, idempotenter Connect-Helfer für configure() und
## inject_network_bridge().
func _connect_economy_sync() -> void:
	if is_instance_valid(_network) and not _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.connect(_on_economy_state_received)

## ADR-027 Late-Inject — analog zu inject_network_bridge(): WorldService kann
## nicht als configure()-Dep bezogen werden (WorldService deklariert "equipment"
## bereits selbst als Dep — ein Rückweg über BootstrapConfig.tres wäre ein
## zirkulärer Dep, den der Resolver ablehnt). Wird von BootPipeline.boot_character()
## aufgerufen, sobald beide Services in der Session-Registry instanziiert sind.
func inject_world_service(world: WorldService) -> void:
	_world = world

## Late-Inject (Zyklus-Vermeidung wie inject_world_service()): CharacterCreationService hält den
## Look, in den Kleidung geschrieben wird. Gleicht außerdem den Rüstungs-Spiegel aller bekannten
## Spieler an (Save geladen → Rüstung wieder sichtbar) und lässt das Panel auf Look-Änderungen
## reagieren (Kleidung ändert sich per Look-Update, auch auf Clients).
func inject_wearables(host: CharacterCreationService) -> void:
	_wearables = host
	if not is_instance_valid(_wearables):
		return
	if not _wearables.look_changed.is_connected(_on_worn_look_changed):
		_wearables.look_changed.connect(_on_worn_look_changed)
	for pid in _equipped.keys():
		for armor_slot in ArmorDefinition.all_slot_ids():
			var item: ItemDefinition = (_equipped[pid] as Dictionary).get(armor_slot)
			_mirror_armor(armor_slot, item.id if is_instance_valid(item) else "", String(pid))

func on_ready() -> void:
	AppLogger.log_info("EquipmentService bereit.", LOG_CAT)

func on_cleanup() -> void:
	if is_instance_valid(_network) and _network.economy_state_received.is_connected(_on_economy_state_received):
		_network.economy_state_received.disconnect(_on_economy_state_received)
	for pid in _visuals.keys():
		var slots: Dictionary = _visuals[pid]
		for slot in slots.keys():
			var wv: WeaponVisual3D = slots[slot]
			if is_instance_valid(wv):
				wv.detach()
				wv.queue_free()
	_visuals.clear()

	if is_instance_valid(_stat_modifiers):
		# ADR-029 Round 69: StatModifierService führt jetzt ebenfalls player_id
		# (String) — die Übersetzung, die hier bis Round 68 nötig war, entfällt
		# komplett (siehe TODO-offene-probleme.md, § Wichtig). _equipped-Keys
		# SIND bereits player_id, kein Zwischenschritt mehr nötig.
		for pid_str in _equipped.keys():
			_stat_modifiers.remove_modifiers_with_prefix(SOURCE_PREFIX, pid_str)

	_equipped.clear()
	AppLogger.log_info("EquipmentService cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# ISaveProvider
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return "equipment"

func get_save_data() -> Dictionary:
	## Serialisiert alle ausgerüsteten Items: { "player_id": { "slot": "item_id"|null } }
	## ADR-029 Round 66: pid ist bereits die player_id (String) — kein str()
	## mehr nötig, war bisher nur wegen int-Keys erforderlich.
	var result: Dictionary = {}
	for pid in _equipped:
		var slots: Dictionary = _equipped[pid]
		var serialized: Dictionary = {}
		for slot in slots:
			var item: ItemDefinition = slots[slot]
			serialized[slot] = item.id if is_instance_valid(item) else null
		result[pid] = serialized
	return result

func load_data(data: Dictionary) -> void:
	## Deserialisiert — benötigt DataService für item_id → ItemDefinition Lookup.
	## ADR-029 Round 66: pid_str ist bereits die player_id — keine int()-
	## Konvertierung mehr, keine Übergangslogik für alte peer_id-Saves (siehe
	## InventorySystem/QuestService/SkillSystem, Round 63-65, "Save-Migration
	## entfällt").
	_equipped.clear()
	if not is_instance_valid(_data):
		AppLogger.log_warn("load_data: DataService fehlt — Equipment wird nicht wiederhergestellt.", LOG_CAT)
		return

	for pid_str in data:
		var pid: String = str(pid_str)
		var slots: Dictionary = data[pid_str]
		_equipped[pid] = {}
		for slot in slots:
			var item_id = slots[slot]
			if item_id == null or item_id == "":
				continue
			var item: ItemDefinition = _data.get_item(item_id)
			if is_instance_valid(item):
				_equipped[pid][slot] = item
				_apply_stat_bonus(slot, item, pid)
			else:
				AppLogger.log_warn("load_data: Item '%s' nicht gefunden — Slot '%s' bleibt leer." % [item_id, slot], LOG_CAT)
	AppLogger.log_info("Equipment geladen (%d Spieler)." % _equipped.size(), LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Rüstet item_def in slot aus. Slots sind exklusiv (ein zweites equip() auf
## denselben Slot ruft zuerst unequip() auf — symmetrisch zu StatModifierService).
## [param visuals] Optional — nur nötig wenn item_def ein 3D-Visual besitzt.
## [return] false bei ungültigen Parametern.
##
## Direktaufruf — nur auf der Autorität sicher. Für Netzwerk-sichere Variante: request_equip().
## ADR-029 Round 66: player_id ist jetzt String, Pflichtparameter ohne Default —
## EINZIGE Methode dieser Migration, die eine Parameter-Reihenfolge ändert
## (player_id rückt vor `visuals`): GDScript erlaubt keinen Pflichtparameter
## nach einem Parameter mit Default, `visuals` behält seinen Default (null),
## also muss player_id davor stehen. Alle Aufrufer werden ohnehin für den
## Typwechsel int → String angefasst, die Umsortierung kostet keinen
## zusätzlichen Blindflug an einer separaten Stelle.
func equip(slot: String, item_def: ItemDefinition, player_id: String, visuals: PlayerVisuals = null) -> bool:
	if slot.is_empty():
		AppLogger.log_error("equip: slot darf nicht leer sein!", LOG_CAT)
		return false
	if not is_instance_valid(item_def):
		AppLogger.log_error("equip: item_def ungültig.", LOG_CAT)
		return false

	unequip(slot, player_id)

	_player_equipped(player_id)[slot] = item_def
	_apply_stat_bonus(slot, item_def, player_id)
	_mirror_armor(slot, item_def.id, player_id)

	# BUGFIX (2026-09-25, "Equipment wird nicht 3D gerendert (Axt/Spitzhacke/
	# Schaufel)"): war bisher auf `item_def is WeaponDefinition` beschränkt —
	# ToolDefinition (Gathering-Werkzeuge, SLOT_TOOL) ist KEIN
	# WeaponDefinition-Subtyp (beide erben unabhängig von ItemDefinition),
	# bekam also nie ein WeaponVisual3D angehängt. WeaponVisual3D.attach_to()
	# nimmt jetzt generisch ItemDefinition entgegen und branched intern
	# selbst auf WeaponDefinition/ToolDefinition (siehe dortiger Kommentar).
	if (item_def is WeaponDefinition or item_def is ToolDefinition) and is_instance_valid(visuals):
		var wv := WeaponVisual3D.new()
		wv.attach_to(visuals, item_def)
		_player_visuals(player_id)[slot] = wv

	AppLogger.log_info("Ausgerüstet: '%s' in Slot '%s' (player %s)." % [item_def.display_name, slot, player_id], LOG_CAT)
	equipment_changed.emit(slot, item_def, player_id)
	return true

## Entfernt das Item aus slot. Räumt StatModifier + Visual symmetrisch ab.
## [return] false wenn der Slot bereits leer war.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func unequip(slot: String, player_id: String) -> bool:
	var equipped := _player_equipped(player_id)
	if not equipped.has(slot):
		return false

	if is_instance_valid(_stat_modifiers):
		# ADR-029 Round 69: StatModifierService führt jetzt player_id (String) —
		# keine Übersetzung mehr nötig an dieser Aufrufgrenze.
		# Präfix statt Einzel-Id: ein Item kann mehrere Modifier belegen (Hauptwert + XP-Boni).
		_stat_modifiers.remove_modifiers_with_prefix(_source_id(slot), player_id)

	var visuals := _player_visuals(player_id)
	if visuals.has(slot):
		var wv: WeaponVisual3D = visuals[slot]
		if is_instance_valid(wv):
			wv.detach()
			wv.queue_free()
		visuals.erase(slot)

	var removed: ItemDefinition = equipped[slot]
	equipped.erase(slot)
	_mirror_armor(slot, "", player_id)

	AppLogger.log_info("Entfernt: '%s' aus Slot '%s' (player %s)." % [removed.display_name, slot, player_id], LOG_CAT)
	equipment_changed.emit(slot, null, player_id)
	return true

## Gibt das ausgerüstete Item in slot zurück, oder null wenn leer.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func get_equipped(slot: String, player_id: String) -> ItemDefinition:
	if WearableCatalog.is_wear_slot(slot):
		return _worn_item(slot, player_id)
	return _player_equipped(player_id).get(slot)

## Bequemlichkeits-Accessor für CombatSystem.
## [return] null wenn der Slot leer ist oder kein WeaponDefinition enthält.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default —
## genau wie bei equip() muss player_id deshalb VOR slot stehen (GDScript
## erlaubt keinen Pflichtparameter nach einem Parameter mit Default). Aufrufer:
## EquipmentUIController._refresh_stats(), CombatSystem.player_melee_damage()/
## apply_weapon_on_hit() — alle drei übergeben slot ohnehin bereits explizit.
func get_equipped_weapon(player_id: String, slot: String = SLOT_WEAPON) -> WeaponDefinition:
	var item: ItemDefinition = _player_equipped(player_id).get(slot)
	return item as WeaponDefinition if item is WeaponDefinition else null

## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func is_equipped(slot: String, player_id: String) -> bool:
	if WearableCatalog.is_wear_slot(slot):
		return is_instance_valid(_worn_item(slot, player_id))
	return _player_equipped(player_id).has(slot)

## Räumt alle Slots eines Spielers — bei Disconnect/Session-Ende.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func clear_player(player_id: String) -> void:
	_mirror_paused = true
	for slot in _player_equipped(player_id).keys():
		unequip(slot, player_id)
	_mirror_paused = false
	_equipped.erase(player_id)
	_visuals.erase(player_id)
	# BUGFIX (2026-09-25, siehe _equipped_instances-Klassenkommentar): sonst
	# bliebe eine verwaiste ItemInstance-Referenz für player_id hängen, falls
	# hier noch ein equipptes Item ohne vorherigen on_unequip_confirmed()-Lauf
	# vorhanden war.
	_equipped_instances.erase(player_id)
	AppLogger.log_info("Equipment für player %s geleert." % player_id, LOG_CAT)

# ─────────────────────────────────────────────
# C-03: Netzwerk-sichere API (Tier 1/2/3)
# ─────────────────────────────────────────────

## Netzwerk-sichere Variante von equip().
## Tier 1 (Solo): ruft on_equip_confirmed() direkt auf.
## Tier 2/3 (Coop): schickt RPC an Autorität via NetworkBridge.
## [param item_id] Item-ID aus DataService — NetworkBridge serialisiert nur Strings, kein ItemDefinition.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func request_equip(slot: String, item_id: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_equip_item(slot, item_id, player_id)
	else:
		on_equip_confirmed(slot, item_id, player_id)

## Netzwerk-sichere Variante von unequip().
## Tier 1 (Solo): ruft on_unequip_confirmed() direkt auf.
## Tier 2/3 (Coop): schickt RPC an Autorität via NetworkBridge.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func request_unequip(slot: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_unequip_item(slot, player_id)
	else:
		on_unequip_confirmed(slot, player_id)

## Authority-Mutation: Wird von request_equip() (Tier 1) und NetworkBridge._rpc_equip_item() (Tier 2/3) aufgerufen.
## C-02 Guard: nur Autorität darf Equipment-State mutieren.
##
## ADR-027: kein visuals-Parameter mehr — eine Node-Referenz vom Aufrufer wäre auf
## Tier 2/3 weder serialisierbar noch im richtigen Szenenbaum gültig. Die Autorität
## löst PlayerVisuals stattdessen selbst über WorldService.get_player_visuals(player_id)
## auf, also die Kopie des ZIEL-Spielers, nicht die des Aufrufers.
##
## Schließt R-4: has_item()-Prüfung sitzt jetzt auf dem einzigen Pfad, über den das
## Spiel tatsächlich ausrüstet (InventoryUIController/EquipmentUIController rufen
## seit ADR-027 request_equip() statt equip() direkt auf).
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
## player_id ist bereits die stabile player_uuid — die frühere Rückübersetzung
## über _resolve_player_uuid() (Round 63, peer_id → uuid) entfällt hier komplett,
## has_item() bekommt player_id direkt (Pass-through statt Übersetzung, siehe
## Klassenkommentar).
func on_equip_confirmed(slot: String, item_id: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_equip_confirmed: Aufruf auf Nicht-Autorität (peer %d) — verweigert." % _network.get_local_peer_id(),
			LOG_CAT
		)
		return
	var item_def := _data.get_item(item_id) if is_instance_valid(_data) else null
	if not is_instance_valid(item_def):
		AppLogger.log_error("on_equip_confirmed: Unbekannte Item-ID '%s'." % item_id, LOG_CAT)
		return
	if not _slot_accepts(slot, item_def):
		AppLogger.log_warn(
			"on_equip_confirmed: Item '%s' passt nicht in Slot '%s' — Equip verweigert." % [item_id, slot],
			LOG_CAT
		)
		return
	if is_instance_valid(_inventory) and (player_id.is_empty() or not _inventory.has_item(item_id, player_id)):
		AppLogger.log_warn(
			"on_equip_confirmed: player %s besitzt Item '%s' nicht — Equip verweigert."
			% [player_id, item_id],
			LOG_CAT
		)
		return
	# Kleidung: kein _equipped-Eintrag, sondern Look-Umbuchung (siehe _wear_confirmed()).
	if WearableCatalog.is_wear_slot(slot):
		_wear_confirmed(slot, item_id, player_id)
		return
	# WorldService.get_player_visuals() führt weiterhin peer_id (int) — Übersetzung
	# an dieser Aufrufgrenze, siehe Klassenkommentar/_resolve_peer_id().
	var visuals_peer_id := _resolve_peer_id(player_id)
	var visuals: PlayerVisuals = _world.get_player_visuals(visuals_peer_id) if (is_instance_valid(_world) and visuals_peer_id != -1) else null

	# BUGFIX (2026-09-25, "Waffe bleibt nach dem Anlegen im Inventar"): equip()
	# selbst mutiert bewusst NUR den Slot-State (siehe Klassenkommentar oben,
	# "NICHT VERANTWORTLICH für Inventar-Abzug") — die has_item()-Prüfung oben
	# verhinderte zwar Equip ohne Besitz, aber nirgends im Spiel gab es tatsächlich
	# einen Aufrufer, der das Item nach erfolgreichem Equip aus dem Inventar
	# entfernt hat (weder hier noch in InventoryUIController/EquipmentUIController
	# — beide rufen nur request_equip() auf). on_equip_confirmed() ist der
	# einzige Pfad, über den das Spiel tatsächlich equippt (siehe TODO-Eintrag
	# zu ADR-027) — daher hier, nicht in equip() selbst: load_data() (Save-
	# Restore) und _on_economy_state_received() (Client-Sync) rufen equip()
	# direkt auf und dürfen NICHT nochmal am Inventar abziehen, das ist schon
	# geschehen bzw. läuft über den separaten "inventory"-Sync-Kanal.
	#
	# Slot-Swap: war bereits ein anderes Item in diesem Slot, wirft equip()
	# es über den internen unequip()-Aufruf einfach weg (Stat-Modifier/Visual
	# abgebaut, aber nie zurück ins Inventar) — Item wäre sonst komplett
	# verloren, nicht nur "hängt doppelt rum". Alten Item-Stand VOR equip()
	# sichern und danach zurückbuchen.
	#
	# BUGFIX (2026-09-25, siehe Klassenkommentar zu _equipped_instances): die
	# tatsächliche ItemInstance des NEU angelegten Items (mit ihrem Schutz-/
	# Durability-/uuid-Zustand) VOR dem Entfernen aus dem Inventar sichern —
	# sonst zerstört remove_item() sie ersatzlos, sobald die Menge auf 0 fällt.
	var previous_item := get_equipped(slot, player_id)
	var previous_instance: ItemInstance = _player_equipped_instances(player_id).get(slot)
	var new_instance: ItemInstance = _inventory.get_item_instance(player_id, item_id) if is_instance_valid(_inventory) else null
	equip(slot, item_def, player_id, visuals)
	if is_instance_valid(_inventory):
		_inventory.remove_item(item_id, player_id, 1)
		_player_equipped_instances(player_id)[slot] = new_instance
		if is_instance_valid(previous_item) and previous_item.id != item_id:
			if is_instance_valid(previous_instance):
				_inventory.restore_item_instance(player_id, previous_instance)
			else:
				_inventory.request_add_item(previous_item.id, player_id, 1)
	## R-7 (ADR-022): Rücksync an einen entfernten Client — analog zu
	## InventorySystem/SkillSystem. Bewusst NUR die Daten (slot + item_id), kein
	## Visual-Handle — 3D-Visual-Replikation über Peers ist ein separates,
	## szenenbaum-repliziertes Thema (WeaponVisual3D), nicht Teil dieses Rücksyncs;
	## siehe ADR-022 „Umsetzungsstand" für die explizite Abgrenzung.
	## ADR-029 Round 66: send_economy_update_for_player() (String) statt
	## send_economy_update() (int) — EquipmentService ist jetzt der letzte der
	## drei Aufrufer, die auf das String-Pendant umgestellt sind (siehe
	## NetworkBridge.send_economy_update_for_player()-Kommentar).
	if is_instance_valid(_network):
		_network.send_economy_update_for_player(player_id, "equipment", {"slot": slot, "item_id": item_id})

## Authority-Mutation: Wird von request_unequip() (Tier 1) und NetworkBridge._rpc_unequip_item() (Tier 2/3) aufgerufen.
## C-02 Guard: nur Autorität darf Equipment-State mutieren.
## ADR-029 Round 66: player_id jetzt String, Pflichtparameter ohne Default.
func on_unequip_confirmed(slot: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error(
			"on_unequip_confirmed: Aufruf auf Nicht-Autorität (peer %d) — verweigert." % _network.get_local_peer_id(),
			LOG_CAT
		)
		return
	if WearableCatalog.is_wear_slot(slot):
		_take_off_confirmed(slot, player_id)
		return
	# BUGFIX (2026-09-25, siehe on_equip_confirmed() + Klassenkommentar zu
	# _equipped_instances): Item-Stand VOR unequip() sichern und — falls
	# vorhanden — die exakte ursprüngliche ItemInstance zurückgeben statt über
	# request_add_item() eine neue (wieder ungeschützte) zu erzeugen. Ohne das:
	# Scroll angewendet → Waffe angelegt (Instanz zerstört) → wieder abgelegt
	# (neue, ungeschützte Instanz) → Tod → Schutz war weg, Waffe verloren.
	var previous_item := get_equipped(slot, player_id)
	var previous_instance: ItemInstance = _player_equipped_instances(player_id).get(slot)
	unequip(slot, player_id)
	_player_equipped_instances(player_id).erase(slot)
	if is_instance_valid(_inventory) and is_instance_valid(previous_item):
		if is_instance_valid(previous_instance):
			_inventory.restore_item_instance(player_id, previous_instance)
		else:
			_inventory.request_add_item(previous_item.id, player_id, 1)
	## R-7 (ADR-022): Rücksync an einen entfernten Client (item_id=null → dieser
	## Slot ist jetzt leer, siehe _on_economy_state_received()-Gegenstück).
	if is_instance_valid(_network):
		_network.send_economy_update_for_player(player_id, "equipment", {"slot": slot, "item_id": null})

# ─────────────────────────────────────────────
# Debug-API
# ─────────────────────────────────────────────
func get_debug_report(player_id: String) -> Array[String]:
	var result: Array[String] = []
	for slot in _player_equipped(player_id):
		var item: ItemDefinition = _player_equipped(player_id)[slot]
		result.append("[%s] %s" % [slot, item.display_name])
	return result

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

## R-7 (ADR-022), Client-Seite: wendet einen von der Autorität gesendeten
## Slot-Zustand auf den EIGENEN lokalen Player an. Ruft bewusst `equip()`/
## `unequip()` direkt auf (nicht `on_*_confirmed()` — deren C-02-Guard würde
## hier fälschlich greifen, da dieser Prozess per Definition nicht die Autorität
## ist) — dieser Pfad IST bereits die netzwerk-empfangende Seite, kein zweiter
## Guard nötig. Kein Visual-Parameter (siehe on_equip_confirmed()-Kommentar) —
## visuals bleiben unverändert, nur der Daten-State wird synchronisiert.
func _on_economy_state_received(kind: String, payload: Dictionary) -> void:
	if kind != "equipment":
		return
	if not is_instance_valid(_network):
		return
	# ADR-029 Round 66: player_id (String) statt peer_id (int) — genau wie
	# InventorySystem/QuestService/SkillSystem übernimmt dieser Client-Pfad
	# jetzt die stabile Identität statt der Routing-peer_id.
	var local_id := _network.get_local_player_id()
	var slot: String = payload.get("slot", "")
	if slot.is_empty():
		return
	var item_id = payload.get("item_id")
	if item_id == null:
		unequip(slot, local_id)
		return
	var item_def := _data.get_item(item_id) if is_instance_valid(_data) else null
	if not is_instance_valid(item_def):
		AppLogger.log_error("_on_economy_state_received: unbekannte Item-ID '%s'." % str(item_id), LOG_CAT)
		return
	equip(slot, item_def, local_id, null)

## Stat-Id für den XP-Bonus eines Skills ("all" → STAT_XP_GAIN).
static func xp_stat_for(skill_id: String) -> String:
	return STAT_XP_GAIN if skill_id == XP_ALL_KEY else "%s_%s" % [STAT_XP_GAIN, skill_id]

## ItemDefinition.xp_bonus → ein PERCENT_ADD-Modifier je Eintrag (source_id mit eigenem Suffix,
## damit mehrere Boni desselben Slots sich nicht überschreiben; unequip() räumt per Präfix ab).
func _apply_xp_bonus(slot: String, item_def: ItemDefinition, player_id: String) -> void:
	for key in item_def.xp_bonus:
		var factor := float(item_def.xp_bonus[key])
		if factor == 0.0:
			continue
		_stat_modifiers.add_modifier(StatModifier.permanent(
			"%s:xp:%s" % [_source_id(slot), key], xp_stat_for(String(key)),
			StatModifier.Operation.PERCENT_ADD, factor
		), player_id)

## Darf item_def in slot? Rüstung nur in ihren eigenen Slot (sonst könnte ein Client dasselbe
## Teil in mehrere Slots legen und die Rüstung vervielfachen); Rüstungs-Slots nehmen nur Rüstung.
func _slot_accepts(slot: String, item_def: ItemDefinition) -> bool:
	if item_def is ArmorDefinition:
		return (item_def as ArmorDefinition).get_slot_id() == slot
	if item_def is WearableDefinition:
		return (item_def as WearableDefinition).wear_slot == slot
	# Alles andere (Waffe, Werkzeug, ...) gehört weder in Rüstungs- noch in Kleidungs-Slots.
	return not ArmorDefinition.is_armor_slot(slot) and not WearableCatalog.is_wear_slot(slot)

## Kleidungsstück, das player_id im Slot trägt (aus dem Look), oder null.
func _worn_item(slot: String, player_id: String) -> ItemDefinition:
	if not is_instance_valid(_wearables):
		return null
	var item_id := _wearables.get_worn_item_id(player_id, slot)
	if item_id.is_empty():
		return null
	return _data.get_item(item_id) if is_instance_valid(_data) else WearableCatalog.get_item(item_id)

## Autorität: Kleidung anziehen. Das Item verlässt das Inventar; was vorher im Slot getragen
## wurde, kommt zurück hinein. Besitz und Slot-Passung sind in on_equip_confirmed() schon geprüft.
func _wear_confirmed(slot: String, item_id: String, player_id: String) -> void:
	if not is_instance_valid(_wearables):
		AppLogger.log_warn("Kleidung anziehen: kein CharacterCreationService injiziert — verweigert.", LOG_CAT)
		return
	var previous_id := _wearables.get_worn_item_id(player_id, slot)
	if previous_id == item_id:
		return
	if not _wearables.set_worn(player_id, slot, item_id):
		return
	if is_instance_valid(_inventory):
		_inventory.remove_item(item_id, player_id, 1)
		if not previous_id.is_empty():
			_inventory.request_add_item(previous_id, player_id, 1)
	AppLogger.log_info("Angezogen: '%s' in Slot '%s' (player %s)." % [item_id, slot, player_id], LOG_CAT)

## Autorität: Kleidung ausziehen. Das Teil wandert ins Inventar; ist es voll, bleibt es am Körper
## (sonst ginge das Kleidungsstück verloren).
func _take_off_confirmed(slot: String, player_id: String) -> void:
	if not is_instance_valid(_wearables):
		return
	var previous_id := _wearables.get_worn_item_id(player_id, slot)
	if previous_id.is_empty():
		return
	if is_instance_valid(_inventory) and _inventory.get_free_slots(player_id) <= 0 and not _inventory.has_item(previous_id, player_id):
		AppLogger.log_warn("Ausziehen verweigert: Inventar von %s ist voll." % player_id, LOG_CAT)
		return
	if not _wearables.set_worn(player_id, slot, ""):
		return
	if is_instance_valid(_inventory):
		_inventory.request_add_item(previous_id, player_id, 1)
	AppLogger.log_info("Ausgezogen: '%s' aus Slot '%s' (player %s)." % [previous_id, slot, player_id], LOG_CAT)

## Rüstung → Look-Spiegel (nur Autorität; set_armor_mirror() ignoriert Clients selbst).
func _mirror_armor(slot: String, item_id: String, player_id: String) -> void:
	if _mirror_paused:
		return
	if is_instance_valid(_wearables) and ArmorDefinition.is_armor_slot(slot):
		_wearables.set_armor_mirror(player_id, slot, item_id)

## Look hat sich geändert (Kleidung an/aus, auch von der Autorität per Rückkanal empfangen):
## Equipment-Panel/Inventar sollen neu zeichnen. Slot/Item sind hier unbekannt (leer/null).
func _on_worn_look_changed(player_id: String) -> void:
	equipment_changed.emit("", null, player_id)

func _source_id(slot: String) -> String:
	return SOURCE_PREFIX + slot

## ADR-029 Round 66: Übersetzt player_uuid → peer_id — das Gegenstück zu
## _resolve_player_uuid() (int → String), das SkillSystem/QuestService/
## EquipmentService (bis Round 65/vor dieser Migration) für EINGEHENDE Aufrufe
## von noch nicht migrierten Quellen nutz(t)en. Round 69: StatModifierService
## ist migriert (siehe TODO-offene-probleme.md) und braucht diese Übersetzung
## nicht mehr — der einzige verbliebene Aufrufer ist WorldService.
## get_player_visuals(), noch peer_id (int) (separater, noch offener Punkt im
## selben TODO-Eintrag). -1 wenn kein NetworkBridge injiziert ist ODER
## player_id keinem verbundenen Peer zugeordnet werden kann (z.B. Spieler
## gerade offline) — Aufrufer müssen das prüfen, kein stiller Fallback auf
## Spieler 1.
func _resolve_peer_id(player_id: String) -> int:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_peer_id('%s'): kein NetworkBridge injiziert — Übersetzung nicht möglich." % player_id,
			LOG_CAT
		)
		return -1
	return _network.get_peer_id_for_player(player_id)


func _player_equipped(player_id: String) -> Dictionary:
	if not _equipped.has(player_id):
		_equipped[player_id] = {}
	return _equipped[player_id]

func _player_visuals(player_id: String) -> Dictionary:
	if not _visuals.has(player_id):
		_visuals[player_id] = {}
	return _visuals[player_id]

## BUGFIX (2026-09-25, siehe _equipped_instances-Klassenkommentar).
func _player_equipped_instances(player_id: String) -> Dictionary:
	if not _equipped_instances.has(player_id):
		_equipped_instances[player_id] = {}
	return _equipped_instances[player_id]

## Übersetzt die Boni eines ausgerüsteten Items in StatModifier(e).
## ADR-029 Round 69: player_id geht jetzt direkt an StatModifierService —
## keine Übersetzung mehr, dieser Service führt selbst player_id (String).
func _apply_stat_bonus(slot: String, item_def: ItemDefinition, player_id: String) -> void:
	if not is_instance_valid(_stat_modifiers):
		return
	_apply_xp_bonus(slot, item_def, player_id)
	if item_def is WeaponDefinition:
		var weapon := item_def as WeaponDefinition
		if weapon.damage_bonus != 0.0:
			_stat_modifiers.add_modifier(StatModifier.permanent(
				_source_id(slot), "damage_bonus", StatModifier.Operation.FLAT_ADD, weapon.damage_bonus
			), player_id)
	elif item_def is ArmorDefinition:
		var armor := item_def as ArmorDefinition
		if armor.armor_value != 0.0:
			_stat_modifiers.add_modifier(StatModifier.permanent(
				_source_id(slot), STAT_ARMOR, StatModifier.Operation.FLAT_ADD, armor.armor_value
			), player_id)
	elif item_def is ToolDefinition:
		var tool := item_def as ToolDefinition
		if not tool.speed_stat_id.is_empty() and tool.speed_bonus != 0.0:
			_stat_modifiers.add_modifier(StatModifier.permanent(
				_source_id(slot), tool.speed_stat_id, StatModifier.Operation.PERCENT_ADD, tool.speed_bonus
			), player_id)
