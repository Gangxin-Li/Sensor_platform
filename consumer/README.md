# Consumer: read Postgres changes from Kafka

This app is the **ET (Extract–Transform)** step: it **consumes** change events from Kafka that were produced by **Debezium** from Postgres.

## How it works

1. **Postgres** holds the `sensors` table. When rows are inserted/updated/deleted, Postgres writes to the WAL.
2. **Debezium Connect** (in the Kafka stack) reads the WAL via the `sensor_cdc` publication and sends each change to the Kafka topic **`dbserver1.public.sensors`**.
3. **This consumer** subscribes to that topic and prints each event (Extract). You can add Transform and Load (e.g. write to another DB or API) later.

So: **Kafka is used to read Postgres changes** – Debezium pushes CDC into Kafka, and this process reads from Kafka.

## Prerequisites

- Kafka stack running: `./scripts/kafka-create.sh start`
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

For Docker or K8s, set `KAFKA_BOOTSTRAP_SERVERS` to the in-cluster Kafka address (e.g. `kafka:29092` if inside the same Docker network).

## Message format

Each message is a Debezium envelope JSON, for example:

- `op`: `c` (create), `u` (update), `r` (read/snapshot), `d` (delete)
- `before` / `after`: row state (null for insert/delete as appropriate)
- `source`: `ts_ms`, `db`, `schema`, `table`, etc.

The consumer logs these fields; you can extend `main.py` to transform or load them.
