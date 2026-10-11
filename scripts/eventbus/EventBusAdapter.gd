# res://scripts/eventbus/EventBusAdapter.gd
class_name EventBusAdapter extends IEventBus

## EventBusAdapter — Produktions-Implementierung von IEventBus.
##
## Delegiert 1:1 an den globalen EventBus-AutoLoad.
## Kein eigener State, kein overhead — reine Indirektionsschicht.
##
## Wird von ServiceInstaller als "event_bus"-Dep in die Registry eingetragen
## bevor Services configure() aufgerufen werden. Dadurch bekommen alle Services
## eine IEventBus-Instanz injiziert statt EventBus direkt zu referenzieren.
##
## Die echte EventBus-Instanz (AutoLoad) bleibt unverändert.
## Alle bestehenden UI-Nodes, Scene-Nodes und AutoLoads die EventBus direkt
## nutzen brauchen NICHT angepasst werden — die Adapter-Schicht ist
## ausschließlich für Services (configure/on_ready-Lifecycle).

func player() -> PlayerEvents:
	return EventBus.player

func world() -> WorldEvents:
	return EventBus.world

func system() -> SystemEvents:
	return EventBus.system

func ui() -> UIEvents:
	return EventBus.ui

func quest() -> QuestEvents:
	return EventBus.quest

func persistence() -> PersistenceEvents:
	return EventBus.persistence

func session() -> SessionEvents:
	return EventBus.session

func networking() -> NetworkingEvents:
	return EventBus.networking

func zones() -> ZoneEvents:
	return EventBus.zones

func combat() -> CombatEvents:
	return EventBus.combat

func bank() -> BankEvents:
	return EventBus.bank

func auction() -> AuctionEvents:
	return EventBus.auction

func trade() -> TradeEvents:
	return EventBus.trade

func shop() -> ShopEvents:
	return EventBus.shop

func smithing() -> SmithingEvents:
	return EventBus.smithing
