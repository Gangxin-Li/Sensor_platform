#!/usr/bin/env bash
# 1. Start Postgres only
# 2. Run db/init_db.sql
# 3. Start Zookeeper, Kafka, Connect
# Usage: ./scripts/start-stack.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
CONTAINER_NAME="postgres_db"
DB_NAME="sensor_platform"
DB_USER="postgres"
INIT_SQL="$PROJECT_DIR/db/init_db.sql"

cd "$PROJECT_DIR"

echo "Step 1: Starting Postgres..."
docker compose -f "$COMPOSE_FILE" up -d postgres

echo "Waiting for Postgres to be ready..."
for i in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" 2>/dev/null; then
    echo "Postgres is ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Postgres did not become ready in time."
    exit 1
  fi
  sleep 2
done

echo "Step 2: Running db/init_db.sql..."
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" < "$INIT_SQL"
echo "Init SQL done."

echo "Step 3: Starting Zookeeper, Kafka, Connect..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Done. All services up."
