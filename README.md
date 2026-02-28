# Sensor Platform

K8s on Docker. ETL: **Producer** → Postgres CDC → (Kafka) → **ET** → **Load** (later).

## How to run

**1. Postgres (Docker)**  
Start DB and apply schema once:

```bash
./scripts/postgres-create.sh start
./scripts/postgres-run.sh ./db/init_db.sql
```

**2. Producer (Docker, keeps running)**  
Build and run in background:

```bash
./producer/docker.sh build
./producer/docker.sh run
```

Logs: `docker logs -f sensor-platform-producer`  
Stop: `./producer/docker.sh shutdown`

**3. Optional: K8s cluster (minikube)**  
Create cluster, then deploy (script builds producer image and loads it into minikube):

```bash
./scripts/k8s-create.sh build
./scripts/k8s-deploy.sh all      # or: ./scripts/k8s-deploy.sh producer
```

**Producer not running in K8s?** Check:

```bash
kubectl get pods -n sensor-platform
kubectl describe pod -n sensor-platform -l app=producer
kubectl logs -n sensor-platform -l app=producer --tail=100
```

- **ImagePullBackOff / ErrImagePull** → Image not in minikube. Run: `./producer/docker.sh build` then `minikube image load sensor-platform-producer:latest`, then `kubectl rollout restart deployment/producer -n sensor-platform`.
- **CrashLoopBackOff** → Often Postgres unreachable. Ensure Postgres is running on your Mac (`./scripts/postgres-create.sh start`) and that it listens on 0.0.0.0 or that minikube can reach the host (e.g. `host.minikube.internal:5432`). Check logs above for connection errors.

## Scripts

| Script | Purpose |
|--------|--------|
| `./scripts/k8s-create.sh build \| rebuild \| pause \| unpause \| delete` | Create/manage the **cluster** (minikube); run once (or after delete). |
| `./scripts/k8s-deploy.sh all \| producer` | **Deploy** apps into the cluster (builds producer image, loads into minikube, then apply). No cluster restart. |
| `./scripts/postgres-create.sh start \| stop \| restart \| delete` | Postgres container. |
| `./scripts/postgres-run.sh <file.sql>` | Run a SQL file on the DB. |

## Project layout

```
Sensor_platform/
├── db/           # init_db.sql (sensors table)
├── et/           # Extract–Transform (placeholder)
├── k8s/          # namespace + deployment-producer
├── producer/     # Producer app + docker.sh; see producer/README.md
├── scripts/      # k8s-create, k8s-deploy, postgres-create, postgres-run
└── README.md
```

For producer details (files, env, run options), see **producer/README.md**.
