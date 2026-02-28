#!/usr/bin/env bash
# Run a SQL file against the Postgres container (sensor_platform DB).
# Usage: $0 <file.sql>
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONTAINER_NAME="${POSTGRES_CONTAINER:-sensor-platform-postgres}"
DB_NAME="${POSTGRES_DB:-sensor_platform}"
DB_USER="${POSTGRES_USER:-postgres}"

file="${1:-}"
[[ -z "$file" ]] && { echo "Usage: $0 <file.sql>"; echo "Example: $0 ./db/init_db.sql"; exit 1; }

if [[ ! -f "$file" ]]; then
  [[ -f "$ROOT/$file" ]] && file="$ROOT/$file" || { echo "Error: File not found: $file"; exit 1; }
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "Error: Container $CONTAINER_NAME is not running. Start with: ./scripts/postgres-create.sh start"
  exit 1
fi

echo "Running $file on $DB_NAME..."
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" < "$file"
echo "Done."
