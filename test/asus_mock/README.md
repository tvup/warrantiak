# ASUS mock

A local stand-in for ASUS' warranty inquiry page and its `GetWarranty` API, so
the ASUS check can be developed and tested without asus.com and reCAPTCHA.

## Fixtures

`GetWarranty?type=2&sn=<SN>` returns `fixtures/<SN>.json` verbatim (serial
upper-cased). Serials without a fixture get `fixtures/_default.json`.

| Fixture | Source | Tests |
|---|---|---|
| `84OAAQ047369.json` | real ASUS response (website=uk) | normal result with data |
| `MOCKNOTINREGION.json` | synthetic | `InNotRegion` together with data |
| `MOCKFAIL.json` | real ASUS response shape | `Status: FAIL` (rejected lookup) |
| `_default.json` | synthetic | `NotSN`, no data (invalid serial) |

Add a case by dropping a new `<SERIAL>.json` in `fixtures/`; the server reads
fixtures on every request, so no restart is needed.

The country site `it` redirects to `/it/pageerror/` (404), like on asus.com.

## Running warrantiak against the mock

Start the mock (port 18765 by default):

```bash
make mock-asus                 # or: python3 test/asus_mock/server.py --port 18765
```

In another terminal, point warrantiak at it with `--asus-base-url` (or
`_ASUS_BASE_URL`):

```bash
./warrantiak -A -s 84OAAQ047369 --asus-website uk --asus-base-url http://127.0.0.1:18765
```

The mock page works like ASUS' page: accept the privacy terms and click
*Submit*. With `--autosubmit` the page does that by itself, and with
`_ASUS_HEADLESS=1` the Playwright browser runs without a window; both are
meant for automated tests only.

## Automated tests

```bash
make test                      # or: bash test/test_asus.sh
```

Starts the mock with `--autosubmit`, runs `warrantiak -A -j` in browser and
Playwright mode (headless) and checks the JSON output. Browser openers are
replaced by fakes, so no real browser opens. Playwright tests are skipped when
`python3` cannot import `playwright` (activate the virtualenv first).
