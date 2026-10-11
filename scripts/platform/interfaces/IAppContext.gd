# res://scripts/platform/interfaces/IAppContext.gd
class_name IAppContext extends RefCounted

## IAppContext — Schmale Service-Fassade für App-Scope-Consumer.
##
## Analogon zu IUIContext, aber bewusst kein IUIContext: App-Scope-Consumer
## (z.B. MainMenuController) existieren VOR jedem Session-Boot — es gibt zu
## dem Zeitpunkt kein QuestService/InventorySystem/SkillSystem/etc., IUIContext
## wäre hier 15 Getter, die alle immer null zurückgeben würden. ISP: ein
## Consumer der nur den EventBus braucht, bekommt auch nur den EventBus.
##
## VERWENDUNG:
##   AppScope registriert IEventBus als "event_bus"-Resource in seiner eigenen
##   Registry (ServiceOrchestrator._ready(), noch vor jedem Session-Boot).
##   AppContext.from_registry(app_scope.registry) baut daraus die Produktions-
##   Implementierung — derselbe Registry-Key (ServiceKeys.EVENT_BUS) wie
##   Services und UIContext nutzen, kein zweiter Adapter (ADR-012-Prinzip,
##   eine Ebene früher angewendet).
##
## Wird ein zweiter App-Scope-Consumer eine zweite App-Scope-Dependency
## brauchen, wird IAppContext dann um genau diesen einen Getter erweitert —
## nicht vorab spekulativ mit Services befüllt, die (noch) niemand braucht.

## IEventBus — Event-Zugriff für App-Scope-Consumer, die auf Signale lauschen
## oder welche emittieren, bevor eine Session existiert (z.B. MainMenuController:
## Netzwerk-/Session-Events, Boot-Failed).
func bus() -> IEventBus:
	return null
