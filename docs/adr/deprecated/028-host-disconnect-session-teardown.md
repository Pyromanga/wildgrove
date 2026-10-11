> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-028: Kein Host-Migration-Konzept — Autoritätsverlust beendet die Session geordnet

**Status:** Akzeptiert — umgesetzt Round 56
**Datum:** 2026-07
**Kontext:** Schließt den TODO-Punkt "Kein Host-Migration-Konzept. Host disconnected = Session tot." (🟠 Wichtig). Betrifft `GameManager`, `SessionManager`, `ServiceOrchestrator`, `MainMenuController`. Direkte Folgefrage aus ADR-010 (Listen-Server/Dedicated-Server-Dualität): was passiert, wenn die Autorität selbst wegfällt?

---

## Problem

ADR-010 legt fest, wer Autorität ist (Tier 1/2/3), beantwortet aber nicht, was passiert, wenn diese Autorität mitten in einer laufenden Session verschwindet — Host schließt die App, Host-Internet bricht weg, dedizierter Server crasht.

Root-Cause-Recherche vor dieser Runde ergab: **es gab schon einen Teil-Mechanismus, der aber nirgendwo ankam.**

- `SessionManager._on_server_disconnected()` reagiert bereits korrekt auf Godots `multiplayer.server_disconnected` — schließt den Peer, emittiert `EventBus.networking.network_peer_disconnected`.
- `MainMenuController._on_network_peer_disconnected()` hört bereits auf genau dieses Signal und setzt einen Statustext + wechselt eine interne View — aber die `MainMenu`-Szene ist zu diesem Zeitpunkt gar nicht sichtbar, weil `GameManager` sich currently im State `PLAYING`/`LOADING`/`PAUSED` befindet und die `World`-Szene aktiv ist.
- `GameManager` selbst hörte auf `network_peer_disconnected` **gar nicht** — kein State-Wechsel, kein Szenenwechsel, kein Scope-Teardown. Der Client blieb strukturell für immer im State `PLAYING`, mit einem toten `multiplayer.multiplayer_peer`, einer weiterhin aktiven `CharacterScope`/`WorldScope`, die nie durch `ServiceOrchestrator.teardown_all()`/`destroy_character_scope()` abgebaut wurde, und einem Charakter, der sichtbar in einer eingefrorenen Welt steht, ohne jeden Weg zurück außer App-Neustart.

Das ist konkret das, was der TODO-Punkt meint: nicht bloß "keine seamless Migration", sondern ein tatsächlich unbehandelter, hängender Fehlerzustand.

---

## Optionen

### Option A: Echte Host-Migration (Re-Election + State-Handoff)

Ein verbleibender Client wird zum neuen Host, übernimmt die autoritative Weltkopie, alle übrigen Clients bauen ihre `ENetMultiplayerPeer`-Verbindung zum neuen Host neu auf.

Setzt voraus: dass irgendein Client überhaupt eine vollständige, aktuelle Weltkopie hat (nicht der Fall — nur die Autorität selbst hält den maßgeblichen State; Clients sehen nur das, was ihnen repliziert wurde), einen Re-Election-Algorithmus, eine Übergangsphase, in der alle RPCs gepuffert werden müssen, und eine Neuverdrahtung von `SessionManager`/`NetworkBridge` für einen Rollenwechsel zur Laufzeit (heute: Rolle wird einmalig beim Booten festgelegt, nirgendwo im Code für einen Wechsel ausgelegt). Das ist eine grundlegend andere Architektur als ADR-010s "ein Prozess = eine Welt" — kein inkrementeller Fix, sondern ein eigener großer Umbau (vergleichbar mit dem in ADR-010 "Ablösung" beschriebenen Szenario "N Sessions pro Serverprozess").

### Option B: Geordnete Session-Beendigung bei Autoritätsverlust (gewählt)

Kein Versuch, die Session fortzuführen. Client erkennt den Verlust, baut seine eigene `CharacterScope`/`WorldScope` sauber ab (identischer Pfad wie beim regulären "Zurück zum Hauptmenü"), kehrt zum Hauptmenü zurück, zeigt eine klare Statusmeldung.

### Option C: Nichts tun, TODO offen lassen

Verworfen — der aktuelle Zustand ist kein "fehlendes Feature", sondern ein Bug: eine Session, die nach Autoritätsverlust nie wieder verlassen werden kann außer durch App-Neustart, ohne dass der Spieler je erfährt, was passiert ist.

---

## Entscheidung

**Option B.** Kein Host-Migration-Feature — bewusst, nicht aus Zeitmangel: das listen-server-basierte Modell aus ADR-010 hat keine der Voraussetzungen für Option A (keine redundante Weltkopie bei Clients, keine Rollenwechsel-Fähigkeit zur Laufzeit), und die vier Genre-Vorbilder, auf die sich ADR-010 stützt (Valheim, Minecraft, Terraria), haben ebenfalls keine automatische Host-Migration — Sessionende + manuelles Neuverbinden ist dort ebenfalls der Standard.

Umsetzung nutzt ausschließlich bereits vorhandene Mechanik, kein Parallelpfad:

```
SessionManager._on_server_disconnected()          [bereits vorhanden]
  → EventBus.networking.emit_network_peer_disconnected()
      → GameManager._on_host_connection_lost()     [NEU]
          → change_state(MAIN_MENU)
              → ServiceOrchestrator._on_state_changed()   [bereits vorhanden]
                  → destroy_character_scope() (inkl. World-Teardown, SaveSystem.end_session())
                  → emit_session_unloaded()
              → SceneManager.transition_to_state(MAIN_MENU)  [bereits vorhanden]
                  → MainMenuController._on_network_peer_disconnected()  [bereits vorhanden, war
                    vorher totes Signal ohne sichtbare Wirkung — zeigt jetzt tatsächlich den
                    Statustext an, weil die Szene wieder sichtbar ist]
```

Der einzige neue Code ist die eine fehlende Verbindung (`GameManager` hört jetzt auf `network_peer_disconnected` und triggert den State-Wechsel). Alles danach existierte bereits und war korrekt — nur nie erreichbar.

`GameConfig.valid_transitions` erlaubt `MAIN_MENU` bereits von `PLAYING`, `LOADING`, `PAUSED`, `CUTSCENE` und `GAME_OVER` aus — deckt jeden Punkt ab, an dem der Host während einer laufenden Session wegbrechen kann, ohne Änderung an der Transition-Tabelle.

Betrifft ausschließlich Clients: `network_peer_disconnected` entspricht Godots `multiplayer.server_disconnected`, das nur auf Nicht-Autoritäts-Peers feuert. Tier 3 (dedizierter Server) selbst hat keine Menü-Szene, an die er zurückkehren könnte, und ist von diesem Signal nicht betroffen — ein crashender dedizierter Server ist ein Deployment-/Ops-Problem (Neustart durch systemd o.ä.), kein Client-seitiger Zustand.

---

## Konsequenzen

### Positiv
- Der TODO-Punkt "Session tot" ist tatsächlich behoben, nicht nur umbenannt: der Client kommt jetzt zuverlässig in einen sauberen, spielbaren Zustand zurück (neues Spiel starten, erneut verbinden, Solo weiterspielen).
- Kein neuer Teardown-Mechanismus — Wiederverwendung des exakt gleichen Pfads wie beim regulären "Zurück zum Hauptmenü" (`ServiceOrchestrator._on_state_changed()`). Ein Bugfix in diesem Pfad gilt automatisch für beide Fälle.
- `MainMenuController._on_network_peer_disconnected()` war seit seiner Einführung totes Signal ohne sichtbare Wirkung — wird durch diese Änderung erstmals tatsächlich erreichbar, ohne selbst verändert werden zu müssen.

### Negativ / Risiken
- Kein Speichern des Sitzungsfortschritts beim Autoritätsverlust — konsistent mit dem bereits bestehenden Verhalten des regulären "Zurück zum Hauptmenü" (auch dort kein erzwungenes Auto-Save, siehe `GameSaveService`/`save_requested`), aber für einen unerwarteten Abbruch schmerzhafter als für einen bewussten Menüwechsel. Nicht Teil dieser Runde behoben — siehe TODO-Punkt "Save-Konflikt-Handling fehlt", der die Save-Semantik in Multiplayer-Sessions grundsätzlicher klären muss, bevor ein Auto-Save-bei-Disconnect sauber definierbar ist (wessen Save? Der Server hält die Autorität über gemeinsam genutzten Weltzustand — ein Client-seitiger Solo-Save des eigenen Charakterausschnitts wäre ein neuer, ungeprüfter Mechanismus).
- Jeder verbindende Spieler verliert bei Host-Ausfall seinen Fortschritt seit dem letzten Save gleichermaßen — keine Sonderbehandlung "wer war am nächsten dran, Host zu werden".

### Mitigationen
- Keine — das Risiko (kein Auto-Save bei Disconnect) ist identisch mit dem bereits akzeptierten Verhalten des regulären Menü-Exits, keine neue Regression.

---

## Ablösung

Dieses ADR wird abgelöst, falls das Projekt je auf ein Modell umsteigt, in dem Clients redundante Weltkopien halten (z. B. für Offline-Fortsetzung) — an diesem Punkt würde Option A (echte Host-Migration) neu bewertbar.
