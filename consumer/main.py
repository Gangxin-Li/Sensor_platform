#!/usr/bin/env python3
"""
Consumer (ETL): read Postgres CDC events from Kafka, transform (outlier filter),
load into sensor_etl_load (current state) and sensor_etl_events (append-only history).
"""
import json
import logging
import os
import signal
import sys
from datetime import datetime, timezone

import psycopg2
from confluent_kafka import Consumer, KafkaError, KafkaException

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "dbserver1.public.sensors")
KAFKA_GROUP = os.getenv("KAFKA_GROUP_ID", "sensor-consumer-et")

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB", "sensor_platform")
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "postgres")
LOAD_TABLE = os.getenv("LOAD_TABLE", "sensor_etl_load")
LOAD_EVENTS_TABLE = os.getenv("LOAD_EVENTS_TABLE", "sensor_etl_events")

_running = True


def _sig_handler(*_):
    global _running
    _running = False


def _numeric(v):
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _parse_metadata(v):
    if v is None:
        return "{}"
    if isinstance(v, dict):
        return json.dumps(v)
    if isinstance(v, str):
        return v
    return "{}"


def load_into_postgres(conn, after: dict) -> None:
    """Upsert one row into sensor_etl_load (Load step)."""
    if not after or not isinstance(after, dict):
        return
    try:
        id_ = after.get("id")
        if id_ is None:
            return
        name = after.get("name") or ""
        sensor_type = after.get("sensor_type") or ""
        location = after.get("location")
        latitude = _numeric(after.get("latitude"))
        longitude = _numeric(after.get("longitude"))
        value = _numeric(after.get("value")) if after.get("value") is not None else 0.0
        value_min = _numeric(after.get("value_min")) if after.get("value_min") is not None else 0.0
        value_max = _numeric(after.get("value_max")) if after.get("value_max") is not None else 100.0
        unit = after.get("unit") or ""
        status = after.get("status") or "active"
        created_at = after.get("created_at")
        updated_at = after.get("updated_at")
        version = after.get("version")
        if version is None:
            version = 1
        try:
            version = int(version)
        except (TypeError, ValueError):
            version = 1
        metadata = _parse_metadata(after.get("metadata"))

        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO sensor_etl_load (
                    id, name, sensor_type, location, latitude, longitude,
                    value, value_min, value_max, unit, status,
                    created_at, updated_at, version, metadata, loaded_at
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s::timestamptz, %s::timestamptz, %s, %s::jsonb, NOW()
                )
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    sensor_type = EXCLUDED.sensor_type,
                    location = EXCLUDED.location,
                    latitude = EXCLUDED.latitude,
                    longitude = EXCLUDED.longitude,
                    value = EXCLUDED.value,
                    value_min = EXCLUDED.value_min,
                    value_max = EXCLUDED.value_max,
                    unit = EXCLUDED.unit,
                    status = EXCLUDED.status,
                    updated_at = EXCLUDED.updated_at,
                    version = EXCLUDED.version,
                    metadata = EXCLUDED.metadata,
                    loaded_at = NOW()
                """,
                (
                    id_, name, sensor_type, location, latitude, longitude,
                    value, value_min, value_max, unit, status,
                    created_at, updated_at, version, metadata,
                ),
            )
        conn.commit()
    except Exception as e:
        logger.exception("Load into Postgres failed: %s", e)
        conn.rollback()


def _event_time_from_payload(ts_ms, updated_at_str):
    """Derive event_time from payload ts_ms (preferred) or updated_at string."""
    if ts_ms is not None:
        try:
            return datetime.fromtimestamp(int(ts_ms) / 1000.0, tz=timezone.utc)
        except (TypeError, ValueError, OSError):
            pass
    if updated_at_str:
        return updated_at_str  # pass through for ::timestamptz in SQL
    return None


def load_event_into_postgres(conn, after: dict, op: str, ts_ms) -> None:
    """Append one row to sensor_etl_events (incremental history, append-only)."""
    if not after or not isinstance(after, dict):
        return
    if op not in ("c", "u", "r", "d"):
        return
    try:
        id_ = after.get("id")
        if id_ is None:
            return
        name = after.get("name") or ""
        sensor_type = after.get("sensor_type") or ""
        location = after.get("location")
        latitude = _numeric(after.get("latitude"))
        longitude = _numeric(after.get("longitude"))
        value = _numeric(after.get("value")) if after.get("value") is not None else 0.0
        value_min = _numeric(after.get("value_min")) if after.get("value_min") is not None else 0.0
        value_max = _numeric(after.get("value_max")) if after.get("value_max") is not None else 100.0
        unit = after.get("unit") or ""
        status = after.get("status") or "active"
        created_at = after.get("created_at")
        updated_at = after.get("updated_at")
        version = after.get("version")
        if version is None:
            version = 1
        try:
            version = int(version)
        except (TypeError, ValueError):
            version = 1
        metadata = _parse_metadata(after.get("metadata"))
        event_time = _event_time_from_payload(ts_ms, updated_at)
        if event_time is None:
            event_time = updated_at or created_at

        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO sensor_etl_events (
                    sensor_id, op, event_time, name, sensor_type, location, latitude, longitude,
                    value, value_min, value_max, unit, status,
                    created_at, updated_at, version, metadata, loaded_at
                ) VALUES (
                    %s, %s, %s::timestamptz, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s::timestamptz, %s::timestamptz, %s, %s::jsonb, NOW()
                )
                """,
                (
                    id_, op, event_time, name, sensor_type, location, latitude, longitude,
                    value, value_min, value_max, unit, status,
                    created_at, updated_at, version, metadata,
                ),
            )
        conn.commit()
    except Exception as e:
        logger.exception("Load event into Postgres failed: %s", e)
        conn.rollback()


def is_extreme_outlier(after: dict) -> bool:
    """
    Simple transformation rule:
    - Treat a reading as an outlier if `value` is far outside the configured [value_min, value_max] range.
    - Margin is +/-10 units beyond the stored range.
    """
    if not isinstance(after, dict):
        return False
    try:
        value = after.get("value")
        value_min = after.get("value_min", 0.0)
        value_max = after.get("value_max", 100.0)
        if value is None:
            return False
        margin = 10.0
        if value < (value_min - margin) or value > (value_max + margin):
            return True
    except TypeError:
        return False
    return False


def main():
    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

    logger.info(
        "Connecting to Postgres %s:%s/%s for Load tables %s (state) + %s (events)",
        POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, LOAD_TABLE, LOAD_EVENTS_TABLE,
    )
    pg_conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )
    pg_conn.autocommit = False

    conf = {
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": KAFKA_GROUP,
        "auto.offset.reset": "earliest",
    }
    consumer = Consumer(conf)
    consumer.subscribe([KAFKA_TOPIC])

    logger.info(
        "Consumer started: topic=%s group=%s bootstrap=%s",
        KAFKA_TOPIC, KAFKA_GROUP, KAFKA_BOOTSTRAP,
    )

    try:
        while _running:
            msg = consumer.poll(timeout=1.0)
            if msg is None:
                continue
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                raise KafkaException(msg.error())
            try:
                raw = msg.value().decode("utf-8")
                value = json.loads(raw)

                # Debezium with JsonConverter usually wraps data in a top-level "payload".
                # Fall back to top-level if there is no payload key.
                payload = value.get("payload", value)

                op = payload.get("op", "?") if isinstance(payload, dict) else "?"
                before = payload.get("before") if isinstance(payload, dict) else None
                after = payload.get("after") if isinstance(payload, dict) else None
                source = payload.get("source", {}) if isinstance(payload, dict) else {}
                ts_ms = payload.get("ts_ms") if isinstance(payload, dict) else None
                table = source.get("table", "?")

                # If there is no meaningful CDC payload, log raw once and skip.
                if op == "?" and before is None and after is None:
                    logger.info("CDC RAW (no op/before/after): %s", raw)
                    continue

                record = {
                    "op": op,
                    "ts_ms": ts_ms,
                    "table": table,
                    "before": before,
                    "after": after,
                    "source": source,
                }
                # Transformation step: filter out extreme outliers based on value/value_min/value_max.
                if after and is_extreme_outlier(after):
                    logger.info("CDC FILTERED OUTLIER: %s", json.dumps(record, ensure_ascii=False))
                    continue

                logger.info("CDC RECORD (clean): %s", json.dumps(record, ensure_ascii=False))

                # Load step: state table (upsert) + events table (append-only).
                if after and payload.get("op") in ("c", "u", "r"):
                    load_into_postgres(pg_conn, after)
                    load_event_into_postgres(
                        pg_conn, after,
                        payload.get("op", "u"),
                        payload.get("ts_ms"),
                    )
            except (json.JSONDecodeError, AttributeError) as e:
                logger.warning("Invalid message: %s", e)
    except KafkaException as e:
        logger.exception("Kafka error: %s", e)
        sys.exit(1)
    finally:
        consumer.close()
        if pg_conn:
            pg_conn.close()
        logger.info("Consumer stopped.")


if __name__ == "__main__":
    main()
