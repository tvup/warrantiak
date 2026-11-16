#!/usr/bin/env python3
"""Interactive ASUS warranty lookup via a visible Playwright browser window.

Opens ASUS' own warranty inquiry page with the serial number pre-filled. The
user accepts the privacy terms and clicks Submit themselves; the page then runs
its normal reCAPTCHA flow and the browser requests GetWarranty. This script
never creates or alters that request; it only reads the response.

The page normally navigates to its result page right after the response
arrives, after which the response body is no longer available to Playwright.
That navigation is therefore blocked, so the page stays on the inquiry page.

Usage: warrantiak_asus_browser.py SERIAL URL [--json]

Set _ASUS_DEBUG=1 to print the raw ASUS response and Playwright errors.

Exit codes:
  0  warranty information found
  2  ASUS returned no warranty information (invalid serial, wrong region, ...)
  3  timed out, or the browser window was closed before a result arrived
  4  the browser could not be launched (caller may fall back)
  5  ASUS rejected the lookup (Status FAIL), e.g. reCAPTCHA did not trust the
     automated browser (caller may fall back); nothing is written to stdout
"""

import json
import os
import sys
from datetime import datetime

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import TimeoutError as PlaywrightTimeout
from playwright.sync_api import sync_playwright

WAIT_SECONDS = 5 * 60
DEBUG = bool(os.environ.get("_ASUS_DEBUG"))
# Only useful against the mock server (test/asus_mock --autosubmit): on the
# real ASUS site nobody can click Submit in a headless browser.
HEADLESS = bool(os.environ.get("_ASUS_HEADLESS"))

SN_STATUS_MESSAGES = {
    "NotSN": "Invalid serial number",
    "InNotRegion": "Serial number is not sold in this region",
    "NoService": "No warranty service available for this serial number",
    "NotBeConfirmed": "Warranty status could not be confirmed",
}


def debug(msg):
    if DEBUG:
        print(msg, file=sys.stderr)


def is_warranty_url(url):
    return "service.asmx/GetWarranty" in url and "type=2" in url


def format_date(value):
    """ASUS returns UTC ISO timestamps; like ASUS' page, show the local date."""
    if not value:
        return ""
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value
    return dt.astimezone().strftime("%Y-%m-%d")


def launch(p):
    try:
        return p.chromium.launch(headless=HEADLESS)
    except PlaywrightError as exc:
        debug(f"Bundled Chromium failed: {exc}")
        # Bundled Chromium not installed: try the system Chrome instead.
        return p.chromium.launch(headless=HEADLESS, channel="chrome")


def is_result_page_url(url):
    return "warranty-status-result" in url.lower()


def capture_warranty_response(browser, url):
    """Returns the GetWarranty response body (str) or raises."""
    page = browser.new_page()

    # Keep the page on the inquiry page after a successful lookup, so the
    # response body stays readable. The GetWarranty request itself is sent by
    # the browser and is not touched.
    page.route(lambda u: is_result_page_url(u), lambda route: route.abort("aborted"))

    print("A browser window has opened on the ASUS warranty page.", file=sys.stderr)
    print("Accept the privacy terms and click Submit. Waiting for the result...", file=sys.stderr)
    page.goto(url, wait_until="domcontentloaded")

    # Raises PlaywrightTimeout on timeout and PlaywrightError if the window is
    # closed by the user.
    response = page.wait_for_event(
        "response",
        predicate=lambda r: is_warranty_url(r.url),
        timeout=WAIT_SECONDS * 1000,
    )
    debug(f"GetWarranty: HTTP {response.status} {response.url.split('&gtid=')[0]}")
    return response.text()


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 1

    serial, url = argv[1], argv[2]
    as_json = "--json" in argv[3:]

    with sync_playwright() as p:
        try:
            browser = launch(p)
        except PlaywrightError as exc:
            print(f"Could not launch a browser via Playwright: {exc}".splitlines()[0], file=sys.stderr)
            print("Install Chromium with: python3 -m playwright install chromium", file=sys.stderr)
            return 4

        try:
            body = capture_warranty_response(browser, url)
        except PlaywrightTimeout:
            print("Timed out waiting for the warranty result.", file=sys.stderr)
            return 3
        except PlaywrightError as exc:
            debug(f"Playwright error: {exc}")
            first_line = (str(exc).splitlines() or ["unknown error"])[0]
            print(f"No result received (browser closed or failed): {first_line}", file=sys.stderr)
            return 3
        finally:
            try:
                browser.close()
            except PlaywrightError:
                pass

    try:
        data = json.loads(body)
    except ValueError:
        debug(body[:2000])
        print("ASUS returned a response that was not valid JSON.", file=sys.stderr)
        return 2

    debug(json.dumps(data, indent=2, ensure_ascii=False))

    obj = (data.get("Result") or {}).get("Obj") or {}
    items = obj.get("Items") or []
    mode = (obj.get("SNStatus") or {}).get("Mode")
    # ASUS may flag the serial (e.g. InNotRegion) and still return product and
    # warranty data. Only treat the status as an error when there is no data.
    notice = SN_STATUS_MESSAGES.get(mode, "")

    if data.get("Status") == "FAIL":
        # ASUS' own page shows "serial number is invalid" for this as well, but
        # it is a rejected lookup, not necessarily an invalid serial number.
        print("ASUS rejected the lookup from the automated browser (Status FAIL); "
              "the serial number may still be valid.", file=sys.stderr)
        return 5

    if not items:
        reason = notice or data.get("Message") or "No warranty information found"
        if as_json:
            print(json.dumps({"serial": serial, "status": "error", "error": reason}))
        else:
            print(f"ASUS: {reason} ({serial})", file=sys.stderr)
        return 2

    item = items[0]
    result = {
        "serial": item.get("SerialNO") or serial,
        "model": item.get("Model", ""),
        "series": item.get("Series", ""),
        "warranty_start": format_date(item.get("WarrantyStartDate", "")),
        "warranty_expiration": format_date(item.get("WarrantyDate", "")),
        "warranty_status": item.get("WarrantyStatus", ""),
        "warranty_territory": item.get("WarrantyTerritory", ""),
        "warranty_country": item.get("WarrantyCountry", ""),
    }
    if notice:
        result["notice"] = notice

    if as_json:
        print(json.dumps(result))
    else:
        print("")
        print("===================== ASUS Warranty Info ======================")
        print(f"Model           : {result['model']}")
        print(f"Series          : {result['series']}")
        print(f"Serial Number   : {result['serial']}")
        print(f"Warranty Start  : {result['warranty_start']}")
        print(f"Warranty End    : {result['warranty_expiration']}")
        print(f"Warranty Status : {result['warranty_status']}")
        print(f"Territory       : {result['warranty_territory']} ({result['warranty_country']})")
        if notice:
            print(f"Notice          : {notice}")
        print("===============================================================")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
