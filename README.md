# Sensor Platform

Kubernetes runs on Docker. Create and manage the cluster with one script.

## Scripts

### k8s-create — cluster on Docker

```bash
./scripts/k8s-create.sh build    # create cluster (kind or minikube)
./scripts/k8s-create.sh rebuild  # delete then create again
./scripts/k8s-create.sh pause   # stop cluster (minikube only)
./scripts/k8s-create.sh unpause # start again (minikube only)
./scripts/k8s-create.sh delete  # remove cluster
```

### postgres-create — Postgres service on Docker

```bash
./scripts/postgres-create.sh start   # run Postgres (port 5432, DB sensor_platform, wal_level=logical)
./scripts/postgres-create.sh stop    # stop container
./scripts/postgres-create.sh restart # stop then start
./scripts/postgres-create.sh delete  # remove container and volume
```

Optional env: `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_CONTAINER`, `POSTGRES_VOLUME`.

### postgres-run — run a SQL file on the database

```bash
./scripts/postgres-run.sh ./db/init_db.sql   # run that SQL file on the DB
```

Postgres container must be running (`./scripts/postgres-create.sh start`). Uses same env as postgres-create for container name and DB.

## Module: sensors table

Defined in `db/init_db.sql`. Columns: `id`, `name`, `sensor_type`, `location`, `latitude`, `longitude`, `value`, `value_min`, `value_max`, `unit`, `status`, `created_at`, `updated_at`, `metadata` (JSONB). Seeded with 100 sensors (types: temperature, humidity, pressure, light, co2, motion, noise, voltage; locations like building/floor; metadata: zone, building, room).

## Project structure

```
Sensor_platform/
├── db/
│   └── init_db.sql         # sensors table + 100 rows
├── scripts/
│   ├── k8s-create.sh
│   ├── postgres-create.sh
│   └── postgres-run.sh
└── README.md
```
