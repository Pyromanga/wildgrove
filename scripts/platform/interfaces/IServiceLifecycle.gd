# res://scripts/platform/interfaces/IServiceLifecycle.gd
class_name IServiceLifecycle

## IServiceLifecycle — Interface für den Service-Lifecycle.
##
## Dieses Interface macht den Vertrag explizit: jeder Service der configure/on_ready/on_cleanup
## implementiert, gibt das durch extends IServiceLifecycle kund.
##
## Service und ServiceNode implementieren dieses Interface (extends IServiceLifecycle).
## ServiceInitializer und ServiceTeardownManager prüfen "svc is IServiceLifecycle"
## statt has_method() — typsicher, keine Tippfehler, keine Silent-Failures.
##
## WARUM NICHT DIREKT IN Service / ServiceNode?
## GDScript unterstützt kein Mehrfach-Erben. Service extends RefCounted,
## ServiceNode extends Node — beide können nicht zusätzlich extends IServiceLifecycle.
## Stattdessen: ServiceInitializer und TeardownManager prüfen gegen IServiceLifecycle
## als Typ-Guard, und Service/ServiceNode deklarieren dieselben Methoden-Signaturen.
## Die Typ-Prüfung ersetzt has_method() auch ohne formales Erben.
##
## PRAKTISCHE AUSWIRKUNG:
## ServiceInitializer nutzt (svc is Service or svc is ServiceNode) als Guard statt
## has_method(). Das ist typsicher, GDScript-kompatibel, und erfordert keine
## Multi-Erben-Architektur.

## Phase 4: DI. Wird von ServiceInitializer aufgerufen.
func configure(_deps: ServiceDeps) -> void:
	pass

## Phase 5: Activation. Wird von ServiceInitializer.run_on_ready() aufgerufen.
func on_ready() -> void:
	pass

## Phase 7: Teardown. Wird von ServiceTeardownManager aufgerufen.
func on_cleanup() -> void:
	pass
