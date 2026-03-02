#!/usr/bin/env bash
# Deploy to K8s from k8s/ manifests. Builds images and loads into minikube when deploying.
# Usage: $0 all | producer | consumer
#   all     - build+load producer and consumer images, then apply all in k8s/
#   producer - build+load producer image, apply namespace + deployment-producer
#   consumer - build+load consumer image, apply namespace + deployment-consumer
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

PRODUCER_IMAGE="${PRODUCER_IMAGE:-sensor-platform-producer:latest}"
CONSUMER_IMAGE="${CONSUMER_IMAGE:-sensor-platform-consumer:latest}"

usage() {
  echo "Usage: $0 <all|producer|consumer>"
  echo "  all     - build producer + consumer images, load into minikube, deploy all (k8s/)"
  echo "  producer - build producer image, load into minikube, deploy producer only"
  echo "  consumer - build consumer image, load into minikube, deploy consumer only"
  exit 1
}

load_into_minikube() {
  local image="$1"
  if command -v minikube &>/dev/null && minikube status &>/dev/null; then
    echo "Loading image into minikube: $image"
    minikube image load "$image"
  else
    echo "Warning: minikube not running or not in PATH; image not loaded. If using minikube, start it and run: minikube image load $image"
  fi
}

ensure_producer_image() {
  echo "Building producer image: $PRODUCER_IMAGE"
  docker build -t "$PRODUCER_IMAGE" ./producer
  load_into_minikube "$PRODUCER_IMAGE"
}

ensure_consumer_image() {
  echo "Building consumer image: $CONSUMER_IMAGE"
  docker build -t "$CONSUMER_IMAGE" ./consumer
  load_into_minikube "$CONSUMER_IMAGE"
}

target="${1:-}"
[[ -z "$target" ]] && usage

case "$target" in
  all)
    ensure_producer_image
    ensure_consumer_image
    echo "Deploying all (namespace, configmaps, deployments)..."
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f producer/configmap.yaml
    kubectl apply -f consumer/configmap.yaml
    kubectl apply -f k8s/deployment-producer.yaml
    kubectl apply -f k8s/deployment-consumer.yaml
    ;;
  producer)
    ensure_producer_image
    echo "Deploying producer..."
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f producer/configmap.yaml
    kubectl apply -f k8s/deployment-producer.yaml
    ;;
  consumer)
    ensure_consumer_image
    echo "Deploying consumer..."
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f consumer/configmap.yaml
    kubectl apply -f k8s/deployment-consumer.yaml
    ;;
  *)
    usage
    ;;
esac

echo "Done."
