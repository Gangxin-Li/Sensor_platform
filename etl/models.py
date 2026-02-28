"""
ETL data models. CDC payload from Kafka (after Debezium SMT) is one row per message.
"""
from pydantic import BaseModel

BATTERY_LOW_THRESHOLD = 3.0


class FeaturePayload(BaseModel):
    """Feature vector sent to inference."""
    sensor_id: str
    vibration_magnitude: float
    avg_temp: float
    strain_gauge: float
    is_unreliable: bool = False

    @classmethod
    def from_cdc_row(
        cls,
        sensor_id: str,
        vibration_x: float,
        vibration_y: float,
        vibration_z: float,
        ambient_temp: float,
        strain_gauge: float,
        battery_voltage: float,
    ) -> "FeaturePayload":
        import math
        mag = math.sqrt(vibration_x**2 + vibration_y**2 + vibration_z**2)
        is_unreliable = battery_voltage < BATTERY_LOW_THRESHOLD
        return cls(
            sensor_id=sensor_id,
            vibration_magnitude=round(mag, 6),
            avg_temp=round(ambient_temp, 2),
            strain_gauge=round(strain_gauge, 2),
            is_unreliable=is_unreliable,
        )
