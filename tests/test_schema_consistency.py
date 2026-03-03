from __future__ import annotations

from pathlib import Path
from typing import List

from consumer.models import SensorEtlEventRow, SensorEtlLoadRow, model_field_names


ROOT = Path(__file__).resolve().parents[1]
DB_DIR = ROOT / "db"



def _parse_columns_from_create(path: Path, table_name: str) -> List[str]:
    """
    Very small SQL parser to extract column names from a CREATE TABLE block.

    Assumes layout like:
        CREATE TABLE IF NOT EXISTS table_name (
            col1 TYPE ...,
            col2 TYPE ...,
            ...
        );
    """

    sql = path.read_text()
    marker = f"CREATE TABLE IF NOT EXISTS {table_name} ("
    start = sql.find(marker)
    assert start != -1, f"Could not find CREATE TABLE for {table_name} in {path}"
    start += len(marker)
    end = sql.find(");", start)
    assert end != -1, f"Could not find end of CREATE TABLE for {table_name} in {path}"

    body = sql[start:end]
    cols: List[str] = []
    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("--"):
            continue
        # Remove trailing comma
        if line.endswith(","):
            line = line[:-1]
        # Split on whitespace, first token is column name (we ignore constraints)
        first = line.split()[0]
        upper = first.upper()
        if upper in {"PRIMARY", "CONSTRAINT", "UNIQUE", "FOREIGN", "CHECK"}:
            continue
        cols.append(first)
    return cols


def test_sensor_etl_load_schema_matches_model() -> None:
    """Ensure db/init_load_table.sql and SensorEtlLoadRow stay in sync."""

    sql_path = DB_DIR / "init_load_table.sql"
    cols = _parse_columns_from_create(sql_path, "sensor_etl_load")
    model_fields = model_field_names(SensorEtlLoadRow)

    # Order should match, because INSERT in consumer/main.py relies on column order.
    assert cols == model_fields, (
        "sensor_etl_load columns in SQL and Pydantic model differ.\n"
        f"SQL:   {cols}\n"
        f"Model: {model_fields}\n"
        "If you changed db/init_load_table.sql, update consumer.models.SensorEtlLoadRow "
        "and consumer/main.py accordingly."
    )


def test_sensor_etl_events_schema_matches_model() -> None:
    """Ensure db/init_load_events_table.sql and SensorEtlEventRow stay in sync."""

    sql_path = DB_DIR / "init_load_events_table.sql"
    cols = _parse_columns_from_create(sql_path, "sensor_etl_events")
    model_fields = model_field_names(SensorEtlEventRow)

    assert cols == model_fields, (
        "sensor_etl_events columns in SQL and Pydantic model differ.\n"
        f"SQL:   {cols}\n"
        f"Model: {model_fields}\n"
        "If you changed db/init_load_events_table.sql, update consumer.models.SensorEtlEventRow "
        "and consumer/main.py accordingly."
    )

