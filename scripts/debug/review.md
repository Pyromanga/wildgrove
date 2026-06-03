## Code-Review: Analyse & Ist-/Soll-Abgleich

Zunächst zur Frage „Warum hat das Terminal nichts geloggt?“ – das liegt sehr wahrscheinlich am Boot-Abbruch in Phase 1. Der `ServiceValidator` meldet

> *Resource konnte nicht geladen werden (Pfad okay, aber Datei defekt?).*

… und daraufhin bricht der `ServiceOrchestrator` ab. Ohne erfolgreichen Boot werden keine weiteren Logeinträge erzeugt, und das In‑Game‑Terminal (`SimpleTerminal`) zeigt nur das an, was der `Logger` tatsächlich ausgibt.  
Der Fehler selbst deutet auf eine fehlende oder defekte Abhängigkeit der `BootstrapConfig.tres` hin – sehr wahrscheinlich fehlen die Skriptdateien `BootstrapConfig.gd` und/oder `ServiceDefinition.gd`, oder sie enthalten Syntaxfehler.  

---

Ich habe alle bereitgestellten Dateien geprüft und mit den Architekturvorgaben aus deiner Spezifikation verglichen. Nachfolgend die Ergebnisse als ausführliche Markdown-Dokumentation, aufgeteilt in **Ist‑Zustand**, **Soll‑Zustand** und einen **Maßnahmenkatalog**.

---

### 📄 1. `review_current_state.md` – Analyse des vorhandenen Codes

```markdown
# 🔍 Ist‑Analyse des WildGrove Core Systems

Stand: 2026-06-03 (erste Session)

## 1. Boot‑Pipeline

### 1.1 ServiceOrchestrator
- Struktur entspricht den 6 Phasen der Spezifikation.
- Nutzt eigene Pipeline-Objekte (`ServiceValidator`, `ServiceDependencyResolver`, …).
- Bricht bei Validierungsfehler korrekt ab.
- **Problem:** EventBus.system.boot_failed wird emittiert, aber die Existenz des Signals ist nicht garantiert (SystemEvents nicht überprüft).

### 1.2 BootstrapConfig.tres
- Definiert 12 Services mit `service_name`, `path`, `deps`.
- Keine `required_data_files` gesetzt → Validator-Prüfung für Daten-Ressourcen läuft ins Leere.
- Pfade sind relativ (`res://scripts/services/…`).  
- Die externe Ressource `BootstrapConfig.gd` wird referenziert – **diese Datei fehlt im gelieferten Satz!** Das ist die wahrscheinlichste Ursache für den Boot-Fehler.
- Ebenso fehlt `ServiceDefinition.gd`.

### 1.3 ServiceValidator
- Prüft Existenz der Config, null-Sicherheit, leere Namen, Pfade.
- **Erweiterungen für Daten-Ressourcen und Zirkularitätscheck sind schon vorgesehen**, aber `required_data_files` nie gefüllt.
- `_load_config()` liefert `null`, wenn die Resource nicht geladen werden kann – hier schlägt es aktuell fehl.

### 1.4 ServiceDependencyResolver
- Implementiert Kahn’s Algorithmus mit Lower‑Case‑Normalisierung.
- Erkennt Zyklen und unbekannte Abhängigkeiten.
- Keine Auffälligkeiten.

### 1.5 ServiceFactory
- Unterscheidet `PackedScene` und `GDScript`.
- Setzt `service_name` und registriert VOR `add_child()`.
- Gut abgesichert.

### 1.6 Services (Autoload)
- Typisierte Variablen für alle registrierten Services.
- `populate()` wird erst in Phase 6 aufgerufen.
- **Kritisch:** Viele Services greifen in ihrer `init()`-Methode auf `Services.save_system` etc. zu – zu diesem Zeitpunkt ist das Autoload **noch nicht gefüllt**. Das führt zu Null-Referenzen und Blockaden.

## 2. Services – Überblick

| Service | Typ | init() verwendet Services.* | Bewertung |
| --- | --- | --- | --- |
| `DataService` | Service | Nein | ✅ OK |
| `SaveSystem` | Service | Nein | ✅ OK |
| `PlayerStateService` | ServiceNode | Nein | ✅ OK |
| `InventorySystem` | ServiceNode | `Services.save_system` | ❌ |
| `SkillSystem` | ServiceNode | `Services.save_system` | ❌ |
| `WorldService` | ServiceNode | `Services.save_system` | ❌ |
| `GameManager` | ServiceNode | `Services.save_system` | ❌ |
| `Factory3D` | ServiceNode | Nein | ✅ OK |
| `InteractionBuilder` | ServiceNode | `Services.player_states` | ❌ |
| `HUDManager` | ServiceNode | Nein | ✅ OK |
| `UIFactory` | ServiceNode | Nein | ✅ OK |
| `QuestService` | Service | Nein | ✅ OK |

**Fazit:** Fünf Services versuchen in `init()` auf das `Services`‑Autoload zuzugreifen, das erst in Phase 6 befüllt wird. Das ist ein schwerer Verstoß gegen die definierte Lebenszyklus‑Trennung.

## 3. EventBus & Kommunikation

- `EventBus.gd` erzeugt Namespaces (`player`, `world`, `system`, `ui`, `quest`).
- Die entsprechenden Event-Klassen (`PlayerEvents`, `SystemEvents` …) wurden **nicht geliefert**, aber die Verwendung im Code setzt sie voraus.
- In `WorldService` wird `EventBus.world.emit_time_of_day_changed(0)` aufgerufen – Existenz dieser Methode unklar.

## 4. Logger & Terminal

- `Logger` funktioniert grundsätzlich, nutzt `print()`.
- `SimpleTerminal` hängt sich an `Logger.on_log` und bietet Befehle.
- Keine offensichtlichen Fehler.

## 5. Fehlende Dateien (nicht geliefert, aber referenziert)

- `ServiceInitializer.gd`
- `ServiceInstaller.gd`
- `ServiceTeardownManager.gd`
- `ServiceRegistry.gd`
- `BootstrapConfig.gd` / `ServiceDefinition.gd`
- `PlayerEvents.gd`, `WorldEvents.gd`, `SystemEvents.gd`, `UIEvents.gd`, `QuestEvents.gd`
- `PlayerData.tres`, `GameConfig.tres` (vom Code erwartet)
- `ItemDefinition.gd`
- `InteractableAction.gd`
- `HUD.gd` / `HUDBuilder.gd`
- `WorldData.gd`, `WorldFactory.gd`

Ohne diese Dateien ist das System nicht lauffähig.

## 6. Hauptkritikpunkte

1. **Fehlende Ressourcen** (BootstrapConfig.gd, ServiceDefinition.gd) → Boot-Abbruch.
2. **Verfrühter Zugriff auf Services‑Autoload** in Phase 4 → Race‑Condition und Null‑Pointer.
3. **Fehlende Dependency Injection** in `init()` – Services müssen ihre Abhängigkeiten anders bekommen.
4. **Ungetestete Event‑Signale** – die Verbindungen können nicht geprüft werden.
5. **Keine Multiplayer‑/Permission‑Schicht** (noch nicht implementiert, aber Architektur sieht sie vor).
```

---

### 📄 2. `target_architecture.md` – Soll‑System gemäß Spezifikation

```markdown
# 🧱 Soll‑Architektur des WildGrove Core Systems

(Extrahiert aus den mitgelieferten Markdown-Spezifikationen)

## 1. Boot‑Pipeline (6 Phasen)

| Phase | Aufgabe | Beteiligte Komponenten |
| --- | --- | --- |
| 1. Validate | Config prüfen, Ressourcen-Existenz, keine Zirkel | `ServiceValidator`, `BootstrapConfig` |
| 2. Resolve | Topologische Sortierung der `deps` | `ServiceDependencyResolver` |
| 3. Instantiate | Services erzeugen, in Registry eintragen | `ServiceFactory` |
| 4. Init | Abhängigkeiten injizieren, **kein** Zugriff auf `Services`‑Autoload | `ServiceInitializer` übergibt Referenzen |
| 5. Activate | `on_ready()`: Signale verbinden, externe Kommunikation starten | `ServiceInitializer` (oder separater Activator) |
| 6. Install | `Services`‑Autoload befüllen, globale Verfügbarkeit herstellen | `ServiceInstaller` → `Services.populate()` |

## 2. Service‑Lebenszyklus

- **`init()`** – andere Services werden **über die Registry / DI** bezogen, nicht über das globale `Services`.
- **`on_ready()`** – hier darf `Services` verwendet werden, weil Phase 6 bereits läuft? **Nein**, laut Spezifikation: Phase 6 füllt erst nach allen `on_ready()`-Aufrufen. Also auch in `on_ready()` nur DI oder EventBus.  
  Die Spezifikation sagt in Phase 5: “Calls `on_ready()` on all services. Use this to connect to the `EventBus`.” – kein Hinweis auf `Services`. Das Autoload ist erst in Phase 6 gefüllt.  
  ⇒ **Weder `init()` noch `on_ready()` dürfen das `Services`‑Autoload benutzen.**  
  ⇒ Sämtliche Abhängigkeiten müssen über Konstruktor-Parameter oder die `ServiceRegistry` übergeben werden.

## 3. Zugriff auf andere Services

- **Während der Boot‑Phasen 4 & 5:**  
  - Jeder Service erhält die `ServiceRegistry` oder gezielt seine deklarierten Abhängigkeiten.  
  - Beispiel: `WorldService` bekommt `save_system` und `data_service` als Parameter von `init(deps: Dictionary)`.  
  - Der `ServiceInitializer` ist dafür verantwortlich, anhand der `deps`-Liste die richtigen Instanzen aus der Registry zu holen und zu übergeben.

- **Nach Phase 6 (Laufzeit):**  
  - `Services.inventory.add_item(...)` – globaler, typisicherer Zugriff.

## 4. EventBus‑Struktur

- Namespaces als separate Klassen (`PlayerEvents`, `WorldEvents`, …).
- Zentrale Instanz im Autoload `EventBus`.
- Neue Signale werden in den entsprechenden Event‑Klassen definiert.

## 5. Daten & Ressourcen

- Alle statischen Werte in `.tres`‑Dateien (`PlayerData`, `QuestDefinition`, …).
- Services validieren in Phase 1 ihre benötigten Daten über `required_data_files`.

## 6. Multiplayer / Permissions (Vorschau)

- Jeder Service muss einen `_auth_provider` erhalten, der prüft, ob eine Aktion server‑authorized ist.
- Methoden trennen in `request_*` (Client) und `execute_*` (Server).

## 7. Entwicklungs-Workflow

1. Events definieren
2. Service‑Klasse erstellen
3. In `BootstrapConfig` registrieren
4. Im `Services`‑Autoload und `populate()` ergänzen
5. `.tres`‑Daten anlegen

## 8. Gegenüberstellung Ist ↔ Soll

| Kriterium | Ist | Soll | Abweichung |
| --- | --- | --- | --- |
| Boot‑Phasen | 1‑6 implementiert | 1‑6 | ✅ |
| init()‑Zugriff | Nutzt `Services.*` | DI / Registry | ❌ Kritisch |
| on_ready()‑Zugriff | Nutzt teilweise `Services.*` | DI / EventBus | ❌ |
| ServiceRegistry | In Factory verwendet | Überall für DI | ⚠️ Teils |
| required_data_files | Vorhanden, aber ungenutzt | Pflicht | ❌ |
| Event‑Klassen | Nicht geliefert | Vorhanden | ❌ |
| Permissions | Nicht implementiert | Vorgesehen | ⏳ |
| Logging | Exzessiv, strukturiert | Gefordert | ✅ |
```

---

### 📄 3. `action_plan.md` – Sofortmaßnahmen & Fehlerbehebung

```markdown
# 🛠️ Fehlerbehebungs- und Umsetzungsplan

## Priorität 1 – Boot‑Fehler beheben (damit das System startet)

### 1.1 Fehlende Basisklassen erstellen
- **BootstrapConfig.gd** anlegen:
  ```gdscript
  class_name BootstrapConfig extends Resource
  @export var services: Array[ServiceDefinition] = []
  ```
- **ServiceDefinition.gd** anlegen:
  ```gdscript
  class_name ServiceDefinition extends Resource
  @export var service_name: String = ""
  @export var path: String = ""
  @export var deps: Array[String] = []
  @export var required_data_files: Array[String] = []
  ```
- Diese beiden Skripte als `res://scripts/core/BootstrapConfig.gd` und `res://scripts/core/ServiceDefinition.gd` speichern.

### 1.2 Fehlende Event‑Klassen (als minimale Platzhalter)
- `PlayerEvents.gd`, `WorldEvents.gd`, `SystemEvents.gd`, `UIEvents.gd`, `QuestEvents.gd`
- Jede Klasse definiert die verwendeten Signale (z.B. `signal xp_gained(...)`, `signal boot_failed(...)`, etc.)

### 1.3 Fehlende Pipeline‑Komponenten
- `ServiceInitializer.gd` – muss `run(ordered, registry)` und `run_on_ready(ordered, registry)` enthalten.  
  In `run()`: für jeden Service-Namen die Instanz holen, deren `deps`-Services aus der Registry besorgen und als Dictionary übergeben, dann `init(deps)` aufrufen.  
  **Wichtig:** `init()` muss so erweitert werden, dass es die Abhängigkeiten als Parameter empfängt.
- `ServiceInstaller.gd` – einfacher Wrapper, der die Registry an `Services.populate()` übergibt.
- `ServiceTeardownManager.gd` – ruft `on_cleanup()` in umgekehrter Reihenfolge auf.
- `ServiceRegistry.gd` – muss `register()`, `get_service()`, `get_all_names()` implementieren.

## Priorität 2 – Lebenszyklus reparieren

### 2.1 Services auf DI umstellen
- **Jede Service‑Klasse** erhält eine `init(deps: Dictionary)`‑Methode (statt parameterlos).
- Entferne **alle** `Services.*`‑Zugriffe aus `init()` und `on_ready()`.
- Beispiel `WorldService`:
  ```gdscript
  func init(deps: Dictionary) -> void:
      var save_sys: SaveSystem = deps.get("savesystem")
      var data_svc: DataService = deps.get("data")
      save_sys.register_save_provider(self)
      var saved := save_sys.get_state_for(SAVE_KEY)
      ...
  ```
- Der `ServiceInitializer` übergibt die aufgelösten Instanzen anhand der `deps`‑Liste.

### 2.2 PlayerStateService & InteractionBuilder
- `InteractionBuilder.init()` benötigt `PlayerStateService`. Also muss `InteractionBuilder` `"playerstates"` in seinen `deps` haben und per DI erhalten.

## Priorität 3 – Fehlende Ressourcen

- `PlayerData.tres` anlegen (von `DataService` erwartet).
- `GameConfig.tres` mit `valid_transitions` (wird von `GameManager` verwendet).
- `ItemDefinition` als Resource-Klasse und einige Beispiel-Items.
- `InteractableAction`-Klasse (wird vom `InteractionBuilder` genutzt).

## Priorität 4 – Test & Validierung

- Nach Erstellung der fehlenden Dateien und DI-Reparatur erneut booten.
- Der `ServiceValidator` wird nun die `required_data_files` prüfen (wenn gepflegt).  
  Empfehlung: mindestens bei `DataService` den Pfad zur `PlayerData.tres` eintragen.
- `Logger` sollte jetzt die Boot‑Phasen vollständig ausgeben.
- `SimpleTerminal` zeigt Logs an, der Befehl `services` listet die registrierten Services auf.

## Priorität 5 – Multiplayer & Permissions (optional)

- `_auth_provider` einführen und in die Service‑Basisklassen integrieren.
- `request_*` / `execute_*`‑Methoden nach Vorbild des `InventoryService`‑Beispiels implementieren.
```

---

### 📦 Zusammenfassung

- **Boot-Fehler:** Sehr wahrscheinlich wegen fehlender Skripte `BootstrapConfig.gd` und `ServiceDefinition.gd`.  
- **Lebenszyklus:** Derzeit brechen fünf Services die Regel, dass `init()` und `on_ready()` nicht auf das erst später befüllte `Services`‑Autoload zugreifen dürfen.  
- **Nächste Schritte:** Die drei oben als Code gezeigten Markdown-Dateien spiegeln detailliert den Ist‑ und Soll‑Zustand wider und liefern eine konkrete Umsetzungsliste.  

Wenn du die fehlenden Dateien erstellst (ich kann dir auf Wunsch auch den kompletten Code für jede dieser Dateien generieren), wird das System booten und der Logger die Phasen im Terminal ausgeben.