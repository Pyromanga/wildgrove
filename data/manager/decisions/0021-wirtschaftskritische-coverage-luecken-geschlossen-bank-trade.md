# 0021 — Wirtschaftskritische Coverage-Luecken geschlossen (bank/trade/shop/auction_house), method_reference_coverage.py Matcher-Bug gefixt

Zeit: 2026-09-01 08:36 UTC
Rolle: manager

## Gewählt
Als Manager selbst priorisiert: der method_reference_coverage.py-Fund vom letzten Turn zeigte Luecken in echten Geld-/Item-Bewegungslogik (bank 56%, trade 57%, shop 62%, auction_house 67%, equipment 56%, network_bridge 24%). Reihenfolge nach wirtschaftlichem Risiko: bank zuerst (direkte Geld-/Item-Mutation), dann trade (kompletter Verhandlungs-Zustandsautomat), dann shop, dann auction_house. Ergebnis: bank jetzt 16/16 (100%), trade 10/14, shop 6/8, auction_house 9/12 -- die verbleibenden Luecken bei trade/shop/auction_house sind die on_*_confirmed()-Handler, die bereits INDIREKT ueber die request_*()-Wrapper im No-Network-Testpfad vollstaendig durchlaufen werden (bekannte Grenze der Textsuche-Heuristik: .methodname( matcht keine indirekten Aufrufe -- kein echter Test-Gap). Zusaetzlich echten Matcher-Bug in method_reference_coverage.py gefixt: Zusatz-Testdateien wie test_equipment_service_r4.gd wurden uebersehen, weil ihr Header nicht woertlich 'Tests fuer <ClassName>' sagt -- jetzt werden test_<basisname>_*.gd-Geschwisterdateien automatisch mitgenommen.

## Verworfene Alternativen
- network_bridge (24%, groesste Luecke) zuerst angehen -- verworfen, die 41 fehlenden Methoden sind fast ausschliesslich duenne RPC-Sende-Wrapper (send_X()), kein Business-Logik-Risiko wie bei bank/trade -- braucht ausserdem echtes Multiplayer-Setup zum sinnvollen Testen, anderes Kaliber, eigener spaeterer Batch. | Fuer trade/shop/auction_house zusaetzlich direkte on_*_confirmed()-Aufrufe ergaenzen um die Metrik auf 100% zu bringen -- verworfen, das waere reine Metrik-Kosmetik ohne echten Testwert (die Pfade sind bereits ueber request_*() identisch durchlaufen).

## Begründung
Bank/Trade/Shop/Auction-House sind der Kern der Wirtschafts-Simulation -- ungetestete inject_network_bridge()/request_*()-Client-Routing-Pfade haetten bedeutet, dass ein Scam-/Dupe-Bug im Mehrspieler-Pfad durch die Testsuite geschluepft waere, obwohl der Solo-Pfad (No-Network) bereits gut abgedeckt war. Der Matcher-Bug-Fund (test_equipment_service_r4.gd uebersehen) war wichtig VOR dem Schreiben neuer Tests zu pruefen -- sonst waere fuer equipment doppelte Arbeit gegen bereits existierende Abdeckung entstanden, derselbe Fehler wie der stale-WIP-Fund zu Beginn dieses Rounds.
