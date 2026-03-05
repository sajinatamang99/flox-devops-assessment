#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL=""
URLS=()
CONFIG_FILE=""

usage() {
    echo "Usage: $0 [--webhook URL] [-f config_file] <url1> [url2] ..."
    echo ""
    echo "Options:"
    echo "  -f FILE        Read URLs from a file (one per line)"
    echo "  --webhook URL  Send Slack notification if any service is unhealthy"
    exit 1
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --webhook)
            WEBHOOK_URL="$2"
            shift 2
            ;;
        -f)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            URLS+=("$1")
            shift
            ;;
    esac
done

if [[ -n "$CONFIG_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        URLS+=("$line")
    done < "$CONFIG_FILE"
fi

if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "Error: No URLs provided"
    usage
fi

TOTAL=${#URLS[@]}
HEALTHY=0
UNHEALTHY_SERVICES=()

echo "[$(timestamp)] Checking $TOTAL services..."

for url in "${URLS[@]}"; do
    HEALTH_URL="${url%/}/health"

    HTTP_CODE=""
    BODY=""

    if RESPONSE=$(curl -sf -w "\n%{http_code}" --max-time 5 "$HEALTH_URL" 2>&1); then
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | sed '$d')
    else
        HTTP_CODE="000"
        BODY="$RESPONSE"
    fi

    if [[ "$HTTP_CODE" == "200" ]] && echo "$BODY" | grep -q '"status".*"healthy"'; then
        VERSION=$(echo "$BODY" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
        echo "[$(timestamp)] OK $HEALTH_URL - HEALTHY (v${VERSION:-unknown})"
        HEALTHY=$((HEALTHY + 1))
    else
        REASON="HTTP $HTTP_CODE"
        if [[ "$HTTP_CODE" == "000" ]]; then
            REASON="Connection refused"
        fi
        echo "[$(timestamp)] FAIL $HEALTH_URL - UNHEALTHY ($REASON)"
        UNHEALTHY_SERVICES+=("$HEALTH_URL")
    fi
done

echo ""
echo "Results: $HEALTHY/$TOTAL services healthy"

if [[ ${#UNHEALTHY_SERVICES[@]} -gt 0 ]]; then
    if [[ -n "$WEBHOOK_URL" ]]; then
        SERVICES_LIST=$(printf '%s\\n' "${UNHEALTHY_SERVICES[@]}")
        PAYLOAD=$(cat <<EOF
{
    "text": "Health check alert: ${#UNHEALTHY_SERVICES[@]}/$TOTAL services unhealthy",
    "blocks": [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Health Check Alert*\n${#UNHEALTHY_SERVICES[@]} of $TOTAL services are unhealthy:\n$SERVICES_LIST"
            }
        }
    ]
}
EOF
        )
        curl -sf -X POST -H 'Content-type: application/json' \
            --data "$PAYLOAD" "$WEBHOOK_URL" >/dev/null 2>&1 || \
            echo "Warning: Failed to send Slack notification"
    fi
    exit 1
fi
