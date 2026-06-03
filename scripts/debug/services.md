### 📄 Dokument 1: Service Registry & Responsibilities

Dieses Dokument dient als Übersicht, welcher Service wofür zuständig ist und welche Abhängigkeiten bestehen.

# 🛠️ System Services Overview

| Service | Typ | Beschreibung | Abhängigkeiten |
| --- | --- | --- | --- |
| **`DataService`** | `Service` | Lädt und verwaltet alle statischen `.tres` Ressourcen (Items, Quests, NPCs). | Keine |
| **`SaveSystem`** | `Service` | Serialisiert dynamische Daten in JSON/Binär und verwaltet Savegames. | Keine |
| **`PlayerStateService`** | `Service` | Hält Laufzeitdaten des Spielers (aktuelle HP, Position, aktive Buffs). | `SaveSystem` |
| **`InventorySystem`** | `Service` | Logik für das Hinzufügen, Entfernen und Benutzen von Items. | `DataService`, `SaveSystem` |
| **`SkillSystem`** | `Service` | Berechnet XP-Kurven und verwaltet die Level der verschiedenen Skills. | `DataService` |
| **`QuestService`** | `Service` | Trackt Quest-Fortschritte, Objectives und schaltet Belohnungen frei. | `DataService`, `SaveSystem` |
| **`WorldService`** | `ServiceNode` | Verwaltet Zeit-Zyklen, Wetter oder das Spawnen von Objekten in der Welt. | `SaveSystem`, `DataService` |
| **`HUDManager`** | `ServiceNode` | Zentrale Steuerung der UI-Elemente (HP-Bar, Quest-Anzeige). | `InventorySystem`, `PlayerStateService` |
| **`Factory3D`** | `Service` | Instanziiert Spielobjekte in der Welt basierend auf Daten-IDs. | `DataService` |
| **`InteractionBuilder`** | `Service` | Dynamische Erstellung von Interaktions-Optionen (z.B. "Ernten", "Reden"). | Keine |