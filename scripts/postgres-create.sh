#!/usr/bin/env bash
# Postgres service on Docker: start | stop | restart | delete.
# Uses postgres:16-alpine, DB sensor_platform, wal_level=logical for CDC.
set -e

CONTAINER_NAME="${POSTGRES_CONTAINER:-sensor-platform-postgres}"
IMAGE="postgres:16-alpine"
PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-sensor_platform}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
VOLUME_NAME="${POSTGRES_VOLUME:-sensor-platform-pgdata}"

usage() {
  echo "Usage: $0 <start|stop|restart|delete>"
  echo "  start   - Run Postgres container (create volume if needed)"
  echo "  stop    - Stop the container"
  echo "  restart - Stop then start"
  echo "  delete  - Stop and remove container and volume"
  exit 1
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage

do_start() {
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
      echo "Postgres already running: $CONTAINER_NAME"
      return
    fi
    docker start "$CONTAINER_NAME"
    echo "Started $CONTAINER_NAME"
    return
  fi
  echo "Creating Postgres container: $CONTAINER_NAME (port $PORT)"
  docker run -d \
    --name "$CONTAINER_NAME" \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -p "$PORT:5432" \
    -v "$VOLUME_NAME:/var/lib/postgresql/data" \
    "$IMAGE" \
    postgres -c wal_level=logical -c max_replication_slots=4 -c max_wal_senders=4
  echo "Started $CONTAINER_NAME. Connect: host=localhost port=$PORT db=$DB_NAME user=$DB_USER"
}

do_stop() {
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker stop "$CONTAINER_NAME"
    echo "Stopped $CONTAINER_NAME"
  else
    echo "Container $CONTAINER_NAME is not running."
  fi
}

do_delete() {
  do_stop 2>/dev/null || true
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker rm "$CONTAINER_NAME"
    echo "Removed container $CONTAINER_NAME"
  fi
  if docker volume ls -q | grep -qx "$VOLUME_NAME"; then
    docker volume rm "$VOLUME_NAME"
    echo "Removed volume $VOLUME_NAME"
  fi
  echo "Done. Data in $VOLUME_NAME has been deleted."
}

case "$cmd" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; do_start ;;
  delete)  do_delete ;;
  *)       usage ;;
esac
