"""
Sensor simulator (Producer).
- On start: ensure sensor_raw has exactly 100 rows (one per sensor). INSERT if empty.
- Then: only UPDATE one random sensor per tick. Each UPDATE is a CDC event (streamed via
  Postgres logical replication → Debezium → Kafka).
"""
import asyncio
import os
import random
import uuid
from typing import List

import asyncpg
from dotenv import load_dotenv
from opentelemetry import trace

from otel_utils import init_otel

load_dotenv()
init_otel(os.getenv("OTEL_SERVICE_NAME", "producer"))
tracer = trace.get_tracer(__name__, "1.0.0")

NUM_SENSORS = 100
UPDATE_INTERVAL_SEC = 0.1
PROB_PACKET_LOSS = 0.02
PROB_LOW_BATTERY = 0.01
PROB_LOW_RSSI = 0.03

# Exactly 100 distinct sensor UUIDs (same set every run for deterministic 100 rows)
SENSOR_IDS: List[uuid.UUID] = [uuid.uuid4() for _ in range(NUM_SENSORS)]


def sample_values() -> tuple:
    """Generate one set of readings; optionally inject low battery/rssi."""
    vib = lambda: round(random.gauss(0, 0.5), 6)
    temp = round(random.uniform(15.0, 35.0), 2)
    strain = round(random.uniform(-100, 100), 2)
    battery = round(random.uniform(3.2, 4.2), 2)
    rssi = random.randint(-85, -40)
    if random.random() < PROB_LOW_BATTERY:
        battery = round(random.uniform(2.0, 2.8), 2)
    if random.random() < PROB_LOW_RSSI:
        rssi = random.randint(-95, -90)
    return (vib(), vib(), vib(), temp, strain, battery, rssi)


async def ensure_initial_100(conn: asyncpg.Connection) -> None:
    """If sensor_raw is empty, INSERT 100 rows (one per sensor)."""
    n = await conn.fetchval("SELECT COUNT(*) FROM sensor_raw")
    if n and int(n) >= NUM_SENSORS:
        return
    rows = []
    for sid in SENSOR_IDS:
        vx, vy, vz, temp, strain, battery, rssi = sample_values()
        rows.append((str(sid), vx, vy, vz, temp, strain, battery, rssi))
    await conn.executemany(
        """
        INSERT INTO sensor_raw (
            sensor_id, vibration_x, vibration_y, vibration_z,
            ambient_temp, strain_gauge, battery_voltage, rssi
        )
        VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (sensor_id) DO NOTHING
        """,
        rows,
    )
    print(f"Initialized {len(rows)} rows in sensor_raw")


async def run_producer() -> None:
    database_url = os.getenv(
        "DATABASE_URL",
        "postgresql://postgres:postgres@db:5432/sensor_db",
    )
    pool = await asyncpg.create_pool(database_url, min_size=2, max_size=8)

    async with pool.acquire() as conn:
        await ensure_initial_100(conn)

    print(f"Producer started: {NUM_SENSORS} sensors, update interval={UPDATE_INTERVAL_SEC}s (CDC)")

    while True:
        if random.random() < PROB_PACKET_LOSS:
            await asyncio.sleep(UPDATE_INTERVAL_SEC)
            continue

        sensor_id = random.choice(SENSOR_IDS)
        vx, vy, vz, temp, strain, battery, rssi = sample_values()

        try:
            with tracer.start_as_current_span("producer.update_one") as span:
                span.set_attribute("sensor_id", str(sensor_id))
                async with pool.acquire() as conn:
                    await conn.execute(
                        """
                        UPDATE sensor_raw
                        SET vibration_x = $1, vibration_y = $2, vibration_z = $3,
                            ambient_temp = $4, strain_gauge = $5, battery_voltage = $6, rssi = $7,
                            updated_at = NOW()
                        WHERE sensor_id = $8
                        """,
                        vx, vy, vz, temp, strain, battery, rssi, sensor_id,
                    )
        except Exception as e:
            print(f"Update error: {e}")
        await asyncio.sleep(UPDATE_INTERVAL_SEC)


if __name__ == "__main__":
    asyncio.run(run_producer())
