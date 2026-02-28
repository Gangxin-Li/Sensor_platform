"""
Mock AI inference service: receives ETL features; returns Warning when vibration magnitude exceeds threshold.
"""
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from pydantic import BaseModel
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Vibration magnitude above this returns Warning (configurable)
VIBRATION_WARNING_THRESHOLD = float(os.getenv("VIBRATION_WARNING_THRESHOLD", "1.5"))


def _init_otel() -> None:
    if not os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return
    resource = Resource.create({"service.name": os.getenv("OTEL_SERVICE_NAME", "inference")})
    provider = TracerProvider(resource=resource)
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "").rstrip("/")
    if endpoint and "4317" not in endpoint:
        endpoint = f"{endpoint}:4317"
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint or "http://localhost:4317", insecure=True)))
    trace.set_tracer_provider(provider)


class FeatureRequest(BaseModel):
    sensor_id: str
    vibration_magnitude: float
    avg_temp: float
    strain_gauge: float
    is_unreliable: bool = False


class InferenceResponse(BaseModel):
    sensor_id: str
    status: str  # "ok" | "warning"
    message: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


_init_otel()
app = FastAPI(title="Inference API", lifespan=lifespan)
FastAPIInstrumentor.instrument_app(app)


@app.post("/features", response_model=InferenceResponse)
async def ingest_features(body: FeatureRequest) -> InferenceResponse:
    """Accept ETL features; return Warning when vibration magnitude exceeds threshold or is_unreliable."""
    if body.is_unreliable:
        return InferenceResponse(
            sensor_id=body.sensor_id,
            status="warning",
            message="Data marked unreliable (low battery)",
        )
    if body.vibration_magnitude >= VIBRATION_WARNING_THRESHOLD:
        return InferenceResponse(
            sensor_id=body.sensor_id,
            status="warning",
            message=f"Vibration magnitude {body.vibration_magnitude:.4f} exceeds threshold {VIBRATION_WARNING_THRESHOLD}",
        )
    return InferenceResponse(
        sensor_id=body.sensor_id,
        status="ok",
        message="ok",
    )


@app.get("/health")
async def health():
    return {"status": "ok"}
