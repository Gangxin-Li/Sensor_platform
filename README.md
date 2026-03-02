# Sensor Platform

K8s on Docker. ETL: **Producer** → Postgres → **Debezium (CDC)** → **Kafka** → **Consumer (ET)** → **Load** (later). Consumer reads CDC events from a Kafka topic produced by the Debezium PostgreSQL connector.

## How to run

**1. Infra (Postgres + Zookeeper + Kafka + Debezium Connect)**  
One script, one `docker-compose.yml` at project root. Init DB is not auto-loaded; run `./scripts/postgres-run.sh ./db/init_db.sql` once when needed.

```bash
./scripts/postgres-create.sh start    # Start full stack, register CDC connector
./scripts/postgres-create.sh stop      # Stop full stack
./scripts/postgres-create.sh restart   # Stop then start
./scripts/postgres-create.sh delete   # Stop and remove containers and volumes
./scripts/postgres-create.sh register  # Register connector only (stack already up)
```

First time (or after fresh DB): run schema and publication with  
`./scripts/postgres-run.sh ./db/init_db.sql`

**2. Producer (Docker, keeps running)**  
Build and run in background so there are changes to consume:

```bash
./producer/docker.sh build
./producer/docker.sh run
```

Logs: `docker logs -f sensor-platform-producer`  
Stop: `./producer/docker.sh shutdown`

**3. Consumer – read Postgres changes from Kafka**  
Consumes CDC events from the Kafka topic produced by Debezium (Postgres → Kafka). Run in foreground:

```bash
pip install -r consumer/requirements.txt
python consumer/main.py
```

Stop with Ctrl+C. See **consumer/README.md** for how Kafka is used to read Postgres changes.

**4. Optional: K8s cluster (minikube)**  
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
- **CrashLoopBackOff** → Often Postgres unreachable. Ensure the stack is running (`./scripts/postgres-create.sh start`) and that minikube can reach the host (e.g. `host.minikube.internal:5432`). Check logs above for connection errors.

## Scripts

| Script | Purpose |
|--------|--------|
| `./scripts/postgres-create.sh start \| stop \| restart \| delete \| register` | **Infra**: full stack (Postgres + Zookeeper + Kafka + Connect) via root `docker-compose.yml`. register = register CDC connector only. |
| `./scripts/postgres-run.sh <file.sql>` | Run a SQL file on the Postgres DB (e.g. `./db/init_db.sql`). |
| `./scripts/k8s-create.sh build \| rebuild \| pause \| unpause \| delete` | Create/manage the **cluster** (minikube); run once (or after delete). |
| `./scripts/k8s-deploy.sh all \| producer` | **Deploy** apps into the cluster (builds producer image, loads into minikube, then apply). No cluster restart. |

## Project layout

```
Sensor_platform/
├── db/              # init_db.sql (sensors table + publication sensor_cdc); run via postgres-run.sh
├── consumer/        # Consumes Postgres CDC from Kafka topic; see consumer/README.md
├── k8s/             # namespace + deployment-producer
├── producer/        # Producer app + docker.sh; see producer/README.md
├── scripts/         # postgres-create (infra), postgres-run, k8s-create, k8s-deploy
├── docker-compose.yml   # Postgres + Zookeeper + Kafka + Debezium Connect (one network)
└── README.md
```

For details: **consumer/README.md**, **producer/README.md**.
