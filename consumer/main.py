#!/usr/bin/env python3
"""
Consumer (ET): read Postgres CDC events from Kafka.
Debezium writes changes from the sensors table to the topic dbserver1.public.sensors.
This script consumes that topic and logs each change (Extract). Transform/Load can be added later.
"""
import json
import logging
import os
import signal
import sys

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

_running = True


def _sig_handler(*_):
    global _running
    _running = False


def main():
    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

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
                value = json.loads(msg.value().decode("utf-8"))
                op = value.get("op", "?")
                before = value.get("before")
                after = value.get("after")
                source = value.get("source", {})
                ts_ms = source.get("ts_ms")
                table = source.get("table", "?")
                op_label = {"c": "INSERT", "u": "UPDATE", "r": "READ", "d": "DELETE"}.get(op, op)
                logger.info(
                    "CDC %s table=%s ts_ms=%s before=%s after=%s",
                    op_label, table, ts_ms, before, after,
                )
            except (json.JSONDecodeError, AttributeError) as e:
                logger.warning("Invalid message: %s", e)
    except KafkaException as e:
        logger.exception("Kafka error: %s", e)
        sys.exit(1)
    finally:
        consumer.close()
        logger.info("Consumer stopped.")


if __name__ == "__main__":
    main()
