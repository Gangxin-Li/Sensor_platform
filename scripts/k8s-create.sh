#!/usr/bin/env bash
# K8s cluster on Docker: build | rebuild | pause | unpause | delete.
# Prefers kind; with minikube: --driver=docker --memory=4096 --cpus=2 (no image-mirror-country; minikube does not support gb)
set -e

MINIKUBE_OPTS="--driver=docker --memory=4096 --cpus=2"

usage() {
  echo "Usage: $0 <build|rebuild|pause|unpause|delete>"
  echo "  build   - Create cluster (kind or minikube)"
  echo "  rebuild - Delete cluster then create again"
  echo "  pause   - Stop cluster (minikube stop; kind has no pause)"
  echo "  unpause - Start cluster again (minikube)"
  echo "  delete  - Remove cluster"
  exit 1
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage

# Prefer kind if available
use_kind() { command -v kind &>/dev/null; }
use_minikube() { command -v minikube &>/dev/null; }

wait_api() {
  echo "Waiting for API server..."
  for i in $(seq 1 30); do
    kubectl cluster-info &>/dev/null && return 0
    sleep 2
  done
  return 1
}

do_build_kind() {
  echo "Creating cluster with kind (K8s in Docker)..."
  kind create cluster
  echo "Done. kubectl cluster-info"
}

do_build_minikube() {
  echo "Creating cluster with minikube (Docker)..."
  minikube start $MINIKUBE_OPTS
  wait_api || { echo "Warning: API not ready after 60s. minikube status"; exit 1; }
  minikube addons enable default-storageclass 2>/dev/null || true
  minikube addons enable storage-provisioner 2>/dev/null || true
  echo "Done. kubectl cluster-info"
}

do_build() {
  if use_kind; then
    do_build_kind
  elif use_minikube; then
    do_build_minikube
  else
    echo "Error: Install kind or minikube (e.g. brew install kind)"
    exit 1
  fi
}

do_rebuild() {
  do_delete
  do_build
}

do_pause() {
  if use_minikube; then
    minikube stop 2>/dev/null || true
    echo "Cluster paused (minikube stopped)."
  elif use_kind && kind get clusters 2>/dev/null | grep -q .; then
    echo "kind has no pause; use: $0 delete"
    exit 1
  else
    echo "No running cluster found."
    exit 1
  fi
}

do_unpause() {
  if use_minikube; then
    minikube start $MINIKUBE_OPTS
    wait_api || true
    echo "Cluster started."
  else
    echo "Only minikube supports unpause. Use: $0 build (for kind)."
    exit 1
  fi
}

do_delete() {
  if use_kind && kind get clusters 2>/dev/null | grep -q .; then
    kind delete cluster
    echo "Kind cluster deleted."
    return
  fi
  if use_minikube; then
    minikube delete 2>/dev/null || true
    echo "Minikube cluster deleted (or was not running)."
    return
  fi
  echo "No cluster tool (kind/minikube) found."
  exit 1
}

case "$cmd" in
  build)   do_build ;;
  rebuild) do_rebuild ;;
  pause)   do_pause ;;
  unpause) do_unpause ;;
  delete)  do_delete ;;
  *)       usage ;;
esac
