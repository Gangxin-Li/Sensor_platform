# Producer

Simulates sensor updates in Postgres: every second it updates 5–10 random rows in the `sensors` table (`value` and `updated_at`). Used to generate changes for CDC (e.g. to Kafka for the ET step).

## Contents

| File | Description |
|------|--------------|
| **main.py** | Python app: connects to Postgres, loop that picks 5–10 random sensor IDs and updates their `value` and `updated_at`. |
| **requirements.txt** | Dependencies: `psycopg2-binary`. |
| **Dockerfile** | Image for running in Docker or K8s (Python 3.11, non-root user). |
| **docker.sh** | Script: `build` \| `rebuild` \| `run` \| `shutdown` for the producer image/container. |
| **configmap.yaml** | K8s ConfigMap: edit this file to change Postgres and producer params (interval, min/max updates) without touching code. Used when deploying to K8s. |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| POSTGRES_HOST | localhost | Postgres host (use `host.docker.internal` when running in Docker; `host.minikube.internal` in minikube). |
| POSTGRES_PORT | 5432 | Postgres port. |
| POSTGRES_DB | sensor_platform | Database name. |
| POSTGRES_USER | postgres | User. |
| POSTGRES_PASSWORD | postgres | Password. |
| PRODUCER_INTERVAL_SEC | 1.0 | Seconds between each batch of updates. |
| PRODUCER_MIN_UPDATES | 5 | Min number of sensors to update per batch. |
| PRODUCER_MAX_UPDATES | 10 | Max number of sensors to update per batch. |

## Run options

**Docker (detached, keep running):** from repo root, `./producer/docker.sh build` then `./producer/docker.sh run`. Stop with `./producer/docker.sh shutdown`.

**Local Python (foreground):** `pip install -r producer/requirements.txt` and `POSTGRES_HOST=localhost python producer/main.py` (Postgres must be running and have the `sensors` table).

**K8s (minikube):** `./scripts/k8s-deploy.sh producer`. Env is loaded from `producer/configmap.yaml`; edit that file to change interval or min/max updates, then re-apply and restart.
