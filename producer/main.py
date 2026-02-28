#!/usr/bin/env python3
"""
Producer: every second update 5-10 random sensors (value, updated_at) in Postgres.
Used to generate changes for CDC (e.g. to Kafka for ET). Run locally or in K8s.
"""
import os
import random
import time
import logging
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import execute_values

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

DB_HOST = os.getenv("POSTGRES_HOST", "localhost")
DB_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB", "sensor_platform")
DB_USER = os.getenv("POSTGRES_USER", "postgres")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "postgres")
INTERVAL_SEC = float(os.getenv("PRODUCER_INTERVAL_SEC", "1.0"))
MIN_UPDATES = int(os.getenv("PRODUCER_MIN_UPDATES", "5"))
MAX_UPDATES = int(os.getenv("PRODUCER_MAX_UPDATES", "10"))
TOTAL_SENSORS = 100


def get_conn():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


@contextmanager
def db_cursor():
    conn = get_conn()
    try:
        yield conn.cursor()
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def update_sensors(cursor, sensor_ids):
    if not sensor_ids:
        return
    updates = [(round(random.uniform(0, 100), 2), sid) for sid in sensor_ids]
    execute_values(
        cursor,
        """
        UPDATE sensors
        SET value = v.value, updated_at = NOW()
        FROM (VALUES %s) AS v(value, id)
        WHERE sensors.id = v.id::int
        """,
        updates,
        template="(%s, %s)",
        page_size=len(updates),
    )


def main():
    n_min, n_max = min(MIN_UPDATES, MAX_UPDATES), max(MIN_UPDATES, MAX_UPDATES)
    logger.info(
        "Producer started: update %s-%s sensors every %s s (DB %s:%s/%s)",
        n_min, n_max, INTERVAL_SEC, DB_HOST, DB_PORT, DB_NAME,
    )
    while True:
        try:
            with db_cursor() as cur:
                n = random.randint(n_min, n_max)
                ids = random.sample(range(1, TOTAL_SENSORS + 1), n)
                update_sensors(cur, ids)
                logger.info("Updated sensor ids=%s", ids)
        except Exception as e:
            logger.exception("Update failed: %s", e)
        time.sleep(INTERVAL_SEC)


if __name__ == "__main__":
    main()
