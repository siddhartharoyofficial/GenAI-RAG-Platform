"""Cross-encoder reranker — top 50 → top 5.

This step is non-negotiable. Skipping it is the single most common reason RAG
systems hallucinate in production. The reranker filters retrieval noise so the
LLM context window is small, precise, and faithful.

Default model: Cohere Rerank 3 multilingual on a Vertex AI endpoint.
Fallback: BGE-Reranker-v2-m3 on a self-hosted endpoint.
"""

from __future__ import annotations

from dataclasses import dataclass

import structlog
from google.cloud import aiplatform

from src.common.config import Settings
from src.retrieval.hybrid_search import RetrievalHit

log = structlog.get_logger()


@dataclass(slots=True)
class RerankedHit:
    hit: RetrievalHit
    rerank_score: float


class CrossEncoderReranker:
    def __init__(self, cfg: Settings) -> None:
        self._cfg = cfg
        aiplatform.init(project=cfg.project_id, location=cfg.region)
        self._endpoint = aiplatform.Endpoint(cfg.reranker_endpoint_id)

    async def rerank(
        self, query: str, hits: list[RetrievalHit], top_k: int | None = None
    ) -> list[RerankedHit]:
        top_k = top_k or self._cfg.rerank_top_k
        if not hits:
            return []

        # Vertex endpoint expects {"query": ..., "documents": [...]} for Cohere Rerank.
        instances = [
            {
                "query": query,
                "documents": [h.text for h in hits],
                "top_n": top_k,
            }
        ]
        response = await self._endpoint.predict_async(instances=instances)

        # Cohere returns sorted indices + relevance scores.
        results = response.predictions[0]["results"]
        out = []
        for r in results[:top_k]:
            idx = r["index"]
            out.append(RerankedHit(hit=hits[idx], rerank_score=float(r["relevance_score"])))

        log.info("rerank.done", input=len(hits), output=len(out))
        return out
