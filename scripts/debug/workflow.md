# 📑 System Meta-Process: Workflow, Debugging & Reporting

Dieses Dokument beschreibt das Protokoll für die Zusammenarbeit. Es stellt sicher, dass die KI immer den vollen Kontext hat und Änderungen nicht zu "Code-Fäulnis" (Code Rot) führen.

## 1. Der "Source of Truth" Workflow

Jede Änderung am Code folgt diesem zyklischen Prozess:

1. **Reporting:** Du postest die aktuellen Logs (Terminal-Output) und markierst, welcher Teil der Architektur gerade betroffen ist.
2. **Context-Request:** Die KI fordert spezifische Dateien an, die laut Log oder Architektur-Plan relevant sind (z.B. "Zeig mir die `Services.gd` und die `BootstrapConfig.tres`").
3. **Cross-Check:** Die KI prüft die Dateien gegen die **Engineering Principles** (Typisierung, Permissions, SoC).
4. **Fix & Update:** Die KI liefert den fixierten Code UND aktualisiert bei Bedarf das betroffene Architektur-Markdown (z.B. wenn ein neuer Service hinzukam).

---

## 2. Struktur des Fehler-Reportings (Das "Blind-Log" Protokoll)

Damit ich dir effektiv helfen kann, sollte ein Report idealerweise so aussehen:

* **Der Error:** Vollständiger Stacktrace aus dem Terminal.
* **Der Status:** Welches Feature wolltest du gerade testen?
* **Die Vermutung:** Was hast du zuletzt geändert?

**KI-Aktion:** Ich werde niemals raten. Wenn ein Typ fehlt, frage ich nach dem entsprechenden File. Wenn ein Pfad falsch ist, prüfen wir die `.tres`.

---

## 3. Meta-Überprüfung der Markdowns

Die Markdown-Files (Architektur, Services, Principles) sind keine statische Doku, sondern **aktiver Teil des Codes**.

* **Synchronität:** Wenn wir in `Services.gd` eine Variable ändern, muss das Markdown `System Services Overview` sofort angepasst werden.
* **Audit:** Einmal pro Session machen wir einen "Health Check":
* Passen die `deps` in der Config noch zur Realität?
* Sind alle Signale im `EventBus` dokumentiert?
* Entsprechen die Dateipfade noch der Struktur?



---

## 4. Multiplayer- & Permission-Check (The Gatekeeper)

Da du Multiplayer im Hinterkopf hast, wird jede neue Funktion einer **Meta-Prüfung** unterzogen:

* **Frage:** Ist das eine `void` Funktion oder ein `Request`?
* **Prüfung:** Werden Daten lokal geändert (Client-Side Prediction) oder warten wir auf das Server-Signal?
* **Validierung:** Gibt es im Service einen Check, der verhindert, dass falsche Daten (z.B. negativer Speed) übernommen werden?

---

## 5. Das "AI-Memory" Protokoll

Da unsere Session-Historie lang wird, nutzen wir "Zusammenfassungen" als Ankerpunkte:

1. **Checkpointing:** Nach jedem gelösten Bug fassen wir den neuen Status Quo kurz zusammen.
2. **File-Indexing:** Wir führen im Kopf (und im Markdown) eine Liste aller `class_name` Definitionen, damit wir keine Namenskollisionen bauen.

---

### Dein nächster Schritt (Action Plan):

Du hast jetzt das gesamte theoretische und prozessuale Fundament. Um das System "live" zu bringen, empfehle ich folgende Reihenfolge für die nächste Session:

dies ist die erste session mach ein ausfuhrliches codereview und erstelle markdown files die das momentane system wiederspiegeln und dss sollsystem wieder spiegeln 