#!/usr/bin/env python3
"""Local mock of the ASUS warranty inquiry page and GetWarranty API.

Serves:
  /<website>/support/warranty-status-inquiry/   inquiry page (?sn= pre-fills)
  /<website>/support/Warranty-Status-Result     result page
  /support/api/service.asmx/GetWarranty         API, answered from fixtures/

GetWarranty?type=2&sn=<SN> returns fixtures/<SN>.json (serial upper-cased),
or fixtures/_default.json when there is no fixture for the serial.

Websites listed in MISSING_WEBSITES redirect to /<website>/pageerror/ (404),
like ASUS does for countries without an inquiry page (e.g. it).

Usage: server.py [--port 18765] [--autosubmit]

--autosubmit makes the inquiry page accept the privacy terms and click Submit
by itself, for automated tests in a headless browser.
"""

import argparse
import http.server
import json
import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"
MISSING_WEBSITES = {"it"}
WEBSITE_RE = r"([a-z]{2,}(?:-[a-z]+)?)"


def log(msg):
    print(f"[asus-mock] {msg}", file=sys.stderr, flush=True)


def load_fixture(serial):
    path = FIXTURES / f"{serial.upper()}.json"
    if not re.fullmatch(r"[A-Za-z0-9_-]+", serial) or not path.is_file():
        path = FIXTURES / "_default.json"
    return path


class Handler(http.server.BaseHTTPRequestHandler):
    autosubmit = False

    def send(self, status, body, content_type="text/html; charset=utf-8", headers=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        path, query = url.path, parse_qs(url.query)

        if path == "/support/api/service.asmx/GetWarranty":
            return self.get_warranty(query)

        m = re.fullmatch(rf"/{WEBSITE_RE}/support/warranty-status-inquiry/?", path)
        if m:
            website = m.group(1)
            if website in MISSING_WEBSITES:
                return self.send(302, "", headers={"Location": f"/{website}/pageerror/"})
            page = (HERE / "inquiry.html").read_text(encoding="utf-8")
            page = page.replace("__WEBSITE__", website)
            page = page.replace("__AUTOSUBMIT__", "true" if self.autosubmit else "false")
            return self.send(200, page)

        m = re.fullmatch(rf"/{WEBSITE_RE}/support/warranty-status-result/?", path, re.IGNORECASE)
        if m:
            return self.send(200, (HERE / "result.html").read_text(encoding="utf-8"))

        if re.fullmatch(rf"/{WEBSITE_RE}/pageerror/?", path):
            return self.send(404, "<h1>Page not found (mock)</h1>")

        return self.send(404, "<h1>Not found (mock)</h1>")

    def get_warranty(self, query):
        req_type = (query.get("type") or [""])[0]
        serial = (query.get("sn") or [""])[0]
        website = (query.get("website") or [""])[0]

        if req_type != "2":
            # type=1: the page asks for its side-menu links on load
            body = {"Result": {"Obj": {"Type": req_type, "SubGroup": []}},
                    "Status": "SUCCESS", "Message": "SUCCESS"}
            return self.send(200, json.dumps(body), "application/json; charset=utf-8")

        fixture = load_fixture(serial)
        log(f"GetWarranty website={website} sn={serial} -> fixtures/{fixture.name} "
            f"(sec-fetch-mode={self.headers.get('sec-fetch-mode')})")
        return self.send(200, fixture.read_bytes(), "application/json; charset=utf-8")

    def log_message(self, fmt, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--autosubmit", action="store_true")
    args = parser.parse_args()

    Handler.autosubmit = args.autosubmit
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    log(f"listening on http://127.0.0.1:{args.port} (autosubmit={args.autosubmit})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
