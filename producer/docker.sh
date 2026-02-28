#!/usr/bin/env bash
# Producer image: build | rebuild | run | shutdown
# Run from repo root or from producer/: ./producer/docker.sh build
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="${PRODUCER_IMAGE:-sensor-platform-producer:latest}"
CONTAINER_NAME="${PRODUCER_CONTAINER:-sensor-platform-producer}"

usage() {
  echo "Usage: $0 <build|rebuild|run|shutdown>"
  echo "  build    - docker build image $IMAGE_NAME"
  echo "  rebuild  - docker build --no-cache"
  echo "  run      - run container (detached); connect to Postgres on host via host.docker.internal"
  echo "  shutdown - stop and remove container $CONTAINER_NAME"
  exit 1
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage

case "$cmd" in
  build)
    echo "Building $IMAGE_NAME..."
    docker build -t "$IMAGE_NAME" .
    echo "Done. Run with: $0 run"
    ;;
  rebuild)
    echo "Rebuilding $IMAGE_NAME (no cache)..."
    docker build --no-cache -t "$IMAGE_NAME" .
    echo "Done."
    ;;
  run)
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
      echo "Container $CONTAINER_NAME already exists. Use: $0 shutdown first"
      exit 1
    fi
    echo "Running $CONTAINER_NAME (detached)..."
    docker run -d \
      --name "$CONTAINER_NAME" \
      -e POSTGRES_HOST="${POSTGRES_HOST:-host.docker.internal}" \
      -e POSTGRES_PORT="${POSTGRES_PORT:-5432}" \
      -e POSTGRES_DB="${POSTGRES_DB:-sensor_platform}" \
      -e POSTGRES_USER="${POSTGRES_USER:-postgres}" \
      -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}" \
      "$IMAGE_NAME"
    echo "Done. Logs: docker logs -f $CONTAINER_NAME"
    ;;
  shutdown)
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
      docker stop "$CONTAINER_NAME" 2>/dev/null || true
      docker rm "$CONTAINER_NAME"
      echo "Stopped and removed $CONTAINER_NAME"
    else
      echo "Container $CONTAINER_NAME is not running or does not exist."
    fi
    ;;
  *)
    usage
    ;;
esac
