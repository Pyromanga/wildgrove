class_name NPCVisualBuilder
extends RefCounted

## NPCVisualBuilder — Erstellt die 3D-Visuals für einen NPC.
##
## Ausgelagert aus QuestNPC._build_visuals() (v28).
## Analog zu AnimalVisualBuilder — statisch, kein State.
##
## SEIT DER FIGUREN-ÜBERARBEITUNG baut jeder NPC denselben Körper wie ein Spieler
## (CharacterPartBuilder: Beine, Arme, Gesicht, Haare, Kleidung, Zubehör) statt
## "schwebender Kapsel + Kugel + Hut". Das Aussehen kommt aus NPCLook (Preset pro
## Story-NPC, sonst deterministisch aus dem Namen). Zusätzlich bekommt jeder NPC eine
## CharacterGaze: Augen/Kopf folgen dem nächsten Spieler in Reichweite, sonst schaut er
## sich im Idle um, blinzelt und atmet; ist der Spieler weit seitlich/hinter ihm, dreht
## er sich langsam mit.
##
## Zusätzlich (NPCProps): Handrequisiten (Axt, Spitzhacke, Speer, Korb, ...), Kopfbedeckungen
## (Schutzhelm mit Lampe, Helm, Zylinder), Schal, Rucksack, Umhang und der Geister-Look.
## Die Signatur ist rückwärtskompatibel: `build(parent, name)` und
## `build(parent, name, body_color)` funktionieren wie vorher (body_color wird zur
## Hemdfarbe). Neu ist nur der optionale vierte Parameter `look`.
##
## Erzeugt: "Visual" (Körper + Blicksteuerung), Name-Label3D, Dialog-Label3D
## (returned als Referenz).
##
## ECHTE KLEIDUNG: Was ein NPC trägt (Oberteil, Hose, Schuhe, Hut, Rüstung, ...), sind dieselben
## Items wie beim Spieler (WearableCatalog / ArmorDefinition-IDs im Look). `wear()` zieht ein Teil
## an (ersetzt das im selben Slot), `take_off()` zieht es aus — danach steht der NPC im
## Unterwäsche-Zustand da bzw. ohne dieses Teil. `get_outfit()` listet, was er gerade trägt.
## Nur Optik/lokal wie der Rest des NPC-Aussehens (kein Inventar, kein Netzwerk-Sync).

## Meta-Key am NPC-Knoten: das aufgelöste NPCLook-Spec (Look + Overrides + Prop ...), damit
## wear()/take_off() den Körper mit geänderten Kleidungs-Feldern neu aufbauen können.
const SPEC_META := "npc_visual_spec"

## body_color: optionale Einfärbung des Oberteils, damit unterschiedliche
## NPC-Subklassen (Miner, Herbalist, ...) sich optisch unterscheiden lassen.
## look: optionale Feld-Überschreibungen (CharacterLook-IDs) für diesen NPC.
static func build(parent: Node3D, display_name: String, body_color: Color = NPCLook.DEFAULT_BODY_COLOR, look: Dictionary = {}) -> Label3D:
	var spec := NPCLook.resolve(display_name, body_color, look)
	parent.set_meta(SPEC_META, spec)
	_build_visual(parent, spec)
	var scale_f: float = spec["scale"]

	# Labels über Kopf/Hut (mit Körpergröße mitwachsend).
	var name_y := maxf(2.4, 1.95 * scale_f + 0.45) + float(spec["hover"])

	# Name-Label
	var name_lbl := Label3D.new()
	name_lbl.text      = display_name
	name_lbl.font_size = 48
	name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_lbl.modulate  = Color(1.0, 0.9, 0.3)
	name_lbl.position.y = name_y
	parent.add_child(name_lbl)

	# Dialog-Label (Referenz zurückgeben, da QuestNPC damit arbeitet)
	var dialog_lbl := Label3D.new()
	dialog_lbl.text      = ""
	dialog_lbl.font_size = 36
	dialog_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dialog_lbl.modulate  = Color(1.0, 1.0, 1.0, 0.9)
	dialog_lbl.position.y = name_y + 0.5
	dialog_lbl.visible    = false
	parent.add_child(dialog_lbl)

	return dialog_lbl

# ─────────────────────────────────────────────
# Körper (neu) aufbauen + An-/Ausziehen
# ─────────────────────────────────────────────

## Baut den Knoten "Visual" (Körper, Requisiten, Blicksteuerung) unter `parent`.
static func _build_visual(parent: Node3D, spec: Dictionary) -> Node3D:
	# Körper + Blick unter einem eigenen Knoten — der Eltern-Knoten (StaticBody3D) bleibt
	# unverändert, nur die Optik dreht sich beim Umsehen.
	var visual := Node3D.new()
	visual.name = "Visual"
	var scale_f: float = spec["scale"]
	visual.scale = Vector3.ONE * scale_f
	parent.add_child(visual)

	var parts := CharacterPartBuilder.build(spec["look"], spec["overrides"])
	visual.add_child(parts["root"] as Node3D)
	NPCProps.apply(parts, spec["look"], spec)
	# Geister u. Ä. schweben leicht über dem Boden.
	visual.position.y = float(spec["hover"])

	var gaze := CharacterGaze.new()
	gaze.name = "Gaze"
	gaze.owner_exclude = parent
	gaze.interest_groups = PackedStringArray(["player"])
	gaze.interest_range = 6.0
	gaze.turn_body = visual
	visual.add_child(gaze)
	gaze.bind(parts)
	return visual

## Zieht dem NPC ein Kleidungsstück oder Rüstungsteil an (WearableCatalog-ID oder ArmorDefinition-ID,
## z. B. "cl_hat_cap_green" / "iron_helmet"). Ersetzt, was im selben Slot getragen wird.
## false bei unbekannter ID oder wenn `parent` kein per build() erzeugter NPC ist.
static func wear(parent: Node3D, item_id: String) -> bool:
	var spec := _spec_of(parent)
	if spec.is_empty():
		return false
	var look: Dictionary = spec["look"]
	var armor_slot := WearableCatalog.armor_slot_of_id(item_id)
	if WearableCatalog.is_wearable_id(item_id):
		look = WearableCatalog.wear_in_look(look, item_id)
	elif not armor_slot.is_empty():
		look[WearableCatalog.armor_look_key(armor_slot)] = item_id
	else:
		return false
	_commit(parent, spec, look)
	return true

## Zieht das Teil im Slot aus (Kleidungs-Slot wie "shirt" oder Rüstungs-Slot wie "helmet").
## false bei unbekanntem Slot oder wenn der Slot schon leer war.
static func take_off(parent: Node3D, slot: String) -> bool:
	var spec := _spec_of(parent)
	if spec.is_empty() or not get_outfit(parent).has(slot):
		return false
	var look: Dictionary = spec["look"]
	if WearableCatalog.is_wear_slot(slot):
		look = WearableCatalog.take_off_in_look(look, slot)
	else:
		look[WearableCatalog.armor_look_key(slot)] = "none"
	_commit(parent, spec, look)
	return true

## Was der NPC gerade trägt: { slot: item_id } über Kleidungs- UND Rüstungs-Slots.
static func get_outfit(parent: Node3D) -> Dictionary:
	var spec := _spec_of(parent)
	if spec.is_empty():
		return {}
	return WearableCatalog.full_outfit(spec["look"])

static func _spec_of(parent: Node3D) -> Dictionary:
	if not is_instance_valid(parent) or not parent.has_meta(SPEC_META):
		return {}
	var spec: Variant = parent.get_meta(SPEC_META)
	return spec as Dictionary if spec is Dictionary else {}

## Look im Spec ersetzen und den Körper neu bauen (alten "Visual" VORHER entfernen, sonst
## bekäme der neue Knoten einen automatisch umbenannten Namen).
static func _commit(parent: Node3D, spec: Dictionary, look: Dictionary) -> void:
	spec["look"] = CharacterLook.sanitize(look)
	spec["scale"] = CharacterLook.body_scale(spec["look"])
	parent.set_meta(SPEC_META, spec)
	var old := parent.get_node_or_null("Visual")
	if is_instance_valid(old):
		parent.remove_child(old)
		old.queue_free()
	_build_visual(parent, spec)
