#!/usr/bin/env python3
"""
Falsk smarthus-backend for simulator-testing i CI.

Hjemme-backend ligger bak en geoblokk, så GitHubs runnere (i USA) når den ikke — og det
SKAL de ikke: å åpne for dem ville punktert geoblokken bare for å ta skjermbilder.
I stedet serverer vi realistiske, faste data her på runneren. Det gir to fordeler:
skjermbildene blir deterministiske, og ingen ekte kameratilgang finnes i CI.

Ekte verifisering skjer på telefonen, innenfra Norge.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8099

# Et 4-ramme «film-stripe»-bilde, som recorderens egne (1x1 grå PNG holder for layout).
STRIPE = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000040000000108020000009d76a5"
    "6d0000001849444154789c636460606060f8cfc0c0c0c0c000006a0009f14b73"
    "0d0000000049454e44ae426082"
)


def tidslinje() -> dict:
    """To kameraer med litt aktivitet — nok til å fylle liste og tidslinje."""
    nå = int(time.time())

    def klipp(start_min_siden: int, lengde: int):
        s = nå - start_min_siden * 60
        return {
            "s": time.strftime("%Y/%m/%d %H:%M:%S", time.localtime(s)),
            "e": time.strftime("%Y/%m/%d %H:%M:%S", time.localtime(s + lengde)),
            "sUnix": s, "eUnix": s + lengde,
        }

    def kamera(navn: str, tider: list[tuple[int, int]]) -> dict:
        return {
            "navn": navn,
            "hendelser": [
                {"type": 131072, "subtype": 2,
                 "intervaller": [klipp(m, l) for m, l in tider]},
                {"type": 131072, "subtype": 1,
                 "intervaller": [klipp(70, 3600)]},
                {"type": 2, "subtype": 2,
                 "intervaller": [klipp(m, 3) for m, _ in tider]},
            ],
        }

    return {"kameraer": [
        kamera("Gate", [(3, 42), (11, 26), (24, 63), (48, 18), (95, 37)]),
        kamera("Inngang", [(7, 31), (19, 54), (36, 22), (77, 45)]),
    ], "kilde": "mock"}


class Handler(BaseHTTPRequestHandler):
    def _send(self, kode: int, kropp: bytes, type_: str) -> None:
        self.send_response(kode)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(kropp)))
        self.end_headers()
        self.wfile.write(kropp)

    def do_GET(self) -> None:
        sti = self.path.split("?")[0]
        if sti == "/api/health":
            self._send(200, b'{"ok":true}', "application/json")
        elif sti == "/api/kamera/tidslinje":
            self._send(200, json.dumps(tidslinje()).encode(), "application/json")
        elif sti.endswith("/bilde"):
            self._send(200, STRIPE, "image/png")
        elif sti.endswith(".m3u8"):
            # Tom, men gyldig spilleliste: nok til at AVPlayer ikke krasjer.
            self._send(200, b"#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-ENDLIST\n",
                       "application/vnd.apple.mpegurl")
        else:
            self._send(404, b'{"error":"ukjent"}', "application/json")

    def log_message(self, *_args) -> None:
        pass  # ikke støy i CI-loggen


if __name__ == "__main__":
    print(f"mock-backend lytter på 127.0.0.1:{PORT}", flush=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
