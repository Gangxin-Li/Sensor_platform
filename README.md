# Sensor Platform

K8s on Docker. ETL: **Producer** → Postgres → **Debezium (CDC)** → **Kafka** → **Consumer (ET)** → **Load** (later). Consumer reads CDC events from a Kafka topic produced by the Debezium PostgreSQL connector.

## How to run

**1. Infra (Postgres + Zookeeper + Kafka + Debezium Connect)**  
Uses `docker-compose.yml` at project root (project name: `sensor-platform`, network: `sensor-platform_kafka_network`).

**Start the stack (Postgres first, then init_db.sql, then Zookeeper/Kafka/Connect):**
```bash
./scripts/start-stack.sh
```
Then register the Debezium CDC connector (once per stack start if Connect was restarted):
```bash
./scripts/register-connector.sh
```

**Stop / restart / reset the stack:**
```bash
./scripts/stack.sh stop     # Stop compose + local consumer
./scripts/stack.sh start    # Same as start-stack.sh + register-connector.sh
./scripts/stack.sh restart  # stop then start
./scripts/stack.sh reset    # stop + remove volumes (wipes DB/Kafka data); then run start and re-apply load tables
```

**Optional:** run more SQL (e.g. load tables) with  
`./scripts/postgres-run.sh ./db/init_load_table.sql` and `./scripts/postgres-run.sh ./db/init_load_events_table.sql`

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

- **ImagePullBackOff / ErrImagePull** → Image not in minikube. Run: `./producer/docker.sh build` then `minikube image load sensor-platform-producer:latest`, then `kubectl rollout restart deployment/producer -n sensor-platform` (or same for `sensor-platform-consumer:latest` and `deployment/consumer`).
- **CrashLoopBackOff** → Often Postgres/Kafka unreachable. Consumer in K8s uses the same pattern as producer (host.minikube.internal for Kafka:9093 and Postgres:5432). If Kafka refuses from minikube, run the consumer locally: `./consumer/docker.sh run`. After any **Connect restart**, run `./scripts/register-connector.sh` again.

## Scripts

| Script | Purpose |
|--------|--------|
| `./scripts/stack.sh stop \| start \| restart \| reset` | **Stack**: stop/start/restart infra + connector; `reset` = remove volumes (full wipe). |
| `./scripts/start-stack.sh` | **Infra**: Postgres → `db/init_db.sql` → Zookeeper, Kafka, Connect (used by `stack.sh start`). |
| `./scripts/register-connector.sh` | Register Debezium Postgres CDC connector (run after stack is up; optional env: `CONNECT_URL`, `POSTGRES_*`). |
| `./scripts/postgres-run.sh <file.sql>` | Run a SQL file on the Postgres DB (e.g. `./db/init_load_table.sql`). Container: `postgres_db`, DB: `sensor_platform`. |
| `./scripts/k8s-create.sh build \| rebuild \| pause \| unpause \| delete` | Create/manage the **cluster** (minikube); run once (or after delete). |
| `./scripts/k8s-deploy.sh all \| producer \| consumer` | **Deploy** apps (build + load image, apply). Env: producer from `producer/configmap.yaml`, consumer from `consumer/configmap.yaml`; edit those to change params without touching code. |

## Project layout

```
Sensor_platform/
├── db/                  # init_db.sql (sensors + publication); init_load_table.sql; init_load_events_table.sql
├── consumer/            # ETL consumer; docker.sh uses network sensor_platform_kafka_network
├── k8s/                 # namespace + deployment-producer, deployment-consumer (env from each app’s configmap)
├── producer/            # Producer app + docker.sh; see producer/README.md
├── scripts/             # start-stack, register-connector, postgres-run, k8s-create, k8s-deploy
├── docker-compose.yml   # name: sensor-platform; Postgres, Zookeeper, Kafka, Connect
└── README.md
```

For details: **consumer/README.md**, **producer/README.md**.

## Key names and parameters

| Item | Value |
|------|--------|
| **Docker network** | `sensor_platform_kafka_network` (compose explicit name; consumer/producer attach here when running locally) |
| **Postgres container** | `postgres_db` |
| **Postgres DB** | `sensor_platform` |
| **Kafka (host)** | `localhost:9092`; **(minikube)** `host.minikube.internal:9093` (same pattern as producer→Postgres) |
| **Connect** | `http://localhost:8083` |
| **Connector name** | `sensor-postgres-connector`; topic prefix `dbserver1` |
| **K8s namespace** | `sensor-platform` |
| **Producer image** | `sensor-platform-producer:latest` |
| **Consumer image** | `sensor-platform-consumer:latest` |
