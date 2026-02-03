#!/bin/bash
# Cordelia device enrollment -- RFC 8628 device authorization flow.
#
# Usage:
#   cordelia enroll --code ABCD-EFGH [--portal https://portal.seeddrill.ai]
#
# Calls local proxy POST /api/enroll with the user code.
# The proxy handles polling the portal and registering with the Rust node.
#
# Prerequisites:
#   - Cordelia proxy running locally on port 3847 (or CORDELIA_PROXY_URL set)
#   - An active enrollment code from the portal UI

set -euo pipefail

PROXY_URL="${CORDELIA_PROXY_URL:-http://localhost:3847}"
PORTAL_URL="${CORDELIA_PORTAL_URL:-}"
USER_CODE=""

usage() {
    echo "Usage: cordelia enroll --code <USER_CODE> [--portal <PORTAL_URL>]"
    echo ""
    echo "Enroll this device with a Cordelia portal using an enrollment code."
    echo ""
    echo "Options:"
    echo "  --code    The 8-character enrollment code (e.g. ABCD-EFGH)"
    echo "  --portal  Portal URL (default: from proxy env or http://localhost:3001)"
    echo "  --proxy   Proxy URL (default: http://localhost:3847)"
    echo "  --help    Show this help message"
    echo ""
    echo "Example:"
    echo "  cordelia enroll --code ABCD-EFGH"
    echo "  cordelia enroll --code ABCD-EFGH --portal https://portal.seeddrill.ai"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --code)
            USER_CODE="$2"
            shift 2
            ;;
        --portal)
            PORTAL_URL="$2"
            shift 2
            ;;
        --proxy)
            PROXY_URL="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$USER_CODE" ]; then
    echo "Error: --code is required"
    echo ""
    usage
fi

# Validate code format (8 alphanumeric chars, optional dash)
CLEAN_CODE=$(echo "$USER_CODE" | tr -d '-' | tr '[:lower:]' '[:upper:]')
if [ ${#CLEAN_CODE} -ne 8 ]; then
    echo "Error: Invalid code format. Expected 8 characters (e.g. ABCD-EFGH)"
    exit 1
fi
FORMATTED_CODE="${CLEAN_CODE:0:4}-${CLEAN_CODE:4:4}"

echo "Cordelia Device Enrollment"
echo "=========================="
echo "Code:   $FORMATTED_CODE"
echo "Proxy:  $PROXY_URL"
[ -n "$PORTAL_URL" ] && echo "Portal: $PORTAL_URL"
echo ""
echo "Waiting for authorization in the portal..."
echo "(This may take a few minutes. Press Ctrl+C to cancel.)"
echo ""

# Build request body
BODY="{\"user_code\": \"$FORMATTED_CODE\""
if [ -n "$PORTAL_URL" ]; then
    BODY="$BODY, \"portal_url\": \"$PORTAL_URL\""
fi
BODY="$BODY}"

# Call proxy enrollment endpoint
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "${PROXY_URL}/api/enroll" \
    --max-time 960)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESP=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        DEVICE_ID=$(echo "$BODY_RESP" | grep -o '"device_id":"[^"]*"' | cut -d'"' -f4)
        ENTITY_ID=$(echo "$BODY_RESP" | grep -o '"entity_id":"[^"]*"' | cut -d'"' -f4)
        echo "Enrollment successful!"
        echo ""
        echo "  Device ID: $DEVICE_ID"
        echo "  Entity ID: $ENTITY_ID"
        echo ""
        echo "Your device is now registered with the Cordelia network."
        echo "Bearer token stored in ~/.cordelia/portal-token"
        ;;
    403)
        echo "Enrollment denied. The portal administrator rejected this enrollment."
        exit 1
        ;;
    404)
        echo "Invalid enrollment code. Check the code and try again."
        exit 1
        ;;
    408)
        echo "Enrollment timed out. The code may have expired."
        echo "Generate a new code in the portal and try again."
        exit 1
        ;;
    410)
        echo "Enrollment code has expired."
        echo "Generate a new code in the portal and try again."
        exit 1
        ;;
    *)
        echo "Enrollment failed (HTTP $HTTP_CODE):"
        echo "$BODY_RESP"
        exit 1
        ;;
esac
