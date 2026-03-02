-- Sensor Platform: sensors table (100 rows)
-- Run on first Postgres init or apply to existing DB.

CREATE TABLE IF NOT EXISTS sensors (
    id              INTEGER PRIMARY KEY,
    name            VARCHAR(128) NOT NULL,
    sensor_type     VARCHAR(64) NOT NULL,
    location        VARCHAR(128),
    latitude        NUMERIC(9, 6),
    longitude       NUMERIC(9, 6),
    value           DOUBLE PRECISION NOT NULL DEFAULT 0,
    value_min       DOUBLE PRECISION NOT NULL DEFAULT 0,
    value_max       DOUBLE PRECISION NOT NULL DEFAULT 100,
    unit            VARCHAR(32) DEFAULT '',
    status          VARCHAR(32) DEFAULT 'active',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version         INTEGER NOT NULL DEFAULT 1,
    metadata        JSONB DEFAULT '{}'
);

ALTER TABLE sensors ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION sensors_bump_version() RETURNS TRIGGER AS $$
BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sensors_version_trigger ON sensors;
CREATE TRIGGER sensors_version_trigger
  BEFORE UPDATE ON sensors
  FOR EACH ROW
  EXECUTE PROCEDURE sensors_bump_version();

CREATE INDEX IF NOT EXISTS idx_sensors_updated_at ON sensors(updated_at);
CREATE INDEX IF NOT EXISTS idx_sensors_version ON sensors(version);
CREATE INDEX IF NOT EXISTS idx_sensors_type ON sensors(sensor_type);
CREATE INDEX IF NOT EXISTS idx_sensors_location ON sensors(location);
CREATE INDEX IF NOT EXISTS idx_sensors_status ON sensors(status);

-- Publication for CDC (Debezium / logical replication).
DROP PUBLICATION IF EXISTS sensor_cdc;
CREATE PUBLICATION sensor_cdc FOR TABLE sensors;

INSERT INTO sensors (
    id, name, sensor_type, location, latitude, longitude,
    value, value_min, value_max, unit, status, version, metadata
)
SELECT
    n,
    'sensor_' || LPAD(n::TEXT, 3, '0'),
    (ARRAY['temperature', 'humidity', 'pressure', 'light', 'co2', 'motion', 'noise', 'voltage'])[1 + (n % 8)],
    'building_' || (1 + (n % 5)) || '_floor_' || (1 + (n % 4)),
    51.0 + (n % 10) * 0.01,
    -0.1 + (n % 20) * 0.01,
    50 + (random() * 50),
    0,
    100,
    CASE (n % 8)
        WHEN 0 THEN 'degC'
        WHEN 1 THEN '%'
        WHEN 2 THEN 'hPa'
        WHEN 3 THEN 'lux'
        WHEN 4 THEN 'ppm'
        ELSE 'raw'
    END,
    'active',
    1,
    jsonb_build_object(
        'zone', (n % 5),
        'building', (n % 3),
        'room', 'R' || (n % 20)
    )
FROM generate_series(1, 100) AS n
ON CONFLICT (id) DO NOTHING;
