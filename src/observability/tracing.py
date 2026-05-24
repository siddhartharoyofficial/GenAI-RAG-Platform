"""OpenTelemetry tracing setup — Cloud Trace exporter + auto-instrumentation."""

from __future__ import annotations

from opentelemetry import trace
from opentelemetry.exporter.cloud_trace import CloudTraceSpanExporter
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from src.common.config import Settings


def configure_tracing(cfg: Settings) -> None:
    """Wire OTel to Cloud Trace + auto-instrument popular libs."""
    resource = Resource.create({SERVICE_NAME: "genai-rag-api"})
    provider = TracerProvider(resource=resource)
    if cfg.otel_exporter == "gcp-trace":
        provider.add_span_processor(BatchSpanProcessor(CloudTraceSpanExporter(project_id=cfg.project_id)))
    trace.set_tracer_provider(provider)

    RedisInstrumentor().instrument()
    # FastAPIInstrumentor is applied per-app in the lifespan handler.
