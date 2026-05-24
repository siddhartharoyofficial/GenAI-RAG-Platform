"""LangGraph workflow — stateful RAG with intent-based branching.

The workflow is a small graph with explicit nodes. Cycles (clarification loops,
retries) are first-class because LangGraph models them natively. Replacing this
with bare asyncio chains works until the first time you need to replay a failed
trace; we paid that lesson once.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4

import structlog
from langgraph.graph import END, StateGraph

from src.common.config import Settings
from src.reranker.cross_encoder import CrossEncoderReranker
from src.retrieval.hybrid_search import HybridRetriever
from src.router.intent_router import Intent

log = structlog.get_logger()


@dataclass(slots=True)
class WorkflowResult:
    answer: str
    citations: list[dict[str, Any]] = field(default_factory=list)
    trace_id: str = ""


@dataclass(slots=True)
class GraphState:
    query: str
    intent: Intent
    session_id: str | None
    tenant_id: str | None
    retrieved: list[Any] = field(default_factory=list)
    reranked: list[Any] = field(default_factory=list)
    answer: str = ""
    citations: list[dict[str, Any]] = field(default_factory=list)
    trace_id: str = field(default_factory=lambda: uuid4().hex)


class RAGWorkflow:
    """Builds and runs the LangGraph workflow."""

    def __init__(self, cfg: Settings) -> None:
        self._cfg = cfg
        # In production these get injected; lazy-init here for brevity.
        self._retriever: HybridRetriever | None = None
        self._reranker = CrossEncoderReranker(cfg)
        self._graph = self._build_graph()

    def _build_graph(self) -> Any:
        g = StateGraph(GraphState)
        g.add_node("retrieve", self._node_retrieve)
        g.add_node("rerank", self._node_rerank)
        g.add_node("synthesize_fast", self._node_synthesize_fast)
        g.add_node("synthesize_quality", self._node_synthesize_quality)

        g.set_entry_point("retrieve")
        g.add_edge("retrieve", "rerank")
        g.add_conditional_edges(
            "rerank",
            self._route_synthesis,
            {
                "fast": "synthesize_fast",
                "quality": "synthesize_quality",
            },
        )
        g.add_edge("synthesize_fast", END)
        g.add_edge("synthesize_quality", END)
        return g.compile()

    # --- Node implementations ------------------------------------------------

    async def _node_retrieve(self, state: GraphState) -> dict[str, Any]:
        if self._retriever is None:
            raise RuntimeError("Retriever not initialized")
        hits = await self._retriever.search(state.query, tenant_id=state.tenant_id)
        return {"retrieved": hits}

    async def _node_rerank(self, state: GraphState) -> dict[str, Any]:
        ranked = await self._reranker.rerank(state.query, state.retrieved)
        return {"reranked": ranked}

    async def _node_synthesize_fast(self, state: GraphState) -> dict[str, Any]:
        # Stub — wire to Gemini 2.5 Flash via Vertex AI.
        answer = f"[fast synthesis stub for: {state.query}]"
        return {"answer": answer, "citations": [{"chunk_id": r.hit.chunk_id} for r in state.reranked]}

    async def _node_synthesize_quality(self, state: GraphState) -> dict[str, Any]:
        # Stub — wire to Claude 3.5 Sonnet via Vertex AI Model Garden.
        answer = f"[quality synthesis stub for: {state.query}]"
        return {"answer": answer, "citations": [{"chunk_id": r.hit.chunk_id} for r in state.reranked]}

    @staticmethod
    def _route_synthesis(state: GraphState) -> str:
        """Route to quality model for complex reasoning, fast model otherwise."""
        if state.intent.label == "complex_reasoning":
            return "quality"
        return "fast"

    # --- Public API ----------------------------------------------------------

    async def run(
        self, query: str, intent: Intent, session_id: str | None, tenant_id: str | None
    ) -> WorkflowResult:
        init = GraphState(query=query, intent=intent, session_id=session_id, tenant_id=tenant_id)
        final = await self._graph.ainvoke(init)
        return WorkflowResult(answer=final["answer"], citations=final["citations"], trace_id=init.trace_id)

    async def run_streaming(
        self, query: str, intent: Intent, session_id: str | None, tenant_id: str | None
    ) -> AsyncIterator[str]:
        """Stream tokens. LangGraph's stream API yields per-node updates; we
        flatten the synthesis-node deltas into a token stream for SSE."""
        init = GraphState(query=query, intent=intent, session_id=session_id, tenant_id=tenant_id)
        async for chunk in self._graph.astream(init, stream_mode="values"):
            if "answer" in chunk and chunk["answer"]:
                yield chunk["answer"]
