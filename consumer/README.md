# Consumer: read Postgres changes from Kafka

This app is the **ET (Extract–Transform)** step: it **consumes** change events from Kafka that were produced by **Debezium** from Postgres.

- **Extraction (implemented)**: subscribe to the Debezium CDC topic, parse the JSON envelope (`before/after/op/source/...`), and log a normalized `CDC RECORD` structure.
- **Transformation (implemented)**: extreme outlier filter based on `value` vs `value_min`/`value_max`; filtered records are logged only, not loaded.
- **Load (implemented)**: cleaned records are written to two tables in the same DB (`sensor_platform`):
  - **`sensor_etl_load`**: current state (upsert by `id`).
  - **`sensor_etl_events`**: append-only history (one row per CDC event).
  Create the tables separately:  
  `./scripts/postgres-run.sh ./db/init_load_table.sql`  
  `./scripts/postgres-run.sh ./db/init_load_events_table.sql`

## How it works

1. **Postgres** holds the `sensors` table. When rows are inserted/updated/deleted, Postgres writes to the WAL.
2. **Debezium Connect** (in the Kafka stack) reads the WAL via the `sensor_cdc` publication and sends each change to the Kafka topic **`dbserver1.public.sensors`**.
3. **This consumer** subscribes to that topic and performs **Extraction**: it parses each message into a structured Python dict (`CDC RECORD`) and logs it. You can add Transform and Load (e.g. write to another DB or API) later.

So: **Kafka is used to read Postgres changes** – Debezium pushes CDC into Kafka, and this process reads from Kafka.

## Prerequisites

- Kafka stack running: `./scripts/start-stack.sh` (then `./scripts/register-connector.sh`)
- Postgres with `sensors` and publication `sensor_cdc` (see `db/init_db.sql`)
- Some changes in `sensors` (e.g. run the producer so that Debezium has events to stream)

## Run

```bash
pip install -r consumer/requirements.txt
python consumer/main.py
```

Stop with Ctrl+C.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| KAFKA_BOOTSTRAP_SERVERS | localhost:9092 | Kafka brokers |
| KAFKA_TOPIC | dbserver1.public.sensors | Debezium topic (schema.table) |
| KAFKA_GROUP_ID | sensor-consumer-et | Consumer group |
| POSTGRES_HOST | localhost | Postgres host for Load (use `postgres` when consumer runs in Docker on same compose network) |
| POSTGRES_PORT | 5432 | Postgres port |
| POSTGRES_DB | sensor_platform | Database name |
| POSTGRES_USER / POSTGRES_PASSWORD | postgres | Credentials for Load tables |
| LOAD_TABLE | sensor_etl_load | State table (upsert by id) |
| LOAD_EVENTS_TABLE | sensor_etl_events | Events table (append-only history) |

**K8s:** Env is loaded from `consumer/configmap.yaml`. Edit that file to change Kafka/Postgres/load table params without touching code; then `kubectl apply -f consumer/configmap.yaml` and `kubectl rollout restart deployment/consumer -n sensor-platform`.

For Docker or K8s, set `KAFKA_BOOTSTRAP_SERVERS` to the in-cluster Kafka address (e.g. `kafka:29092` if inside the same Docker network).

## Message format

Each message is a Debezium envelope JSON, for example:

- `op`: `c` (create), `u` (update), `r` (read/snapshot), `d` (delete)
- `before` / `after`: row state (null for insert/delete as appropriate)
- `source`: `ts_ms`, `db`, `schema`, `table`, etc.

The consumer logs these fields; you can extend `main.py` to transform or load them.
