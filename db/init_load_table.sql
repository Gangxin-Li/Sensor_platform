-- ETL Load table: target for consumer Load step (same DB as sensors, no publication).
-- Run separately from init_db.sql: ./scripts/postgres-run.sh ./db/init_load_table.sql

CREATE TABLE IF NOT EXISTS sensor_etl_load (
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
    metadata        JSONB DEFAULT '{}',
    loaded_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sensor_etl_load_updated_at ON sensor_etl_load(updated_at);
CREATE INDEX IF NOT EXISTS idx_sensor_etl_load_loaded_at ON sensor_etl_load(loaded_at);
