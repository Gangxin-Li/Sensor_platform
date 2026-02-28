"""OpenTelemetry init: enabled only when OTEL_EXPORTER_OTLP_ENDPOINT is set."""
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

def init_otel(service_name: str) -> None:
    if not os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return
    resource = Resource.create({"service.name": service_name or "producer"})
    provider = TracerProvider(resource=resource)
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "").rstrip("/")
    if endpoint and "4317" not in endpoint:
        endpoint = f"{endpoint}:4317"
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint or "http://localhost:4317", insecure=True)))
    trace.set_tracer_provider(provider)
