class_name PlayerMount
extends RefCounted

## PlayerMount — Reit-Zustand eines Spielers (gehört Player.gd, reine Logik ohne Szenenbaum-Zugriff
## außer auf das übergebene Pet).
##
## Solange gemountet:
##  - speed_multiplier() > 1 → Player._apply_movement() skaliert die Lauf-Geschwindigkeit,
##  - das Pet hängt am Reiter (sync_pet(): Position + Blickrichtung), Kollision/KI ruhen,
##  - der Reiter sitzt seat_height() höher (Player setzt das am PlayerVisuals).
## Nur im Solo-Spiel (Player/WorldService prüfen das): Client-Vorhersage und Abgleich im Koop
## kennen den Faktor nicht, würden den Reiter sonst ständig zurückziehen.

var _pet: PetComponent = null
var _saved_layer: int = 0
var _saved_mask: int = 0

func is_mounted() -> bool:
	return is_instance_valid(_pet)

func get_pet() -> PetComponent:
	return _pet if is_instance_valid(_pet) else null

func speed_multiplier() -> float:
	return MountDefinitions.speed_mult_for(_pet.get_species_id()) if is_mounted() else 1.0

func seat_height() -> float:
	return MountDefinitions.seat_height_for(_pet.get_species_id()) if is_mounted() else 0.0

## Prüft, ob rider dieses Pet jetzt besteigen darf. Gibt "" bei Erfolg, sonst einen Grund-Schlüssel.
static func can_mount(rider_pos: Vector3, rider_peer_id: int, pet: PetComponent, already_mounted: bool) -> String:
	if already_mounted:
		return "already_mounted"
	if not is_instance_valid(pet):
		return "no_pet"
	if pet.is_ridden():
		return "taken"
	if not MountDefinitions.is_mountable(pet.get_species_id()):
		return "not_mountable"
	if pet.get_owner_peer_id() != rider_peer_id:
		return "not_owner"
	if pet.global_position.distance_to(rider_pos) > MountDefinitions.MOUNT_RANGE:
		return "too_far"
	return ""

func mount(pet: PetComponent) -> void:
	if is_mounted():
		return
	_pet = pet
	_saved_layer = pet.collision_layer
	_saved_mask = pet.collision_mask
	pet.collision_layer = 0
	pet.collision_mask = 0
	pet.set_ridden(true)

func dismount() -> Vector3:
	## Gibt die Absetz-Position (neben dem Tier) zurück; ohne Reittier Vector3.ZERO.
	if not is_mounted():
		_pet = null
		return Vector3.ZERO
	var spot := _pet.global_position
	_pet.collision_layer = _saved_layer
	_pet.collision_mask = _saved_mask
	_pet.set_ridden(false)
	_pet = null
	return spot

## Pet an den Reiter hängen. yaw: Blickrichtung des Reiter-Modells (Bogenmaß).
func sync_pet(rider_pos: Vector3, yaw: float) -> void:
	if not is_mounted():
		return
	_pet.global_position = rider_pos
	_pet.rotation.y = yaw
	_pet.velocity = Vector3.ZERO
