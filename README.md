# Sensor Platform

AI predictive monitoring for critical infrastructure: sensor telemetry pipeline with **CDC over Kafka**.

**Data flow:** `sensor_raw` (100 rows in Postgres) → logical replication → **Debezium** → **Kafka** → **ETL** (stream consumer) → Inference.

## Structure

```
sensor-platform/
├── db/                 # Init DB: sensor_raw (100 rows), publication for logical replication
├── producer/           # Fills sensor_raw once (100 rows), then only UPDATEs (CDC events)
├── kafka/              # Debezium connector config (Postgres → Kafka)
├── etl/                # Kafka stream consumer: CDC → features → inference
├── inference/          # Mock AI inference (FastAPI)
├── monitoring/         # OTel, Prometheus, Grafana
├── k8s/                # Kubernetes manifests
├── scripts/            # docker.sh, register-debezium.sh
└── docker-compose.yml
```

## Local run

```bash
# 1. Build and start (DB, Zookeeper, Kafka, Connect, Producer, ETL, Inference)
docker compose build
docker compose up -d

# 2. Register Debezium connector (one-time; Connect may take 1–2 min to start)
chmod +x scripts/register-debezium.sh
./scripts/register-debezium.sh

# If the script keeps "waiting for Connect at localhost:8083":
#   docker compose ps          # ensure connect is running
#   docker compose logs connect   # see why it might be slow or failing
#   Then run the script again (it waits up to 2 min).

# Optional: with Prometheus + Grafana
docker compose --profile monitoring up -d
```

**Helper script** (build / rebuild / down / up / fresh):

```bash
chmod +x scripts/docker.sh
./scripts/docker.sh build          # build images
./scripts/docker.sh rebuild       # down + build --no-cache
./scripts/docker.sh up -d         # start in background
./scripts/docker.sh down           # stop and remove
./scripts/docker.sh down -v        # stop and remove volumes
./scripts/docker.sh restart       # down + up -d
./scripts/docker.sh fresh          # down -v, build, up -d (full reset)
./scripts/docker.sh up -d --monitoring   # start with Prometheus + Grafana
```

- **PostgreSQL**: `localhost:5432`, database `sensor_db`, user/password `postgres/postgres`
- **Inference API**: http://localhost:8000, health http://localhost:8000/health

## Querying the database

**Connection (from your machine):**

| Field      | Value        |
|------------|--------------|
| Host       | `localhost`  |
| Port       | `5432`       |
| Database   | `sensor_db`  |
| User       | `postgres`   |
| Password   | `postgres`   |

**Option 1 — `psql` on your machine** (if PostgreSQL client is installed):

```bash
psql postgresql://postgres:postgres@localhost:5432/sensor_db
```

**Option 2 — `psql` via Docker** (no local Postgres needed):

```bash
docker compose exec db psql -U postgres -d sensor_db
```

Then run SQL, for example:

```sql
-- Exactly 100 rows (one per sensor)
SELECT COUNT(*) FROM sensor_raw;

-- Latest state per sensor
SELECT sensor_id, vibration_x, vibration_y, vibration_z, ambient_temp, battery_voltage, updated_at
FROM sensor_raw ORDER BY updated_at DESC LIMIT 10;
```

**Option 3 — GUI client** (standalone desktop apps; install separately): [DBeaver](https://dbeaver.io/) (free), [pgAdmin](https://www.pgadmin.org/) (free), [TablePlus](https://tableplus.com/), [DataGrip](https://www.jetbrains.com/datagrip/) (JetBrains). Create a PostgreSQL connection with the values above.

## Viewing run status

After `docker compose up -d`:

| What to check | How |
|---------------|-----|
| **Containers** | `docker compose ps` — see if db, producer, etl, inference, otel-collector are running |
| **Logs** | `docker compose logs -f producer` or `etl` or `inference` — follow live output |
| **Inference health** | Open http://localhost:8000/health or `curl http://localhost:8000/health` |
| **Inference API docs** | http://localhost:8000/docs — Swagger UI to call `POST /features` |
| **Database** | `psql postgresql://postgres:postgres@localhost:5432/sensor_db` → `SELECT COUNT(*) FROM sensor_raw;` (should be 100) |
| **Kafka Connect** | http://localhost:8083/connectors — register Debezium via `./scripts/register-debezium.sh` |
| **Prometheus** (optional) | Start with `docker compose --profile monitoring up -d`, then http://localhost:9090 |
| **Grafana dashboard** (optional) | Same profile; open http://localhost:3000 — login `admin` / `admin`, then open the **Sensor Platform** dashboard |

With the `monitoring` profile you get **Grafana** at http://localhost:3000 (admin/admin) and a pre-loaded **Sensor Platform** dashboard showing Prometheus scrape targets (e.g. Prometheus, OTel Collector).

Quick checks:

```bash
# Container status
docker compose ps

# Live logs (one service)
docker compose logs -f inference
docker compose logs -f etl
docker compose logs -f producer

# Health
curl http://localhost:8000/health

# Row count (should be 100)
psql postgresql://postgres:postgres@localhost:5432/sensor_db -c "SELECT COUNT(*) FROM sensor_raw;"
```

## Reset / delete all data and re-run

To wipe all data and start from a clean state:

**Option A — Reset sensor_raw (keep schema):** truncate and let producer re-insert 100 rows:

```bash
docker compose exec db psql -U postgres -d sensor_db -c "TRUNCATE sensor_raw CASCADE;"
docker compose restart producer
```

**Option B — Remove DB volume and restart everything (full reset):**

```bash
docker compose down -v
docker compose build
docker compose up -d
```

`-v` removes named volumes (e.g. Postgres data). On next `up`, the DB will run `init_db.sql` again and the producer will repopulate `sensor_raw`.

**If `docker compose down -v` fails with “network has active endpoints”:** some containers are still attached. Stop and remove them, then retry:

```bash
# From repo root: stop all project containers, then down with volumes
docker compose stop
docker compose down --remove-orphans
docker compose down -v --remove-orphans

# If it still fails, force-remove any container still on the network:
docker ps -a --filter network=sensor_platform_default -q | xargs docker rm -f
docker compose down -v --remove-orphans
```

## K8s deployment

```bash
# After building and pushing images to a registry reachable by the cluster
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap-db-init.yaml
kubectl apply -f k8s/deployment-db.yaml
kubectl apply -f k8s/deployment-otel-collector.yaml
kubectl apply -f k8s/deployment-inference.yaml
kubectl apply -f k8s/deployment-producer.yaml
kubectl apply -f k8s/deployment-etl.yaml
```

Pods communicate via K8s Services (`db`, `inference`, `otel-collector`). For the CDC pipeline you also need **Kafka** and **Kafka Connect (Debezium)** in the cluster; deploy them (e.g. Strimzi or Confluent operator) and register the connector from `kafka/connectors/sensor-debezium-source.json`.

## Data flow (CDC)

1. **sensor_raw** (Postgres): exactly 100 rows, one per sensor. **Producer** inserts 100 rows once, then only **UPDATE**s one random row per tick → each update is a CDC event.
2. **Postgres logical replication** (publication `sensor_raw_pub`) streams changes to the WAL.
3. **Debezium** (Kafka Connect source): reads WAL, sends change events to Kafka topic `sensor_cdc.public.sensor_raw`. SMT **ExtractNewRecordState** emits the row (no envelope).
4. **ETL**: Kafka consumer reads from that topic, computes vibration magnitude and `is_unreliable` (low battery), POSTs to **Inference**.
5. **Inference** returns `warning` when magnitude exceeds threshold or `is_unreliable`.

Transform can be extended with **Kafka Connect SMT** (e.g. drop columns, rename) in the connector config; ETL does feature computation and inference call.

## Environment variables (examples)

| Service   | Variable                       | Description                    |
|-----------|--------------------------------|--------------------------------|
| producer  | `DATABASE_URL`                 | PostgreSQL connection string   |
| etl       | `KAFKA_BOOTSTRAP_SERVERS`      | e.g. `kafka:9092`              |
| etl       | `KAFKA_CDC_TOPIC`              | e.g. `sensor_cdc.public.sensor_raw` |
| etl       | `INFERENCE_URL`                | Inference service URL          |
| inference | `VIBRATION_WARNING_THRESHOLD`  | Vibration alert threshold      |
| all       | `OTEL_EXPORTER_OTLP_ENDPOINT`  | OTel collector (optional)     |
