### 📄 Dokument 2: Engineering Principles (Blind-Coding Guide)

Dieses Dokument fasst unsere Design-Philosophie zusammen, damit du auch ohne Godot-Editor stabilen Code schreibst.

# 🧠 Development Principles for Blind-Coding

Da wir ohne die visuelle Unterstützung des Godot-Editors arbeiten, folgen wir diesen strengen Prinzipien, um die Stabilität des Projekts zu garantieren:

### 1. Statische Typsicherheit (The "No-Guessing" Rule)

* **Problem:** GDScript ist normalerweise sehr dynamisch. Ohne Editor merkst du Tippfehler in Variablen erst beim Absturz.
* **Lösung:** Wir nutzen **immer** explizite Typen (`var x: String`) und Type-Casting (`as Node`).
* **Services:** Der `Services`-Container erlaubt uns Autocompletion und verhindert "Null-Pointer", da er beim Boot prüft, ob die Klasse zum Key passt.

### 2. Exzessives Logging (The "Eyes" of the System)

Da wir kein "Live-Debugging" oder "Remote-Inspektor" haben, ist der Logger unsere einzige Informationsquelle.

* **Trace-Prinzip:** Jede wichtige Zustandsänderung (Quest-Start, Item-Grip, Service-Boot) muss ein Log-Event feuern.
* **Struktur:** Jedes Log enthält: `[Zeit] [Level] [Kategorie] Nachricht | DATA: {snapshot}`.
* **Vorteil:** Wenn ein Bug auftritt, können wir den "Flugschreiber" auslesen und sehen exakt, in welcher Phase die Pipeline stecken blieb.

### 3. Entkopplung über den EventBus (Signal-First Design)

* Services rufen sich gegenseitig nur für **Daten** auf (Anfragen).
* Services informieren die Außenwelt über **Signale** (Benachrichtigungen).
* **Warum?** So kann das `InventorySystem` existieren, ohne zu wissen, dass es ein `HUD` gibt. Das macht den Code modular und testbar.

### 4. Daten-getriebenes Design (Resource-First)

* Logik gehört in `.gd` Dateien.
* Werte (Zahlen, Texte, Pfade) gehören in `.tres` Dateien.
* **Warum?** Wir können das Balancing des Spiels (z.B. Spieler-Geschwindigkeit) ändern, indem wir nur eine Textdatei (`PlayerData.tres`) editieren, ohne den Code anpassen zu müssen.

### 5. Lifecycle-Phasen (The Boot-Pipeline)

Wir trennen strikt zwischen:

1. **Instanziierung:** Objekt wird erstellt.
2. **Init:** Referenzen werden gesetzt (Wer bin ich? Wer sind die anderen?).
3. **Ready:** Die Welt ist geladen, jetzt darf kommuniziert werden (Signale verbinden).