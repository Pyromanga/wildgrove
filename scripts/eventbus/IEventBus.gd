# res://scripts/eventbus/IEventBus.gd
class_name IEventBus extends RefCounted

## IEventBus — Schmale Fassade für Event-Infrastruktur.
##
## Services hängen von IEventBus ab, nicht vom globalen EventBus-AutoLoad.
## Das ermöglicht Tests mit MockEventBus ohne laufenden SceneTree.
##
## PRODUKTION: EventBusAdapter implementiert IEventBus und delegiert 1:1
##             an den echten EventBus-AutoLoad. Zero runtime overhead.
##
## TEST:       MockEventBus implementiert IEventBus und zeichnet alle
##             emit_*()-Aufrufe auf. Signal-Connects funktionieren auf
##             lokalen Instanzen — kein globales State-Bleeding zwischen Tests.
##
## VERWENDUNG in Services:
##   var _bus: IEventBus
##   func configure(deps: ServiceDeps) -> void:
##       _bus = deps.require(ServiceKeys.EVENT_BUS) as IEventBus
##
##   func on_ready() -> void:
##       _bus.player().xp_gained.connect(_on_xp_gained)
##       _bus.quest().emit_quest_started("quest_foo")
##
## WARUM Accessor-Methoden statt Properties:
##   GDScript unterstützt keine abstrakten Property-Overrides über Vererbung.
##   Methoden mit virtualem Override-Pattern sind der einzige zuverlässige Weg.

## Gibt den PlayerEvents-Namespace zurück.
## In Produktion: EventBus.player (echtes AutoLoad-Feld)
## In Tests: lokale PlayerEvents-Instanz
func player() -> PlayerEvents:
	return null

## Gibt den WorldEvents-Namespace zurück.
func world() -> WorldEvents:
	return null

## Gibt den SystemEvents-Namespace zurück.
func system() -> SystemEvents:
	return null

## Gibt den UIEvents-Namespace zurück.
func ui() -> UIEvents:
	return null

## Gibt den QuestEvents-Namespace zurück.
func quest() -> QuestEvents:
	return null

## Gibt den PersistenceEvents-Namespace zurück (ADR-018, vorher Teil von system()).
func persistence() -> PersistenceEvents:
	return null

## Gibt den SessionEvents-Namespace zurück (ADR-018, vorher Teil von system()).
func session() -> SessionEvents:
	return null

## Gibt den NetworkingEvents-Namespace zurück (ADR-018, vorher Teil von system()).
func networking() -> NetworkingEvents:
	return null

## Gibt den ZoneEvents-Namespace zurück (ADR-030).
func zones() -> ZoneEvents:
	return null

## Gibt den CombatEvents-Namespace zurück (Round 98, ADR-036/ADR-042).
func combat() -> CombatEvents:
	return null

## Gibt den BankEvents-Namespace zurück (ADR-034, ADR-050 Phase 2, Round 112).
func bank() -> BankEvents:
	return null

## Gibt den AuctionEvents-Namespace zurück (ADR-035, ADR-050 Phase 2, Round 113).
func auction() -> AuctionEvents:
	return null

## Gibt den TradeEvents-Namespace zurück (ADR-035, ADR-050 Phase 2, Round 113).
func trade() -> TradeEvents:
	return null

## Gibt den ShopEvents-Namespace zurück (Round 88, ADR-050 Phase 2, Round 113).
func shop() -> ShopEvents:
	return null

## Gibt den SmithingEvents-Namespace zurück (Schmelzen & Schmieden, SmithingService).
func smithing() -> SmithingEvents:
	return null
