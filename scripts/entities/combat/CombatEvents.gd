class_name CombatEvents extends BaseEvents

## CombatEvents — EventBus-Namespace für Kampf-/PvP-Lifecycle-Signale.
##
## Gehört fachlich zu scripts/entities/combat/ (wo CombatSystem/
## PvPDeathLossService leben), nicht in den domänenlosen eventbus/-Ordner —
## analog zu ZoneEvents (scripts/world/zones/) und PlayerEvents
## (scripts/entities/player/).
##
## Schließt die in ADR-018 "Bewusst nicht behoben" als funktionale (nicht
## strukturelle) Lücke dokumentierte fehlende `player_killed_by_player`-
## Event-Kategorie — jetzt möglich, weil ADR-042 (Round 96) den dafür
## nötigen "an alle Peers"-Broadcast-Mechanismus liefert.
##
## Einbinden in EventBus.gd:
##   var combat: CombatEvents
##   # in _ready():
##   combat = CombatEvents.new()
##
## Verwendung:
##   EventBus.combat.player_killed_by_player.connect(_on_kill_feed_entry)
##
## WICHTIG (analog ADR-030s ZoneEvents-Konvention): dieses Signal ist die
## KILL-FEED-Quelle, kein Ersatz für PvPDeathLossService.death_loss_applied
## (das bleibt die autoritätsseitige, vollständige Quelle der Wahrheit mit
## den kompletten `items_lost`-Details für die eigentliche Loot-Anwendung).
## player_killed_by_player() feuert auf JEDEM Peer — auf der Autorität
## direkt (kein Rundweg über ihr eigenes Broadcast-RPC, siehe ADR-042s
## "kein Rundweg zur eigenen lokalen Kopie"-Konvention), auf Clients als
## Ergebnis des `broadcast_to_all_peers()`-Empfangs (ADR-042). Der
## `items_lost_count` hier ist bewusst nur eine Stack-ANZAHL (fürs
## Kill-Feed-Display "N Items verloren"), keine Item-Detailliste — welche
## konkreten Items verloren gingen, ist reine Autoritäts-/Opfer-Information,
## kein "alle Spieler sehen alle Loot-Details"-Broadcast.

## Emittiert bei jedem PvP-Tod, auf JEDEM Peer (siehe Klassenkommentar für
## die Autorität-vs-Client-Unterscheidung).
signal player_killed_by_player(
	victim_player_id: String,
	killer_player_id: String,
	victim_was_skulled: bool,
	gold_lost: int,
	items_lost_count: int
)

func _init() -> void:
	super._init("Events/Combat")

func emit_player_killed_by_player(
	victim_player_id: String,
	killer_player_id: String,
	victim_was_skulled: bool,
	gold_lost: int,
	items_lost_count: int
) -> void:
	_log_info(
		"PvP-Kill: '%s' -> '%s' (geskullt=%s, %d Gold, %d Item-Stacks verloren)."
		% [killer_player_id, victim_player_id, victim_was_skulled, gold_lost, items_lost_count]
	)
	player_killed_by_player.emit(victim_player_id, killer_player_id, victim_was_skulled, gold_lost, items_lost_count)
