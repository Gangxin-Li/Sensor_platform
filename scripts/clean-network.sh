#!/usr/bin/env bash
# Stop all containers on sensor_platform network, then bring compose down cleanly.
set -e
cd "$(dirname "$0")/.."

echo "Stopping and removing sensor_platform containers..."
docker compose down --remove-orphans

echo "Checking for containers still on sensor_platform_default..."
CONTAINERS=$(docker network inspect sensor_platform_default --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)
if [ -n "$CONTAINERS" ]; then
  for c in $CONTAINERS; do
    echo "Stopping $c"
    docker stop "$c" 2>/dev/null || true
    docker rm -f "$c" 2>/dev/null || true
  done
fi

echo "Bringing down compose again (with -v to remove volumes if desired)..."
docker compose down -v --remove-orphans 2>/dev/null || docker compose down --remove-orphans

echo "Done. If the network still exists and you want to remove it:"
echo "  docker network rm sensor_platform_default"
