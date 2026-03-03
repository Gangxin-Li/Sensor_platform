from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Type

from pydantic import BaseModel


class SensorEtlLoadRow(BaseModel):
    """Pydantic model mirroring db/init_load_table.sql (sensor_etl_load)."""

    id: int
    name: str
    sensor_type: str
    location: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    value: float
    value_min: float
    value_max: float
    unit: str = ""
    status: str = "active"
    created_at: datetime
    updated_at: datetime
    version: int = 1
    metadata: Dict[str, Any] = {}
    loaded_at: datetime


class SensorEtlEventRow(BaseModel):
    """Pydantic model mirroring db/init_load_events_table.sql (sensor_etl_events)."""

    event_id: int | None = None
    sensor_id: int
    op: str
    event_time: datetime
    name: str
    sensor_type: str
    location: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    value: float
    value_min: float
    value_max: float
    unit: str = ""
    status: str = "active"
    created_at: datetime
    updated_at: datetime
    version: int = 1
    metadata: Dict[str, Any] = {}
    loaded_at: datetime


def model_field_names(model_cls: Type[BaseModel]) -> List[str]:
    """
    Return model field names in declaration order.

    Supports both Pydantic v1 (__fields__) and v2 (model_fields).
    """

    # Pydantic v2
    fields = getattr(model_cls, "model_fields", None)
    if fields is not None:
        return list(fields.keys())

    # Pydantic v1 fallback
    fields = getattr(model_cls, "__fields__", None)
    if fields is not None:
        return list(fields.keys())

    raise RuntimeError(f"Unsupported Pydantic version for {model_cls!r}")

