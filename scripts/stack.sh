#!/usr/bin/env bash
# Full stack control: stop | start | restart | reset
# - stop:   docker compose down, stop local consumer container
# - start:  start-stack.sh + register-connector.sh
# - restart: stop then start
# - reset:  stop + remove compose volumes (wipes Postgres/Kafka data), then print next steps
# Run from project root: ./scripts/stack.sh <command>
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
CONSUMER_CONTAINER="${CONSUMER_CONTAINER:-sensor-platform-consumer}"

usage() {
  echo "Usage: $0 <stop|start|restart|reset>"
  echo "  stop    - docker compose down, stop and remove local consumer container"
  echo "  start   - start Postgres → init_db.sql → Zookeeper/Kafka/Connect, then register connector"
  echo "  restart - stop then start"
  echo "  reset   - stop + remove volumes (deletes all DB and topic data). You must run start and re-apply load tables after."
  exit 1
}

do_stop() {
  echo "Stopping stack and local consumer..."
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONSUMER_CONTAINER"; then
    docker stop "$CONSUMER_CONTAINER" 2>/dev/null || true
    docker rm "$CONSUMER_CONTAINER"
    echo "Stopped and removed $CONSUMER_CONTAINER"
  fi
  cd "$PROJECT_DIR"
  docker compose -f "$COMPOSE_FILE" down
  echo "Stack stopped."
}

do_start() {
  echo "Starting stack (Postgres → init_db.sql → Zookeeper, Kafka, Connect)..."
  "$SCRIPT_DIR/start-stack.sh"
  echo "Waiting for Connect to be ready..."
  for i in $(seq 1 30); do
    if curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:8083/connectors 2>/dev/null | grep -q '200\|404'; then
      echo "Connect is ready."
      break
    fi
    [ "$i" -eq 30 ] && { echo "Connect did not become ready in time. Run ./scripts/register-connector.sh later."; return 0; }
    sleep 3
  done
  echo "Registering Debezium connector..."
  "$SCRIPT_DIR/register-connector.sh"
  echo "Stack started. Run consumer locally: ./consumer/docker.sh run"
}

do_reset() {
  echo "Stopping and removing all stack data (volumes)..."
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONSUMER_CONTAINER"; then
    docker stop "$CONSUMER_CONTAINER" 2>/dev/null || true
    docker rm "$CONSUMER_CONTAINER"
  fi
  cd "$PROJECT_DIR"
  docker compose -f "$COMPOSE_FILE" down -v
  echo "Done. All containers and volumes removed."
  echo ""
  echo "Next steps to bring everything back:"
  echo "  1. ./scripts/stack.sh start"
  echo "  2. ./scripts/postgres-run.sh ./db/init_load_table.sql"
  echo "  3. ./scripts/postgres-run.sh ./db/init_load_events_table.sql"
  echo "  4. ./consumer/docker.sh run   # optional, to run consumer"
}

cmd="${1:-}"
case "$cmd" in
  stop)   do_stop ;;
  start)  do_start ;;
  restart) do_stop; do_start ;;
  reset)  do_reset ;;
  *)     usage ;;
esac
