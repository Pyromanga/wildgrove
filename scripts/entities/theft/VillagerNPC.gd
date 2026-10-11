extends StaticBody3D
class_name VillagerNPC

## VillagerNPC — Stationärer, beklaubarer Dorfbewohner (Wunsch "es fehlt ein
## NPC den ich beklauen kann").
##
## Bewusst nach ShopNPC.gd-Muster gebaut (StaticBody3D, kein CharacterBody3D/
## keine KI wie EnemyNPC) — ein Villager kämpft nicht und bewegt sich nicht,
## er steht nur herum und lässt sich bestehlen. Drei feste Aktionen
## ("pickpocket_weak/normal/strong"), exakt wie PlayerPickpocket.gd es für
## Spieler-Ziele macht (gleiche Kristall-Tiers, gleiche Konstanten in
## PickpocketService) — nur das Ziel ist hier ein NPC statt ein anderer
## Spieler-Node.
##
## AUTORITÄTS-ROUTING: anders als PlayerPickpocket/Player._on_pickpocket_
## requested() (das über NetworkBridge.send_pickpocket_attempt() explizit
## zur Autorität routen muss, weil ein Spieler-Node nicht zwingend
## Server-Autorität hat) braucht es hier KEINEN eigenen Netzwerk-Zweig:
## VillagerNPC ist wie EnemyNPC/HarvestableEntity ein normales Welt-Entity
## mit set_multiplayer_authority(1) — InteractableComponent._handle_
## completion() routet Klicks von Nicht-Autorität-Peers bereits generisch
## zur Autorität (siehe HarvestableEntity._on_interacted()-Kommentar
## "ADR-020 / R-1"). _on_interacted() unten läuft deshalb, exakt wie
## EnemyNPC._on_interacted(), direkt gegen PickpocketService.
##
## Siehe PickpocketService.on_pickpocket_npc_confirmed() für die eigentliche
## Diebstahl-Mechanik (Formel/Cooldown identisch zur Spieler-Variante, nur
## der stehlbare Pool ist ein fester Gold-Bereich statt echtem Inventar).

const LOG_CAT := "VillagerNPC"

## Konfigurierbar via on_spawn(config) — analog EnemyNPC.
@export var npc_display_name: String = "Dorfbewohner"
var _gold_min: int = 5
var _gold_max: int = 40
## Fiktiver "Verteidigungs-Level" gegen den die Diebstahl-Chance läuft
## (ersetzt SkillSystem.get_level() eines echten Opfers, siehe
## PickpocketService.on_pickpocket_npc_confirmed()). Niedrig gehalten —
## Villager sind ein leichtes Einstiegsziel, kein Endgame-Opfer.
var _defense_level: int = 5

var _dialog_label: Label3D
var _ctx: IEntityContext = null

## Pet-Kampf (Wunsch "Pets sollen wie Pokémon kämpfen, Dorfbewohner kann man herausfordern"): Aktions-ID
## der Herausforderung, Kampf-Runde (nach jedem Sieg ein neues Gegner-Team) und Ruhepause nach einer
## Niederlage des Dorfbewohners. Rein lokaler Zustand je Peer — das Gegner-Team folgt deterministisch aus
## Name + Runde (PetBattleEncounter.seed_for), muss also nicht übertragen werden.
const ACTION_PET_BATTLE := "pet_battle"
const BATTLE_REST_MSEC: int = 300000  # 5 Minuten
var _battle_round: int = 0
var _battle_rest_until_msec: int = 0
var _battle_bus: IEventBus = null

const _CRYSTAL_BY_ACTION := {
	"pickpocket_weak":   "theft_crystal_weak",
	"pickpocket_normal": "theft_crystal_normal",
	"pickpocket_strong": "theft_crystal_strong",
}
const _TIER_CONFIG := [
	{"action_id": "pickpocket_weak",   "label": "Taschendiebstahl (schwach)", "comp_name": "PickpocketWeakInteractable"},
	{"action_id": "pickpocket_normal", "label": "Taschendiebstahl",           "comp_name": "PickpocketNormalInteractable"},
	{"action_id": "pickpocket_strong", "label": "Taschendiebstahl (stark)",   "comp_name": "PickpocketStrongInteractable"},
]

func _ready() -> void:
	name = "VillagerNPC_" + npc_display_name.replace(" ", "_")
	add_to_group("npcs")
	set_multiplayer_authority(1)
	_dialog_label = NPCVisualBuilder.build(self, npc_display_name, _get_body_color(), _npc_look_overrides())
	_build_collision()
	_setup_interactable()
	AppLogger.log_info("VillagerNPC '%s' bereit." % npc_display_name, LOG_CAT)

## Hook für Subklassen (SettlerNPC-Rollen, ProfessionNPC): Hemdfarbe statt Standardblau.
## Standardfarbe = NPCLook.DEFAULT_BODY_COLOR → Aussehen unverändert.
func _get_body_color() -> Color:
	return NPCLook.DEFAULT_BODY_COLOR

## Hook für Subklassen: CharacterLook-Felder, die den (namensbasierten) Zufalls-Look überschreiben,
## z. B. {"sex": "female"}. Leer = Zufalls-Look unverändert.
func _npc_look_overrides() -> Dictionary:
	return {}

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	for tier_config in _TIER_CONFIG:
		var d := InteractableData.new()
		d.id           = tier_config["action_id"]
		d.label        = "%s (%s)" % [tier_config["label"], npc_display_name]
		d.duration     = 0.5
		# Kein xp_type/xp_amount — die Diebstahl-XP vergibt PickpocketService
		# selbst (Erfolg/Fehlschlag unterschiedlich), passt nicht ins feste
		# InteractionResolver-Schema. Identisches Muster wie PlayerPickpocket.gd.
		d.inspect_text = "%s. Wirkt beschäftigt und unaufmerksam." % npc_display_name
		var comp := InteractableComponent.new()
		comp.name = tier_config["comp_name"]
		comp.data = d
		add_child(comp)
		comp.interacted.connect(_on_interacted)

	var battle_data := InteractableData.new()
	battle_data.id           = ACTION_PET_BATTLE
	battle_data.label        = "Zum Pet-Kampf herausfordern (%s)" % npc_display_name
	battle_data.duration     = 0.3
	battle_data.inspect_text = "%s. Hat eigene Tiere dabei und lässt sich auf einen Pet-Kampf ein." % npc_display_name
	var battle_comp := InteractableComponent.new()
	battle_comp.name = "PetBattleInteractable"
	battle_comp.data = battle_data
	add_child(battle_comp)
	battle_comp.interacted.connect(_on_interacted)

## Bevorzugter Typ der Gegner-Tiere dieses Berufs (PetBattleTypes.Type, -1 = keiner). Subklassen
## (Bauer, Wasserträger) überschreiben das für etwas Charakter.
func _battle_bias_type() -> int:
	return -1

## Herausforderung. Läuft NUR auf dem Peer, der interagiert hat (das Kampf-Fenster ist rein lokal; pets
## sind client-autoritativ) — die über InteractableComponent geroutete Kopie auf dem Server ignoriert das.
func _on_pet_battle_interacted(peer_id: int) -> void:
	if not is_instance_valid(_ctx) or peer_id != _ctx.get_local_peer_id():
		return
	var bus: IEventBus = _ctx.get_event_bus()
	if not is_instance_valid(bus):
		return
	if Time.get_ticks_msec() < _battle_rest_until_msec:
		bus.world().emit_interaction_reward_text("%s ruht sich noch vom letzten Kampf aus." % npc_display_name)
		return
	bus.ui().emit_pet_battle_requested(
		String(name), npc_display_name, PetBattleEncounter.seed_for(String(name), _battle_round), _battle_bias_type()
	)

func _on_pet_battle_finished(villager_key: String, won: bool) -> void:
	if villager_key != String(name) or not won:
		return
	_battle_round += 1
	_battle_rest_until_msec = Time.get_ticks_msec() + BATTLE_REST_MSEC

## Siehe Klassenkommentar "AUTORITÄTS-ROUTING" — kein Netzwerk-Zweig nötig,
## direkter Aufruf gegen PickpocketService, exakt wie EnemyNPC._on_interacted()
## gegen CombatSystem.
func _on_interacted(action_id: String, peer_id: int) -> void:
	if action_id == ACTION_PET_BATTLE:
		_on_pet_battle_interacted(peer_id)
		return
	if not action_id.begins_with("pickpocket_"):
		return
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_interacted(): kein EntityContext gespeichert — Diebstahl verweigert.", LOG_CAT)
		return

	var pickpocket: PickpocketService = _ctx.get_pickpocket()
	if not is_instance_valid(pickpocket):
		AppLogger.log_error("_on_interacted(): kein PickpocketService im Context — Diebstahl verweigert.", LOG_CAT)
		return

	var crystal_item_id: String = _CRYSTAL_BY_ACTION.get(action_id, "")
	if crystal_item_id.is_empty():
		AppLogger.log_error("_on_interacted(): unbekannte action_id '%s'." % action_id, LOG_CAT)
		return

	var network: NetworkBridge = _ctx.get_network_bridge()
	var thief_id := network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	if thief_id.is_empty():
		AppLogger.log_warn("_on_interacted(): player_id-Übersetzung fehlgeschlagen — Diebstahl verweigert.", LOG_CAT)
		return

	pickpocket.on_pickpocket_npc_confirmed(thief_id, name, crystal_item_id, _gold_min, _gold_max, _defense_level)

# ─────────────────────────────────────────────
# Collision
# ─────────────────────────────────────────────

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.5
	col.shape = sh
	col.position.y = 0.75
	add_child(col)

# ─────────────────────────────────────────────
# EntityOrchestrator-Interface
# ─────────────────────────────────────────────

## npc_display_name wird bewusst NICHT hier aus cfg übernommen (anders als
## z.B. EnemyNPC._label): _ready() (und damit NPCVisualBuilder.build() mit
## dem Namens-Label) läuft laut EntityOrchestrator-Kontrakt VOR on_spawn() —
## ein Override hier käme fürs Label immer zu spät. Wer einen anderen Namen
## braucht, setzt das @export-Feld an der Szene/Definition, nicht über cfg.
func on_spawn(cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	# Ohne Kontext erreicht eine Nicht-Host-Interaktion die Autorität nicht und "Untersuchen"
	# bleibt stumm (InteractableComponent._handle_completion()/get_actions()). EnemyNPC macht
	# dasselbe in seinem on_spawn().
	if is_instance_valid(ctx):
		for child in get_children():
			if child is InteractableComponent:
				(child as InteractableComponent).inject_context(ctx)
	if is_instance_valid(ctx):
		_battle_bus = ctx.get_event_bus()
		if is_instance_valid(_battle_bus) and not _battle_bus.ui().pet_battle_finished.is_connected(_on_pet_battle_finished):
			_battle_bus.ui().pet_battle_finished.connect(_on_pet_battle_finished)
	if cfg.has("gold_min"):       _gold_min        = cfg["gold_min"]
	if cfg.has("gold_max"):       _gold_max        = cfg["gold_max"]
	if cfg.has("defense_level"):  _defense_level   = cfg["defense_level"]

func on_despawn() -> void:
	if is_instance_valid(_battle_bus) and _battle_bus.ui().pet_battle_finished.is_connected(_on_pet_battle_finished):
		_battle_bus.ui().pet_battle_finished.disconnect(_on_pet_battle_finished)
