
# 🌍 World Management & Multiplayer Authority Matrix

Dieses Dokument definiert, wer in einer (potenziell vernetzten) Welt die Macht über die Daten hat.

## 1. Das "Server-Authoritative" Modell

In einem sauberen Enterprise-Ansatz für Multiplayer gilt: **Der Server ist die Quelle der Wahrheit.**

| Instanz | Rolle | Verantwortung |
| --- | --- | --- |
| **Server (Host)** | **Authority** | Berechnet Physik, validiert Inventar-Logik, prüft Quest-Fortschritt. |
| **Client (Player)** | **Proxy / Input** | Sendet Eingaben (Tasten), zeigt Vorhersagen (Prediction) und rendert die UI. |

---

## 2. Die logische Zuständigkeit (Who owns what?)

### A. Der `WorldService` (Der Raumverwalter)

* **Logik:** Er weiß, welche Chunks geladen sind und welche Objekte (Interaktions-Punkte, Ressourcen) in der Welt existieren.
* **Multiplayer-Rolle:** Nur der Server entscheidet, wann eine Ressource (z.B. ein Baum) "leer" ist. Er synchronisiert den Status an alle Clients.

### B. Der `PlayerStateService` (Der Identitätsverwalter)

* **Logik:** Verwaltet HP, XP und Position.
* **Permissions:** * **Besitzer (Owner):** Darf seine eigenen Stats *lesen*.
* **Server:** Darf die Stats *schreiben* (ändern).
* **Fremde Spieler:** Sehen nur einen Bruchteil (z.B. nur den Namen und die HP-Bar).



### C. Der `InventoryService` (Der Transaktionsverwalter)

* **Logik:** Das Inventar ist eine reine Datenbank-Operation.
* **Permissions:** Der Client schickt eine `Request_Pickup`-Nachricht. Der Server prüft: "Ist der Spieler nah genug? Ist Platz im Rucksack?" Erst dann wird das Item in der `SaveSystem`-Struktur des Servers hinzugefügt.

---

## 3. Permission Layers (Zugriffsstufen)

Um den Code sauber zu halten, nutzen wir drei Permission-Level:

1. **Public (Read-Only):** Statische Daten aus dem `DataService` (z.B. "Wie viel Schaden macht ein Schwert?") – Jeder darf das wissen.
2. **Protected (Owner-Read/Server-Write):** Dynamische Daten wie "Mein aktuelles Gold". Nur ich und der Server wissen das.
3. **Private (Server-Only):** Sensible Daten wie "Antispam-Timer" oder "Drop-Wahrscheinlichkeiten". Kein Client sollte das je sehen.

---

## 4. Logische Objekt-Verwaltung in der Welt

Wie werden Objekte verwaltet, damit sie Multiplayer-ready sind?

### 1. Das "Global-ID" Prinzip

Jedes Objekt in der Welt (jede Truhe, jeder Busch) braucht eine **UUID** (Unique ID).

* *Warum?* Wenn Spieler A eine Truhe öffnet, muss der Server allen sagen: "Truhe `UUID_123` ist jetzt offen." Ohne ID weiß der Client nicht, welche der 100 Truhen gemeint ist.

### 2. State vs. Visuals

* **State (Service):** Die Information `is_open = true` liegt im `SaveSystem`/`WorldService`.
* **Visuals (Node):** Der `ServiceNode` in der Welt hört auf das Signal und spielt die Animation ab.

---

## 5. Cheat-Prävention (The "Validation" Layer)

Da wir keinen Gott-Modus für Clients wollen, bauen wir in jeden Service einen **Validator** ein:

```gdscript
# Beispiel im InventoryService
func request_item_move(item_id: String, target_slot: int, requester_id: int):
    if not _auth_provider.is_server(): 
        _send_request_to_server("move_item", [item_id, target_slot])
        return

    # SERVER-LOGIK
    if _logic.is_valid_move(requester_id, item_id, target_slot):
        _execute_move(item_id, target_slot)
        _sync_to_clients()

```

---

## Zusammenfassung für dein Design

Wenn du jetzt Services schreibst, frage dich immer:
**"Darf ein manipulierter Client diese Variable einfach ändern?"**

* Wenn **NEIN** -> Die Logik gehört tief in den Service, und der Zugriff erfolgt nur über eine validierte Funktion.
* Wenn **JA** (z.B. Grafik-Einstellungen) -> Das kann lokal im Client bleiben.