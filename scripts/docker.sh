#!/usr/bin/env bash
# Docker Compose helpers: build, rebuild, up, down, restart.
# Usage: ./scripts/docker.sh <command> [options]
#   build      Build images
#   rebuild    Down, build --no-cache, (optional) up
#   up         Start all services (-d detached)
#   down       Stop and remove containers (use -v to remove volumes)
#   restart    down + up
#   fresh      down -v, build, up (full reset)
set -e

cd "$(dirname "$0")/.."
COMPOSE="docker compose"
PROFILE=""

usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  build       Build images (no start)"
  echo "  rebuild     Stop, rebuild images with --no-cache, optionally start"
  echo "  up          Start services (add -d for detached)"
  echo "  down        Stop and remove containers (add -v to remove volumes)"
  echo "  restart     down then up -d"
  echo "  fresh       down -v, build, up -d (full reset)"
  echo ""
  echo "Options (after command):"
  echo "  -v          With down: remove volumes"
  echo "  -d          With up: run in background"
  echo "  --monitoring  Use profile 'monitoring' (Prometheus + Grafana)"
  echo ""
  echo "Examples:"
  echo "  $0 build"
  echo "  $0 rebuild"
  echo "  $0 up -d"
  echo "  $0 down -v"
  echo "  $0 fresh"
  echo "  $0 up -d --monitoring"
  exit 1
}

apply_profile() {
  if [ "$PROFILE" = "monitoring" ]; then
    COMPOSE="$COMPOSE --profile monitoring"
  fi
}

cmd_build() {
  apply_profile
  $COMPOSE build "$@"
}

cmd_rebuild() {
  apply_profile
  $COMPOSE down --remove-orphans
  $COMPOSE build --no-cache "$@"
  echo "Rebuild done. Run '$0 up -d' to start."
}

cmd_up() {
  apply_profile
  $COMPOSE up "$@"
}

cmd_down() {
  apply_profile
  $COMPOSE down "$@"
}

cmd_restart() {
  apply_profile
  $COMPOSE down --remove-orphans
  $COMPOSE up -d "$@"
}

cmd_fresh() {
  apply_profile
  echo "Stopping and removing containers and volumes..."
  $COMPOSE down -v --remove-orphans 2>/dev/null || true
  echo "Building..."
  $COMPOSE build
  echo "Starting..."
  $COMPOSE up -d
  echo "Done. Check: docker compose ps"
}

# Parse global options (--monitoring)
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --monitoring) PROFILE=monitoring; shift ;;
    *)            ARGS+=("$1"); shift ;;
  esac
done

[ ${#ARGS[@]} -eq 0 ] && usage
CMD="${ARGS[0]}"
REST=("${ARGS[@]:1}")

case "$CMD" in
  build)   cmd_build "${REST[@]}" ;;
  rebuild) cmd_rebuild "${REST[@]}" ;;
  up)      cmd_up "${REST[@]}" ;;
  down)    cmd_down "${REST[@]}" ;;
  restart) cmd_restart "${REST[@]}" ;;
  fresh)   cmd_fresh ;;
  *)       echo "Unknown command: $CMD"; usage ;;
esac
