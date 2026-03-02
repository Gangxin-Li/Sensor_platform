-- ETL Load: append-only events table (incremental history, one row per CDC event).
-- Run separately: ./scripts/postgres-run.sh ./db/init_load_events_table.sql

CREATE TABLE IF NOT EXISTS sensor_etl_events (
    event_id        BIGSERIAL PRIMARY KEY,
    sensor_id       INTEGER NOT NULL,
    op              VARCHAR(1) NOT NULL,
    event_time      TIMESTAMPTZ NOT NULL,
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

CREATE INDEX IF NOT EXISTS idx_sensor_etl_events_sensor_id ON sensor_etl_events(sensor_id);
CREATE INDEX IF NOT EXISTS idx_sensor_etl_events_event_time ON sensor_etl_events(event_time);
CREATE INDEX IF NOT EXISTS idx_sensor_etl_events_sensor_time ON sensor_etl_events(sensor_id, event_time);
