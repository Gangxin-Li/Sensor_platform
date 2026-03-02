#!/usr/bin/env bash
# Consumer image: build | rebuild | run | shutdown
# Run from repo root or from consumer/: ./consumer/docker.sh build
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
 
IMAGE_NAME="${CONSUMER_IMAGE:-sensor-platform-consumer:latest}"
CONTAINER_NAME="${CONSUMER_CONTAINER:-sensor-platform-consumer}"

usage() {
  echo "Usage: $0 <build|rebuild|run|shutdown>"
  echo "  build    - docker build image $IMAGE_NAME"
  echo "  rebuild  - docker build --no-cache"
  echo "  run      - run container (detached); connect to Kafka in docker-compose network (kafka:29092)"
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
      --network sensor_platform_kafka_network \
      -e KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-kafka:29092}" \
      -e KAFKA_TOPIC="${KAFKA_TOPIC:-dbserver1.public.sensors}" \
      -e KAFKA_GROUP_ID="${KAFKA_GROUP_ID:-sensor-consumer-et}" \
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
