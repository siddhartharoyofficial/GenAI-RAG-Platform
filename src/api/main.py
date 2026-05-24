"""FastAPI entrypoint for the GenAI RAG platform.

The API service is the orchestrator. It owns the request lifecycle:
    1. Validate request, propagate trace context.
    2. Embed query, probe semantic cache.
    3. Classify intent via the router.
    4. Dispatch to a LangGraph workflow.
    5. Stream the response back, write through the cache, update memory.

Heavy lifting lives in the modules under src/*; this file is intentionally thin.
"""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from typing import AsyncIterator

import structlog
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from src.cache.semantic_cache import SemanticCache
from src.common.config import settings
from src.observability.tracing import configure_tracing
from src.orchestration.workflow import RAGWorkflow
from src.router.intent_router import IntentRouter

log = structlog.get_logger()


# --- Lifecycle ----------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Initialize singletons once; tear them down on shutdown."""
    cfg = settings()
    configure_tracing(cfg)

    app.state.cache = await SemanticCache.connect(cfg)
    app.state.router = IntentRouter(cfg)
    app.state.workflow = RAGWorkflow(cfg)

    log.info("api.ready", project=cfg.project_id, region=cfg.region)
    try:
        yield
    finally:
        await app.state.cache.close()


app = FastAPI(
    title="GenAI RAG Platform",
    version="0.1.0",
    description="Hybrid semantic-cache and routed multi-agent RAG, on Google Cloud.",
    lifespan=lifespan,
)


# --- Schemas ------------------------------------------------------------------

class QueryRequest(BaseModel):
    query: str = Field(..., min_length=1, max_length=4096)
    session_id: str | None = None
    tenant_id: str | None = None
    metadata: dict = Field(default_factory=dict)


class QueryResponse(BaseModel):
    answer: str
    source: str  # "cache" | "rag"
    citations: list[dict] = Field(default_factory=list)
    trace_id: str


# --- Routes -------------------------------------------------------------------

@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz(request: Request) -> dict[str, str]:
    """Readiness — confirms the cache is reachable."""
    try:
        await request.app.state.cache.ping()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"status": "ready"}


@app.post("/v1/query", response_model=QueryResponse)
async def query(req: QueryRequest, request: Request) -> QueryResponse:
    """Non-streaming endpoint — useful for batch and eval workloads."""
    cache: SemanticCache = request.app.state.cache
    router: IntentRouter = request.app.state.router
    workflow: RAGWorkflow = request.app.state.workflow

    # 1. Cache probe.
    cached = await cache.lookup(req.query, tenant_id=req.tenant_id)
    if cached is not None:
        return QueryResponse(answer=cached.answer, source="cache", citations=cached.citations, trace_id=cached.trace_id)

    # 2. Intent classification.
    intent = await router.classify(req.query)

    # 3. Dispatch.
    result = await workflow.run(query=req.query, intent=intent, session_id=req.session_id, tenant_id=req.tenant_id)

    # 4. Async cache write-back — don't block the response on it.
    asyncio.create_task(cache.write(req.query, result, tenant_id=req.tenant_id))

    return QueryResponse(answer=result.answer, source="rag", citations=result.citations, trace_id=result.trace_id)


@app.post("/v1/query/stream")
async def query_stream(req: QueryRequest, request: Request) -> StreamingResponse:
    """SSE streaming endpoint — TTFT-optimized path for interactive UIs."""
    cache: SemanticCache = request.app.state.cache
    router: IntentRouter = request.app.state.router
    workflow: RAGWorkflow = request.app.state.workflow

    async def event_stream() -> AsyncIterator[str]:
        cached = await cache.lookup(req.query, tenant_id=req.tenant_id)
        if cached is not None:
            yield f"event: cache_hit\ndata: {cached.answer}\n\n"
            return

        intent = await router.classify(req.query)
        async for token in workflow.run_streaming(
            query=req.query, intent=intent, session_id=req.session_id, tenant_id=req.tenant_id
        ):
            yield f"data: {token}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
