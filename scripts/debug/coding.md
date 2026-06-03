

# 🏛️ Enterprise Software Excellence: The 20-Year Horizon

Dieses Dokument definiert die Leitplanken für Software, die darauf ausgelegt ist, Generationen von Entwicklern zu überdauern und technologische Wechsel (Engine-Updates, Plattform-Wechsel) zu überleben.

## 1. Die "Fundamental Truths" (Grundprinzipien)

### A. Separation of Concerns (SoC)

Code darf niemals "zu viel" wissen.

* **Regel:** Ein Service kümmert sich um die *Datenhaltung*, ein anderer um die *Berechnung*, ein dritter um die *Visualisierung*.
* **Enterprise-Benefit:** Wenn du die Grafik-Engine austauschst, bleibt deine gesamte Quest-Logik unberührt.

### B. Dependency Inversion (The Hollywood Principle)

*"Don't call us, we'll call you."*

* **Regel:** High-Level Module (Gameplay) sollten nicht von Low-Level Modulen (Datenbanken, File-IO) abhängen. Beide hängen von Abstraktionen ab.
* **In Godot:** Wir nutzen den `ServiceOrchestrator`, um Abhängigkeiten von oben nach unten zu "injizieren", statt dass Services sich diese selbst kreuz und quer suchen.

### C. Stateless Logic where possible

Zustand (State) ist die Quelle aller Bugs.

* **Regel:** Versuche, Funktionen "pure" zu halten. Gleicher Input = Gleicher Output.
* **Enterprise-Benefit:** Pure Functions sind extrem leicht zu testen (Unit Tests) und verursachen keine Side-Effects in riesigen Code-Basen.

---

## 2. Coding Responsibilities & Standards

### 🛡️ Defensive Programming (Trust No One)

In einem Projekt mit 20 Jahren Laufzeit wird irgendwann jemand (oder du selbst) eine Funktion falsch aufrufen.

* **Validation:** Jede öffentliche Funktion prüft ihre Parameter (`if not data: return`).
* **Fail Fast:** Wenn etwas fundamental schiefgeht (z.B. Boot-Config fehlt), stoppt das System sofort mit einem Error, anstatt mit korrupten Daten weiterzulaufen.

### 📝 Self-Documenting Code vs. Comments

Kommentare lügen oft (weil sie veralten). Der Code muss die Wahrheit sagen.

* **Regel:** `var p_spd_m` ist verboten. Nutze `var player_speed_modifier`.
* **Regel:** Funktionen müssen Verben sein (`calculate_velocity()`, nicht `velocity_logic()`).

### 📦 Explicit over Implicit

Verlasse dich niemals auf "Magic" oder Annahmen.

* **Kein Duck-Typing:** Nutze statische Typisierung (`: String`, `: Service`).
* **Keine impliziten Pfade:** Alle Ressourcen müssen über zentrale Config-Dateien (`.tres`) referenziert werden, niemals als Hardcoded String mitten im Code.

---

## 3. The "Logging as a First-Class Citizen" Rule

In Enterprise-Systemen ist das Log nicht "Zusatz", sondern das **primäre Debugging-Tool**.

* **Audit Trail:** Jede wichtige Entscheidung des Systems muss im Log nachvollziehbar sein.
* **Contextual Data:** Ein Log wie `"Speed changed"` ist nutzlos. Ein Log wie `"Speed updated to 12.0 (Reason: Powerup_Coffee, Base: 6.0)"` ist Gold wert.
* **Categorization:** Nutze Kategorien (`LOG_CAT`), um das Rauschen zu filtern. Im Blind-Coding schalten wir alles stumm, außer dem Bereich, an dem wir gerade arbeiten.

---

## 4. Stability through Lifecycles

Große Systeme scheitern oft am Timing (Race Conditions).

| Phase | Responsibility |
| --- | --- |
| **Creation** | Objekt existiert im Speicher. Keine Logik. |
| **Injection** | Das Objekt erhält seine Werkzeuge (Services). |
| **Warm-up** | Interne Daten werden geladen. |
| **Live** | Das Objekt kommuniziert mit der Außenwelt. |
| **Teardown** | Das Objekt gibt alles sauber zurück. |

---

## 5. Das "Legacy"-Mindset

Schreibe Code immer so, als müsste ihn eine Person warten, die:

1. Deine Architektur-Idee nicht kennt.
2. Keinen Zugriff auf dich hat, um Fragen zu stellen.
3. Ein gewalttätiger Psychopath ist, der weiß, wo du wohnst.

**Fazit:** Einfachheit ist das höchste Maß an Perfektion. Ein komplexes Problem in viele kleine, einfache, entkoppelte Services zu zerlegen, ist die Kunst des Enterprise-Codings.