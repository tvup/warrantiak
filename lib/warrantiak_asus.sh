#!/bin/bash
#
# ASUS warranty check.
#
# ASUS' warranty lookup (support/api/service.asmx/GetWarranty) requires a
# Google reCAPTCHA Enterprise v3 token that can only be produced by a real
# browser on asus.com. We therefore never call the API directly. Instead:
#
#   browser    - open ASUS' own inquiry page in the user's default browser with
#                the serial number pre-filled (?sn=...). The user clicks Submit.
#   playwright - open a visible browser window on ASUS' page via Playwright; the
#                user clicks Submit and the script reads the page's own response.
#   auto       - (default) playwright if the Python module is installed,
#                otherwise browser.
#
# Select the mode with the environment variable _ASUS_MODE.
#
# _ASUS_WEBSITE selects the ASUS country site (e.g. dk, de, uk; default
# global). Devices sold elsewhere may get "not sold in this region" on the
# global site. Not every country has an inquiry page (e.g. it); in that case
# the global page is used.
#
# _ASUS_BASE_URL (default https://www.asus.com) points the check at another
# server, e.g. the local mock in test/asus_mock (see test/asus_mock/README.md).

_ASUS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function _asus_base_url() {
    local base="${_ASUS_BASE_URL:-https://www.asus.com}"
    base="${base%/}"
    if [[ ! "$base" =~ ^https?://[^/[:space:]]+$ ]]; then
        echo "WARNING: invalid _ASUS_BASE_URL '$base'; using https://www.asus.com." >&2
        base="https://www.asus.com"
    fi
    printf '%s' "$base"
}

# Prints the inquiry page URL for $_ASUS_WEBSITE, falling back to global when
# the country site has no such page (ASUS redirects those to /pageerror/).
function _asus_inquiry_url() {
    local base website global_url
    base="$(_asus_base_url)"
    global_url="${base}/global/support/warranty-status-inquiry/"
    website="${_ASUS_WEBSITE:-global}"
    website="${website,,}"

    if [[ ! "$website" =~ ^[a-z]{2,}(-[a-z]+)?$ ]]; then
        echo "WARNING: invalid _ASUS_WEBSITE '$website'; using the global ASUS site." >&2
        printf '%s' "$global_url"
        return
    fi

    local url="${base}/${website}/support/warranty-status-inquiry/"
    if [[ "$website" != "global" ]]; then
        local probe=""
        probe=$(curl -sSL -o /dev/null --max-time 15 \
            -w '%{http_code} %{url_effective}' "$url" 2>/dev/null) || probe=""
        if [[ "$probe" != "200 $url" ]]; then
            echo "NOTE: ASUS '$website' has no warranty inquiry page (or it could not be reached); using the global ASUS site." >&2
            url="$global_url"
        fi
    fi
    printf '%s' "$url"
}

function _asus_urlencode() {
    local s="$1" out="" c i
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '%s' "$out"
}

function _asus_has_playwright() {
    command -v python3 >/dev/null 2>&1 \
        && python3 -c 'import playwright.sync_api' >/dev/null 2>&1
}

function _asus_open_in_browser() {
    local serial="$1" output_json="$2" url="$3"
    local opener=""

    if command -v xdg-open >/dev/null 2>&1; then
        opener="xdg-open"
    elif command -v open >/dev/null 2>&1; then
        opener="open"
    fi

    if [[ -n "$opener" ]]; then
        # Run detached: xdg-open may block until a newly launched browser exits.
        ( "$opener" "$url" >/dev/null 2>&1 & )
    fi

    if [[ "$output_json" == "true" ]]; then
        echo "{\"serial\":\"$serial\",\"status\":\"manual_check_required\",\"url\":\"$url\"}"
    else
        echo ""
        echo "===================== ASUS Warranty Info ======================"
        echo "ASUS requires a browser (reCAPTCHA) to check warranty status."
        if [[ -n "$opener" ]]; then
            echo "The ASUS inquiry page has been opened in your browser with"
            echo "the serial number pre-filled. Accept the privacy terms and"
            echo "click Submit to see the result."
        else
            echo "Open this URL in a browser and click Submit:"
        fi
        echo ""
        echo "  $url"
        if ! _asus_has_playwright; then
            echo ""
            echo "Tip: install Playwright to get the result here in the terminal:"
            echo "  pip install playwright && python3 -m playwright install chromium"
        fi
        echo "==============================================================="
    fi
}

function _asus_get_warranty_info() {
    local serial="$1"
    local output_json="$2"
    local mode="${_ASUS_MODE:-auto}"
    local url
    url="$(_asus_inquiry_url)?sn=$(_asus_urlencode "$serial")"

    if [[ "$mode" == "auto" ]]; then
        if _asus_has_playwright; then mode="playwright"; else mode="browser"; fi
    fi

    case "$mode" in
        browser)
            _asus_open_in_browser "$serial" "$output_json" "$url"
            ;;
        playwright)
            if ! _asus_has_playwright; then
                echo "ERROR: _ASUS_MODE=playwright, but the Python module 'playwright' is not installed." >&2
                echo "Install it with: pip install playwright && python3 -m playwright install chromium" >&2
                return 1
            fi

            local args=("$serial" "$url")
            [[ "$output_json" == "true" ]] && args+=("--json")

            local rc=0
            python3 "$_ASUS_LIB_DIR/warrantiak_asus_browser.py" "${args[@]}" || rc=$?

            # 4: browser could not be launched (e.g. Chromium not installed)
            # 5: ASUS rejected the lookup from the automated browser
            if [[ $rc -eq 4 || $rc -eq 5 ]]; then
                echo "Falling back to your default browser." >&2
                _asus_open_in_browser "$serial" "$output_json" "$url"
                return 0
            fi
            return $rc
            ;;
        *)
            echo "ERROR: unknown _ASUS_MODE '$mode' (use auto, browser or playwright)." >&2
            return 1
            ;;
    esac
}
