"""
ETL: stream consumer from Kafka (CDC from Postgres via Debezium).
- Consumes topic sensor_cdc.public.sensor_raw (after SMT = plain row JSON).
- Per message: compute vibration magnitude, is_unreliable, POST to inference.
"""
import json
import math
import os
import sys

import httpx
from confluent_kafka import Consumer, KafkaError
from dotenv import load_dotenv
from opentelemetry import trace

from models import FeaturePayload
from otel_utils import init_otel

load_dotenv()
init_otel(os.getenv("OTEL_SERVICE_NAME", "etl"))
tracer = trace.get_tracer(__name__, "1.0.0")

# Config
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_CDC_TOPIC", "sensor_cdc.public.sensor_raw")
INFERENCE_URL = os.getenv("INFERENCE_URL", "http://inference:8000")
CONSUMER_GROUP = os.getenv("KAFKA_CONSUMER_GROUP", "etl-inference")


def build_payload(msg_value: dict) -> FeaturePayload | None:
    """Parse Debezium SMT output (after = one row)."""
    try:
        sid = msg_value.get("sensor_id")
        if not sid:
            return None
        return FeaturePayload.from_cdc_row(
            sensor_id=str(sid),
            vibration_x=float(msg_value.get("vibration_x", 0)),
            vibration_y=float(msg_value.get("vibration_y", 0)),
            vibration_z=float(msg_value.get("vibration_z", 0)),
            ambient_temp=float(msg_value.get("ambient_temp", 0)),
            strain_gauge=float(msg_value.get("strain_gauge", 0)),
            battery_voltage=float(msg_value.get("battery_voltage", 0)),
        )
    except (TypeError, KeyError, ValueError):
        return None


def send_to_inference(payload: FeaturePayload) -> None:
    with httpx.Client(timeout=10.0) as client:
        try:
            r = client.post(
                f"{INFERENCE_URL.rstrip('/')}/features",
                json=payload.model_dump(),
            )
            r.raise_for_status()
        except Exception as e:
            print(f"Inference POST error for {payload.sensor_id}: {e}", file=sys.stderr)


def run_consumer() -> None:
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": CONSUMER_GROUP,
        "auto.offset.reset": "earliest",
    })
    consumer.subscribe([KAFKA_TOPIC])
    print(f"ETL consumer started: topic={KAFKA_TOPIC}, inference={INFERENCE_URL}")

    while True:
        msg = consumer.poll(timeout=1.0)
        if msg is None:
            continue
        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                continue
            print(f"Consumer error: {msg.error()}", file=sys.stderr)
            continue
        try:
            value = json.loads(msg.value().decode("utf-8"))
        except (json.JSONDecodeError, AttributeError):
            continue
        # Debezium initial snapshot or heartbeat may have different shape; we want "after" row.
        # After SMT ExtractNewRecordState, value is the row itself (no envelope).
        if not isinstance(value, dict):
            continue
        payload = build_payload(value)
        if payload is None:
            continue
        with tracer.start_as_current_span("etl.process_cdc") as span:
            span.set_attribute("sensor_id", payload.sensor_id)
            send_to_inference(payload)


if __name__ == "__main__":
    run_consumer()
