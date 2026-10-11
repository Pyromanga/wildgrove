#!/usr/bin/env python3
"""udp_latency_proxy.py — CI-only bidirektionales UDP-Relay mit künstlicher
Latenz/Jitter/Paketverlust.

Wozu: `tests/integration/test_movement_two_peer.gd` (IT-01/IT-02) und der
Zwei-Prozess-Job "IT-03 — Two-Process Movement Round Trip" (build-apk.yml,
scripts/testing/IT03Harness.gd) laufen beide über 127.0.0.1-Loopback — dort
sind Pakete quasi verzögerungsfrei und gehen praktisch nie verloren. Echtes
Internet/WLAN/Mobilfunk ist das nicht. Dieses Skript sitzt zwischen Host- und
Client-Prozess und simuliert genau diese Bedingungen, ohne dass die
GDScript-Seite (IT03Harness.gd, NetworkBridge, ENet) irgendetwas davon weiß —
aus deren Sicht ist es einfach ein Netzwerk mit echter Latenz.

Topologie:
    Client-Prozess  --(UDP)-->  [dieses Skript, --listen-port]
                                        |  (Delay/Jitter/Loss)
                                        v
                    [dieses Skript, sendet an --target-host:--target-port]  -->  Host-Prozess

    Antworten des Hosts laufen exakt denselben Weg zurück (ebenfalls mit
    Delay/Jitter/Loss, per Default demselben Profil — echte Netzwerke sind
    selten perfekt symmetrisch, aber für einen CI-Rauchtest reicht ein
    symmetrisches Profil; siehe --down-* für ein optional abweichendes
    Rückkanal-Profil).

Nur für EINEN Client ausgelegt (IT-03 hat exakt einen) — die Client-Adresse
wird beim ersten empfangenen Paket gelernt und danach für den Rückweg
verwendet. Für mehrere gleichzeitige Clients bräuchte es eine
Adress-zu-Adress-Tabelle statt einer einzelnen `_client_addr`-Variable.

Nutzt nur die Python-Standardbibliothek (asyncio) — kein Extra-Dependency-
Install im CI-Runner nötig.

Beispiel:
    python3 udp_latency_proxy.py \\
        --listen-port 38215 --target-host 127.0.0.1 --target-port 38214 \\
        --delay-ms 80 --jitter-ms 20 --loss-pct 2
"""

import argparse
import asyncio
import random
import sys
import time


def _log(msg: str) -> None:
    # Ungepuffert genug für CI-Logs — ein Skript, kein Service, kein
    # Logging-Framework nötig.
    print(f"[udp_latency_proxy] {time.strftime('%H:%M:%S')} {msg}", flush=True)


class _RelayProtocol(asyncio.DatagramProtocol):
    """Eine Instanz pro Richtung. `forward_addr` ist entweder die feste
    Ziel-Adresse (Client → Host) oder None (Host → Client, Ziel wird erst
    beim ersten Client-Paket bekannt — siehe `client_addr_box`)."""

    def __init__(
        self,
        label: str,
        loop: asyncio.AbstractEventLoop,
        delay_ms: float,
        jitter_ms: float,
        loss_pct: float,
        client_addr_box: dict,
        is_client_facing: bool,
        fixed_target: tuple | None,
    ) -> None:
        self.label = label
        self.loop = loop
        self.delay_ms = delay_ms
        self.jitter_ms = jitter_ms
        self.loss_pct = loss_pct
        self.client_addr_box = client_addr_box
        self.is_client_facing = is_client_facing
        self.fixed_target = fixed_target
        self.transport: asyncio.DatagramTransport | None = None
        self.peer_transport: asyncio.DatagramTransport | None = None
        self.packets_forwarded = 0
        self.packets_dropped = 0

    def connection_made(self, transport: asyncio.DatagramTransport) -> None:
        self.transport = transport

    def datagram_received(self, data: bytes, addr) -> None:
        if self.is_client_facing:
            if self.client_addr_box.get("addr") != addr:
                _log(f"Client-Adresse gelernt: {addr}")
                self.client_addr_box["addr"] = addr

        if self.loss_pct > 0 and random.random() * 100.0 < self.loss_pct:
            self.packets_dropped += 1
            return  # Stiller Drop — genau das simuliert echten Paketverlust.

        target = self.fixed_target if self.fixed_target else self.client_addr_box.get("addr")
        if target is None:
            # Host antwortet, bevor der Client je ein Paket geschickt hat —
            # kann strukturell nicht passieren (Client verbindet zuerst),
            # aber kein Grund für eine Exception, falls doch.
            return

        delay_sec = max(0.0, (self.delay_ms + random.uniform(-self.jitter_ms, self.jitter_ms)) / 1000.0)
        self.loop.call_later(delay_sec, self._forward, data, target)

    def _forward(self, data: bytes, target) -> None:
        if self.peer_transport is None:
            return
        self.peer_transport.sendto(data, target)
        self.packets_forwarded += 1

    def error_received(self, exc: Exception) -> None:
        _log(f"{self.label}: Socket-Fehler: {exc}")


async def _run(args: argparse.Namespace) -> None:
    loop = asyncio.get_running_loop()
    client_addr_box: dict = {"addr": None}

    # up = Client → Host, down = Host → Client. Getrennte Profile möglich
    # (--down-delay-ms etc.), Default: identisch zum Up-Profil.
    down_delay = args.down_delay_ms if args.down_delay_ms is not None else args.delay_ms
    down_jitter = args.down_jitter_ms if args.down_jitter_ms is not None else args.jitter_ms
    down_loss = args.down_loss_pct if args.down_loss_pct is not None else args.loss_pct

    client_facing_transport, client_facing_proto = await loop.create_datagram_endpoint(
        lambda: _RelayProtocol(
            "up (client→host)", loop, args.delay_ms, args.jitter_ms, args.loss_pct,
            client_addr_box, is_client_facing=True,
            fixed_target=(args.target_host, args.target_port),
        ),
        local_addr=("0.0.0.0", args.listen_port),
    )
    host_facing_transport, host_facing_proto = await loop.create_datagram_endpoint(
        lambda: _RelayProtocol(
            "down (host→client)", loop, down_delay, down_jitter, down_loss,
            client_addr_box, is_client_facing=False,
            fixed_target=None,
        ),
        local_addr=("0.0.0.0", 0),  # beliebiger freier Port, nur zum Senden an den Host
    )

    # Jede Seite muss die andere kennen, um weiterzuleiten.
    client_facing_proto.peer_transport = host_facing_transport
    host_facing_proto.peer_transport = client_facing_transport

    _log(
        f"bereit — Client verbindet sich mit Port {args.listen_port}, "
        f"relayt nach {args.target_host}:{args.target_port}. "
        f"Up: {args.delay_ms}ms±{args.jitter_ms}ms, {args.loss_pct}% Loss. "
        f"Down: {down_delay}ms±{down_jitter}ms, {down_loss}% Loss."
    )

    try:
        await asyncio.sleep(args.max_lifetime_sec)
        _log(f"max_lifetime_sec ({args.max_lifetime_sec}s) erreicht — beende.")
    finally:
        _log(
            f"Statistik up: {client_facing_proto.packets_forwarded} weitergeleitet, "
            f"{client_facing_proto.packets_dropped} verworfen (simulierter Loss)."
        )
        _log(
            f"Statistik down: {host_facing_proto.packets_forwarded} weitergeleitet, "
            f"{host_facing_proto.packets_dropped} verworfen (simulierter Loss)."
        )
        client_facing_transport.close()
        host_facing_transport.close()


def _parse_args(argv: list) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--listen-port", type=int, required=True, help="Port, auf dem der Client sich verbindet.")
    p.add_argument("--target-host", type=str, default="127.0.0.1", help="Echter Host-Prozess.")
    p.add_argument("--target-port", type=int, required=True, help="Echter Host-Port.")
    p.add_argument("--delay-ms", type=float, default=0.0, help="Basis-Latenz Client→Host, in ms (einfacher Weg).")
    p.add_argument("--jitter-ms", type=float, default=0.0, help="Zufällige Abweichung ± um --delay-ms.")
    p.add_argument("--loss-pct", type=float, default=0.0, help="Wahrscheinlichkeit in %% pro Paket, Client→Host.")
    p.add_argument("--down-delay-ms", type=float, default=None, help="Abweichendes Profil Host→Client (Default: wie --delay-ms).")
    p.add_argument("--down-jitter-ms", type=float, default=None, help="Siehe --down-delay-ms.")
    p.add_argument("--down-loss-pct", type=float, default=None, help="Siehe --down-delay-ms.")
    p.add_argument("--max-lifetime-sec", type=float, default=300.0, help="Fallback-Selbstabschaltung (Defense in Depth, wie IT03Harness).")
    return p.parse_args(argv)


def main() -> None:
    args = _parse_args(sys.argv[1:])
    try:
        asyncio.run(_run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
