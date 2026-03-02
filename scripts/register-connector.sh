#!/usr/bin/env bash
# Register Debezium Postgres connector with Kafka Connect.
# Usage: ./scripts/register-connector.sh
set -e

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-sensor_platform}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"

echo "Registering Debezium Postgres connector against ${CONNECT_URL} (DB ${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB})..."
cat <<EOF2 | curl -sS -X POST "${CONNECT_URL}/connectors" -H 'Content-Type: application/json' -d @- | jq . 2>/dev/null || echo
{
  "name": "sensor-postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "${POSTGRES_HOST}",
    "database.port": "${POSTGRES_PORT}",
    "database.user": "${POSTGRES_USER}",
    "database.password": "${POSTGRES_PASSWORD}",
    "database.dbname": "${POSTGRES_DB}",
    "topic.prefix": "dbserver1",
    "plugin.name": "pgoutput",
    "publication.name": "sensor_cdc",
    "snapshot.mode": "never",
    "schema.include.list": "public",
    "table.include.list": "public.sensors",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter"
  }
}
EOF2
