#!/usr/bin/env bash
# Deploy to K8s from k8s/ manifests. Builds producer image and loads into minikube when deploying producer.
# Usage: $0 all | producer
#   all     - build+load producer image, then apply all in k8s/
#   producer - build+load producer image, then apply namespace + deployment-producer
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

PRODUCER_IMAGE="${PRODUCER_IMAGE:-sensor-platform-producer:latest}"

usage() {
  echo "Usage: $0 <all|producer>"
  echo "  all     - build producer image, load into minikube, deploy all (k8s/)"
  echo "  producer - build producer image, load into minikube, deploy producer only"
  exit 1
}

ensure_producer_image() {
  echo "Building producer image: $PRODUCER_IMAGE"
  docker build -t "$PRODUCER_IMAGE" ./producer
  if command -v minikube &>/dev/null && minikube status &>/dev/null; then
    echo "Loading image into minikube..."
    minikube image load "$PRODUCER_IMAGE"
  else
    echo "Warning: minikube not running or not in PATH; image not loaded. If using minikube, start it and run: minikube image load $PRODUCER_IMAGE"
  fi
}

target="${1:-}"
[[ -z "$target" ]] && usage

case "$target" in
  all)
    ensure_producer_image
    echo "Deploying all (k8s/)..."
    kubectl apply -f k8s/
    ;;
  producer)
    ensure_producer_image
    echo "Deploying producer..."
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/deployment-producer.yaml
    ;;
  *)
    usage
    ;;
esac

echo "Done."
