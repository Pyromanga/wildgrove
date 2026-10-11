class_name WildBush
extends HarvestableEntity

## WildBush — Basis der Sträucher (BushCatalog). Zwei Aktionen auf EINER Entity:
##   "pick_<id>"  Früchte pflücken (foraging)   — primäre Komponente (HarvestableEntity._interactable_comp)
##   "chop_<id>"  roden (woodcutting, Axt-Tempo) — zweite Komponente, siehe _setup_interactable()
## Beide enden im Despawn (HarvestableEntity._on_interacted): Loot + XP kommen aus der jeweils
## gewählten InteractableData. Das Muster "mehrere Komponenten pro Node" gibt es auch beim Spieler
## (Angriff + Handel) und beim VillagerNPC (drei Taschendiebstahl-Stufen).
## Subklassen geben nur _bush_id() zurück (eigener Skriptpfad pro Art, siehe WorldEntityRegistry).

var _pick_data: InteractableData = null
var _chop_data: InteractableData = null

func _bush_id() -> String:
	return ""

func _get_entity_type_id() -> String:
	return BushCatalog.entity_type(_bush_id())

func _build_interactable_data() -> InteractableData:
	var b: Dictionary = BushCatalog.get_bush(_bush_id())
	var d := InteractableData.new()
	d.id            = "pick_%s" % _bush_id()
	d.label         = "%s pflücken" % String(b.get("name", "Strauch"))
	d.duration      = 1.6
	d.xp_type       = BushCatalog.SKILL_PICK
	d.xp_amount     = int(b.get("pick_xp", 10))
	d.loot_table    = load(BushCatalog.pick_loot_path(_bush_id())) as LootTable
	d.yield_stat_id = "gathering_yield_foraging"
	d.inspect_text  = BushCatalog.inspect_text(_bush_id())
	return d

func _build_chop_data() -> InteractableData:
	var b: Dictionary = BushCatalog.get_bush(_bush_id())
	var d := InteractableData.new()
	d.id            = "chop_%s" % _bush_id()
	d.label         = "%s roden" % String(b.get("name", "Strauch"))
	d.duration      = 2.5
	d.xp_type       = BushCatalog.SKILL_CHOP
	d.xp_amount     = int(b.get("chop_xp", 14))
	d.loot_table    = load(BushCatalog.chop_loot_path(_bush_id())) as LootTable
	d.yield_stat_id = "gathering_yield_wood"
	d.speed_stat_id = "gathering_speed_wood"   # Axt-Bonus wie bei Bäumen
	d.inspect_text  = BushCatalog.inspect_text(_bush_id())
	return d

func _setup_interactable() -> void:
	super._setup_interactable()          # primäre Komponente: Pflücken
	_pick_data = _interactable_comp.data
	_chop_data = _build_chop_data()
	var chop_comp := InteractableComponent.new()
	chop_comp.name = "ChopInteractable"
	chop_comp.data = _chop_data
	add_child(chop_comp)
	chop_comp.interacted.connect(_on_interacted)
	if _ctx != null:
		chop_comp.inject_context(_ctx)

func on_spawn(config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	super.on_spawn(config, ctx)
	var chop_comp: Node = get_node_or_null("ChopInteractable")
	if chop_comp is InteractableComponent:
		(chop_comp as InteractableComponent).inject_context(ctx)

## HarvestableEntity löst Loot/XP über _interactable_comp.data auf — für "roden" kurz die Roden-Daten
## einsetzen und danach wieder die Pflück-Daten (die Entity wird gepoolt und wiederverwendet).
func _on_interacted(action_id: String, peer_id: int) -> void:
	var chopping: bool = action_id == "chop_%s" % _bush_id()
	if chopping and is_instance_valid(_interactable_comp):
		_interactable_comp.data = _chop_data
	super._on_interacted(action_id, peer_id)
	if is_instance_valid(_interactable_comp):
		_interactable_comp.data = _pick_data

## Beide Komponenten bleiben beim Visual-Neuaufbau erhalten (Basis behält nur die primäre).
func _clear_visuals() -> void:
	for child in get_children():
		if child is InteractableComponent:
			continue
		remove_child(child)
		child.free()

func _build_visuals() -> void:
	var b: Dictionary = BushCatalog.get_bush(_bush_id())
	if b.is_empty():
		_add_placeholder_box(Vector3(0.8, 0.8, 0.8), Color(0.2, 0.45, 0.2))
		return
	PlantVisualBuilder.build_bush(self, b["look"], hash(position))
