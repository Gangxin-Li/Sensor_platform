#!/usr/bin/env bash
# Register Debezium Postgres source connector with Kafka Connect.
# Run from host after: docker compose up -d
# Connect can take 1–2 minutes to be ready; script waits up to 2 minutes.
set -e

cd "$(dirname "$0")/.."
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONFIG="${1:-kafka/connectors/sensor-debezium-source.json}"
MAX_WAIT="${MAX_WAIT:-120}"

echo "Connect URL: $CONNECT_URL"
echo "If this hangs, check: docker compose ps  &&  docker compose logs connect"
echo "Waiting for Connect (up to ${MAX_WAIT}s)..."
elapsed=0
while [ "$elapsed" -lt "$MAX_WAIT" ]; do
  if code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$CONNECT_URL/connectors" 2>/dev/null); then
    if [ "$code" = "200" ]; then
      echo " OK (Connect ready)"
      break
    fi
  fi
  sleep 3
  elapsed=$((elapsed + 3))
  echo -n "."
done

if [ "$elapsed" -ge "$MAX_WAIT" ]; then
  echo ""
  echo "Connect did not become ready in ${MAX_WAIT}s."
  echo "  - Ensure all services are up: docker compose ps"
  echo "  - Check Connect logs: docker compose logs connect"
  echo "  - From another host? Set CONNECT_URL (e.g. http://<host>:8083)"
  exit 1
fi

echo "Registering connector from $CONFIG..."
resp=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" \
  -d @"$CONFIG" \
  "$CONNECT_URL/connectors")
body=$(echo "$resp" | head -n -1)
code=$(echo "$resp" | tail -n 1)
echo "$body" | jq . 2>/dev/null || echo "$body"
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
  echo "HTTP $code (connector may already exist; check: $CONNECT_URL/connectors)"
  exit 1
fi
echo "Done. Status: curl -s $CONNECT_URL/connectors/sensor-debezium-source/status | jq"
