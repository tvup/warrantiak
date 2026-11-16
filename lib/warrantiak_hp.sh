#!/usr/bin/env bash

# Escapes a value for use inside a JSON string
_hp_json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Uses the locals of _hp_get_warranty_info (bash dynamic scoping)
_hp_json_output() {
    echo "{"
    echo "  \"SerialNumber\": \"$(_hp_json_str "$serial_number")\","
    echo "  \"ProductName\": \"$(_hp_json_str "$product_name")\","
    echo "  \"ProductNumber\": \"$(_hp_json_str "$product_number")\","
    echo "  \"WarrantyStart\": \"$(_hp_json_str "$warranty_start")\","
    echo "  \"WarrantyEnd\": \"$(_hp_json_str "$warranty_end")\","
    echo "  \"WarrantyStatus\": \"$(_hp_json_str "$status")\""
    echo "}"
}

_hp_get_type_info() {
  local serial_number="$1"

  TYPE_INFO=$(curl -s "https://support.hp.com/wcc-services/searchresult/sk-en?q=$serial_number&context=pdp&authState=anonymous&template=WarrantyLanding" \
    -H "Accept: application/json, text/plain, */*" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -H "Accept-Language: en-GB,en;q=0.9" \
    -H "Referer: https://support.hp.com/sk-en/check-warranty" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Site: same-origin" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15" \
    --compressed)

  echo "$TYPE_INFO"
}

_hp_get_warranty_info() {
  local serial_number="$1"
  local product_number="$2"
  local json_output="$3"

  # Construct the JSON payload
  local payload=$(cat <<EOF
{
    "productNumber": "$product_number",
    "serialNumber": "$serial_number",
    "countryCode": "US",
    "authState": "anonymous",
    "languageCode": "en"
}
EOF
)

  # Make the POST request
  local response=$(curl -s -X POST "https://support.hp.com/wcc-services/profile/devices/warranty/specs?authState=anonymous&template=checkWarranty" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/plain, */*" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -H "Accept-Language: en-GB,en;q=0.9" \
    -H "Referer: https://support.hp.com/sk-en/warrantyresult" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15" \
    --compressed \
    -d "$payload")

  # Check if the response contains valid data
  if echo "$response" | grep -q "\"status\":\"OK\""; then
    # Extract fields using grep, sed, and awk
    local warranty_start=$(echo "$response" | grep -o '"warrantyStartDate":"[^"]*"' | sed 's/"warrantyStartDate":"//;s/"//')
    local warranty_end=$(echo "$response" | grep -o '"warrantyEndDate":"[^"]*"' | sed 's/"warrantyEndDate":"//;s/"//')
    local status=$(echo "$response" | grep -o '"status":"[^"]*"' | sed 's/"status":"//;s/"//')
    local product_name=$(echo "$response" | grep -o '"productName":"[^"]*"' | sed 's/"productName":"//;s/"//')

    # Output the JSON
    [[ "$json_output" == "true" ]] && { _hp_json_output; return; }

    # Output the human-readable format
    echo ""
    echo "====================== HP Warranty Info ======================="
    echo "Product Name    : $product_name"
    echo "Serial Number   : $serial_number"
    echo "Product Number  : $product_number"
    echo "Warranty Start  : $warranty_start"
    echo "Warranty End    : $warranty_end"
    echo "Warranty Status : $status"
    echo "==============================================================="
  elif [[ "$json_output" == "true" ]]; then
    echo "{\"SerialNumber\": \"$(_hp_json_str "$serial_number")\", \"error\": \"Failed to retrieve warranty information\"}"
    return 1
  else
    echo "Failed to retrieve warranty information. Response:"
    echo "$response"
  fi
}

