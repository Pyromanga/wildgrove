# ADR-012 — UI-Layer EventBus-Injektion: `IUIContext.bus()`

**Status:** Accepted
**Datum:** 2026-06
**Schließt ab:** H-07 / ADR-011 (UI-Hälfte) — Services-Hälfte von H-07 bereits über `deps.require(ServiceKeys.EVENT_BUS)` gelöst.
**Bezug:** AUDIT-03 I-02, AUDIT-04 H-07

---

## Kontext

ADR-011 (Säule 3) hat H-07 bewusst in zwei Hälften gesplittet: Services injizieren `IEventBus`
seitdem korrekt über `ServiceDeps.require(ServiceKeys.EVENT_BUS)` — derselbe `EventBusAdapter`,
den auch `BootPipeline` für die Session-Registry registriert. Die UI-Hälfte wurde explizit
zurückgestellt ("~50 Dateien, kein akuter Bug. Separater ADR.").

AUDIT-03 (I-02) hat diese zurückgestellte Hälfte konkretisiert: 10 Dateien in
`scripts/ui/controllers/*.gd` griffen direkt auf den `EventBus`-AutoLoad zu
(`EventBus.player.xp_gained`, `EventBus.ui.emit_notification`, …) — teils zusätzlich zu einem
bereits injizierten `IUIContext`, der die Services kapselt:

```gdscript
# Vorher — SkillPanelController.gd
func setup(visuals: SkillPanelVisuals, ctx: IUIContext) -> void:
    _ctx = ctx                                   # ctx ist da ...
    EventBus.player.xp_gained.connect(_on_xp_gained)   # ... wird aber umgangen.
```

Folge: kein Controller war ohne laufenden `EventBus`-AutoLoad isoliert testbar — exakt das
Problem, das `IEventBus`/`MockEventBus` für Services bereits gelöst hatten, nur eine Schicht
höher.

---

## Entscheidung

`IUIContext` bekommt einen fünften Accessor neben `get_quest()`, `get_skill_system()`,
`get_inventory()`, `get_equipment()`, `get_data()`:

```gdscript
func bus() -> IEventBus:
    return null   # Basis-Vertrag wie alle anderen Getter
```

`UIContext` (Produktions-Implementierung) löst ihn aus **demselben Registry-Key** auf, den auch
Services nutzen — kein zweiter Adapter, keine zweite Quelle:

```gdscript
static func from_registry(registry: ServiceRegistry) -> UIContext:
    ctx._bus = registry.get_service(ServiceKeys.EVENT_BUS) as IEventBus
    # identischer Key wie deps.require(ServiceKeys.EVENT_BUS) in Services
```

Alle 10 betroffenen Controller (`ContextButtonController`, `ContextMenuController`,
`EquipmentUIController`, `FloatingTextController`, `InteractionButtonController`,
`NotificationController`, `PauseMenuController`, `PlayerHPController`, `QuestPanelController`,
`SkillPanelController`) nehmen jetzt ausschließlich `ctx: IUIContext` entgegen und lesen Events
über `_ctx.bus().<namespace>()`. Wo zuvor ein Controller einen rohen Namespace-Typ
(`UIEvents`, `PlayerEvents`, untypisiertes `Object`) als Konstruktor-Parameter bekam
(`ContextButtonController`, `ContextMenuController`, `FloatingTextController`), wird dieser
Parameter durch `ctx` ersetzt — ein einziger Injektionspunkt statt zwei parallelen.

`HUDBuilder.build_all()` und die zugehörigen `*Component.build()`-Fabriken geben `ctx` jetzt an
jede dieser Komponenten weiter; die vorherigen lokalen `EventBus.ui` / `EventBus.player`-Variablen
in `HUDBuilder` entfallen.

**Nachträglich migriert (nicht mehr Teil der Ausnahmeliste):**
- `HUDManager.gd` / `HUDBuilder.gd` — ursprünglich bewusst außerhalb dieses ADR belassen (leben
  außerhalb des Service-Containers, ADR-003/AUDIT-03 II-03, eigener Lifecycle). In einer
  Folge-Session mitmigriert: `HUDManager.boot()` nimmt jetzt eine `ctx`-Factory entgegen und liest
  `_bus = ctx.bus()`; `HUDBuilder` reicht `ctx` an seine Komponenten-Fabriken durch
  (`InteractionComponent.build(hud, ctx.bus().world())`) statt lokaler `EventBus.ui`/`EventBus.player`-Variablen.
- `IEntityContext.get_event_bus() -> IEventBus` — war zum Zeitpunkt der ursprünglichen I-02-Analyse
  noch mit `Node`-Rückgabetyp und lieferte den AutoLoad aus. Ist mittlerweile korrekt typisiert und
  wird von `EntityContext.from_deps()` mit dem injizierten `IEventBus` befüllt — kein separater
  Befund mehr.

**Bewusst außerhalb dieses ADR:**
- `JoystickComponent`, `InteractionComponent`, `InteractionUIController`,
  `InventoryUIController`, `JumpButtonComponent`, `JoystickController` — nehmen Events bereits
  als injizierten Parameter entgegen, kein `EventBus.*`-Zugriff im Controller-Code selbst. Kein
  I-02-Befund, daher unverändert.
- `scripts/ui/MainMenuController.gd` (liegt außerhalb von `scripts/ui/controllers/`) — hat
  dasselbe Muster (4 direkte `EventBus.*`-Aufrufe), aber keinen `IUIContext`-Injektionspunkt
  (existiert vor Session-Boot, die Session-Registry mit dem `event_bus`-Resource gibt es zu dem
  Zeitpunkt noch nicht). Nicht Teil von I-02s Scope; als Folgearbeit vorgemerkt.

---

## Konsequenzen

**Positiv:**
- Alle 10 Controller sind jetzt ohne laufenden `EventBus`-AutoLoad testbar — `UIContext.for_test()`
  + `MockEventBus` (bereits vorhanden für Service-Tests), kein neuer Mock-Typ nötig.
- Ein einziger Injektionspfad pro Controller (`ctx: IUIContext`) statt der vorherigen Mischung aus
  `ctx`, typisiertem Namespace-Parameter und direktem AutoLoad-Zugriff in ein und derselben Datei.
- `EventBusAdapter` bleibt die einzige Produktions-Implementierung von `IEventBus` — UI und
  Services teilen sich denselben Adapter, keine Doppelpflege.

**Neutral:**
- `setup()`-Signaturen von 7 Controllern geändert (Parameter ersetzt, nicht nur ergänzt) — keine
  bestehenden Tests betroffen (vor I-02 gab es keine Controller-Tests, siehe AUDIT-03 IV-03).
- 7 `*Component.build()`-Fabriken + `HUDBuilder.build_all()` entsprechend angepasst.

**Negativ / Trade-off:**
- Volle Testabdeckung für alle 10 Controller ist nicht Teil dieses Fixes — 3 Beispiel-Tests
  (`test_notification_controller.gd`, `test_player_hp_controller.gd`,
  `test_skill_panel_controller.gd`) beweisen den Mechanismus für die drei strukturellen Fälle
  (RefCounted-neu, Node-neu, Node-bereits-ctx). Die übrigen 7 bleiben IV-03 (separat getrackt).

---

## Alternativen erwogen

**Zwei Injektionspunkte behalten** (`event_bus: UIEvents`-Parameter UND `ctx: IUIContext`
parallel) — würde den eigentlichen Bug (zwei Quellen für denselben Wert) nur kaschieren statt
lösen; `ContextButtonController` hatte genau dieses Muster und griff trotzdem zusätzlich direkt
auf den AutoLoad zu.

**Eigener `EventBusContext`/separates Interface nur für UI** — hätte einen zweiten
`IEventBus`-Adapter-Typ erfordert, der zu Services' `EventBusAdapter` synchron bleiben muss.
Mehr Code, kein zusätzlicher Nutzen gegenüber Wiederverwendung von `IEventBus`/`MockEventBus`.

**`EventBus`-AutoLoad direkt durch ein Singleton-Interface ersetzen (volle H-07-Lösung,
~50 Dateien)** — wie in ADR-011 begründet weiterhin zu groß für einen einzelnen, atomar
überprüfbaren Schritt. I-02 löst exakt den Teil mit einem benennbaren Schaden
(nicht testbare UI-Controller); `HUDManager`/`HUDBuilder` wurden in einer Folge-Session
mitmigriert (siehe oben). Der verbleibende Rest (`World.gd`, `MainMenuController.gd`) bleibt
bewusst zurückgestellt, bis ein konkreter Befund dafür vorliegt.
