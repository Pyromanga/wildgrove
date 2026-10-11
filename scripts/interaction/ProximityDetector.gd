class_name ProximityDetector
extends Node3D

## ProximityDetector — Area3D-basierte Nähe-Erkennung für Interagierbare.
##
## Extrahiert aus InteractableComponent._setup_detection().
## Emittiert player_entered / player_exited Signale statt direkt Label zu toggeln.
##
## G-02: Signale übergeben jetzt den Player-Node statt anonym zu feuern.
## InteractableComponent kann damit peer_id-korrekt auf den richtigen Spieler reagieren.
##
## Verwendung:
##   var detector := ProximityDetector.new(3.0)
##   add_child(detector)
##   detector.player_entered.connect(_on_player_near)
##   detector.player_exited.connect(_on_player_left)

## G-02: player: Node3D statt leerem Signal — Empfänger wissen welcher Spieler nah ist.
signal player_entered(player: Node3D)
signal player_exited(player: Node3D)

var _radius: float

func _init(radius: float = 3.0) -> void:
	_radius = radius

func _ready() -> void:
	var area := Area3D.new()
	area.name = "DetectionArea"

	var col   := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = _radius
	col.shape = shape
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(body)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_exited.emit(body)
