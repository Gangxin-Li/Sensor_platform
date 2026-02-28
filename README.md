# Sensor Platform

Kubernetes runs on Docker. Create and manage the cluster with one script.

## Script: k8s-create

```bash
./scripts/k8s-create.sh build    # create cluster (kind or minikube)
./scripts/k8s-create.sh rebuild # delete then create again
./scripts/k8s-create.sh pause   # stop cluster (minikube only)
./scripts/k8s-create.sh unpause # start again (minikube only)
./scripts/k8s-create.sh delete  # remove cluster
```

## Project structure

```
Sensor_platform/
├── scripts/
│   └── k8s-create.sh
└── README.md
```
