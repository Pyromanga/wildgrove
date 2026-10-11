class_name ZoneEvents extends BaseEvents

## ZoneEvents — EventBus-Namespace für Zonen-Lifecycle-Signale (ADR-030).
##
## Gehört fachlich zu scripts/world/zones/ (wo ZoneService/ZoneTriggerVolume
## leben), nicht in den domänenlosen eventbus/-Ordner — analog zu
## NetworkingEvents (scripts/networking/) und QuestEvents (scripts/progression/quests/).
##
## Einbinden in EventBus.gd:
##   var zones: ZoneEvents
##   # in _ready():
##   zones = ZoneEvents.new()
##
## Verwendung:
##   EventBus.zones.zone_entered.connect(_on_zone_entered)
##   EventBus.zones.emit_zone_entered(peer_id, &"pvp_north")
##
## WICHTIG (ADR-030 Entscheidung): diese Signale sind die AUTORITATIVE
## Quelle der Wahrheit auf dem Server/Host — nur ZoneService (autoritätsseitig)
## emittiert sie. Ein Client konsumiert sie nur als Ergebnis eines Broadcasts,
## nie als eigene Entscheidungsgrundlage (siehe ADR-030 "Entscheidung").

## Emittiert von ZoneService wenn peer_id eine Zone betritt (autoritätsseitig).
## Mehrere Zonen können gleichzeitig aktiv sein (additiv/Set-basiert, siehe
## ADR-030 "Mitigationen") — dieses Signal feuert pro einzelner neu betretener Zone.
signal zone_entered(peer_id: int, zone_id: StringName)
## Emittiert von ZoneService wenn peer_id eine Zone verlässt (autoritätsseitig).
signal zone_exited(peer_id: int, zone_id: StringName)

func _init() -> void:
	super._init("Events/Zones")

func emit_zone_entered(peer_id: int, zone_id: StringName) -> void:
	_log_info("Peer %d betritt Zone '%s'." % [peer_id, zone_id])
	zone_entered.emit(peer_id, zone_id)

func emit_zone_exited(peer_id: int, zone_id: StringName) -> void:
	_log_info("Peer %d verlässt Zone '%s'." % [peer_id, zone_id])
	zone_exited.emit(peer_id, zone_id)
