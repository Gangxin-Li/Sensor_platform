-- sensor-platform: database init for CDC pipeline
-- sensor_raw: exactly 100 rows (one per sensor). All changes are CDC (updates).
-- Postgres logical replication streams these changes to Kafka via Debezium.

-- ============================================================
-- sensor_raw: current state per sensor (100 rows only)
-- Producer INSERTs 100 rows once, then only UPDATEs. Each UPDATE is a CDC event.
-- ============================================================
CREATE TABLE IF NOT EXISTS sensor_raw (
    sensor_id       UUID PRIMARY KEY,
    vibration_x     DOUBLE PRECISION NOT NULL,
    vibration_y     DOUBLE PRECISION NOT NULL,
    vibration_z     DOUBLE PRECISION NOT NULL,
    ambient_temp    DOUBLE PRECISION NOT NULL,
    strain_gauge    DOUBLE PRECISION NOT NULL,
    battery_voltage DOUBLE PRECISION NOT NULL,
    rssi            INTEGER NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sensor_raw IS 'Current reading per sensor (100 rows). Updates streamed via logical replication.';

-- Publication for logical replication (consumed by Debezium → Kafka). Idempotent.
DO $$
BEGIN
  CREATE PUBLICATION sensor_raw_pub FOR TABLE sensor_raw;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
