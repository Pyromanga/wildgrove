# res://scripts/platform/AppContext.gd
class_name AppContext extends IAppContext

## AppContext — Produktions-Implementierung von IAppContext.
##
## Löst IEventBus aus derselben Registry auf, die AppScope hält — registriert
## von ServiceOrchestrator._ready() (AppScope.register_event_bus()) VOR
## MenuScopeInitializer/MainMenuController überhaupt existieren. Identischer
## Registry-Key (ServiceKeys.EVENT_BUS) und identischer EventBusAdapter wie
## Services (deps.require()) und Session-UI (UIContext.from_registry()) —
## keine dritte Quelle für denselben Wert.
##
## Gebaut und injiziert von ServiceOrchestrator._on_menu_initializer_ready(),
## analog zu inject_save_system()/inject_session_manager().

var _bus: IEventBus = null

static func from_registry(registry: ServiceRegistry) -> AppContext:
	var ctx := AppContext.new()
	ctx._bus = registry.get_service(ServiceKeys.EVENT_BUS) as IEventBus
	return ctx

static func for_test() -> AppContext:
	return AppContext.new()

func bus() -> IEventBus:
	return _bus
