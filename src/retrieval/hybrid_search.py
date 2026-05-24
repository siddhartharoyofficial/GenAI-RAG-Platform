"""Hybrid retrieval — dense (pgvector HNSW) + sparse (BM25) with RRF fusion.

Why hybrid:
    Pure vector search fails on exact-match content (SKUs, error codes, statute
    references). BM25 catches what vectors miss. Reciprocal Rank Fusion gives us
    a single ranked list without tuning weights per query type.

Why pgvector and not a dedicated vector DB:
    AlloyDB's pgvector with HNSW indexing pushes metadata filters into the
    traversal itself, which eliminates an entire class of cross-tenant leakage
    risks that naive vector stores suffer from. Operating one primitive instead
    of two is a real engineering win.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any

import psycopg
import structlog

from src.common.config import Settings
from src.observability.embeddings import embed_text

log = structlog.get_logger()


@dataclass(slots=True)
class RetrievalHit:
    chunk_id: str
    text: str
    parent_text: str  # expanded parent chunk
    score: float
    metadata: dict[str, Any]


class HybridRetriever:
    """Combines pgvector dense search and BM25 FTS via RRF."""

    RRF_K = 60  # standard RRF constant

    def __init__(self, cfg: Settings, pool: psycopg.AsyncConnection) -> None:
        self._cfg = cfg
        self._pool = pool

    async def search(
        self,
        query: str,
        tenant_id: str | None = None,
        top_k: int | None = None,
    ) -> list[RetrievalHit]:
        top_k = top_k or self._cfg.retrieval_top_k

        # Fire dense and sparse searches concurrently.
        dense_task = asyncio.create_task(self._dense_search(query, tenant_id, top_k))
        sparse_task = asyncio.create_task(self._sparse_search(query, tenant_id, top_k))
        dense, sparse = await asyncio.gather(dense_task, sparse_task)

        fused = self._reciprocal_rank_fusion(dense, sparse, top_k=top_k)
        return fused

    async def _dense_search(self, query: str, tenant_id: str | None, k: int) -> list[RetrievalHit]:
        embedding = await embed_text(query)
        sql = """
            SELECT c.chunk_id, c.text, p.text AS parent_text, c.metadata,
                   1 - (c.embedding <=> %s::vector) AS score
            FROM chunks c
            JOIN parent_chunks p ON p.parent_id = c.parent_id
            WHERE (%s::text IS NULL OR c.tenant_id = %s)
            ORDER BY c.embedding <=> %s::vector
            LIMIT %s
        """
        async with self._pool.cursor() as cur:
            await cur.execute(sql, (embedding.tolist(), tenant_id, tenant_id, embedding.tolist(), k))
            rows = await cur.fetchall()
        return [
            RetrievalHit(chunk_id=r[0], text=r[1], parent_text=r[2], score=r[4], metadata=r[3]) for r in rows
        ]

    async def _sparse_search(self, query: str, tenant_id: str | None, k: int) -> list[RetrievalHit]:
        sql = """
            SELECT c.chunk_id, c.text, p.text AS parent_text, c.metadata,
                   ts_rank_cd(c.fts, plainto_tsquery('english', %s)) AS score
            FROM chunks c
            JOIN parent_chunks p ON p.parent_id = c.parent_id
            WHERE c.fts @@ plainto_tsquery('english', %s)
              AND (%s::text IS NULL OR c.tenant_id = %s)
            ORDER BY score DESC
            LIMIT %s
        """
        async with self._pool.cursor() as cur:
            await cur.execute(sql, (query, query, tenant_id, tenant_id, k))
            rows = await cur.fetchall()
        return [
            RetrievalHit(chunk_id=r[0], text=r[1], parent_text=r[2], score=r[4], metadata=r[3]) for r in rows
        ]

    @classmethod
    def _reciprocal_rank_fusion(
        cls,
        dense: list[RetrievalHit],
        sparse: list[RetrievalHit],
        top_k: int,
    ) -> list[RetrievalHit]:
        """RRF score = sum(1 / (k + rank)) across input lists."""
        scored: dict[str, tuple[RetrievalHit, float]] = {}
        for rank, hit in enumerate(dense):
            scored[hit.chunk_id] = (hit, 1.0 / (cls.RRF_K + rank + 1))
        for rank, hit in enumerate(sparse):
            prev = scored.get(hit.chunk_id)
            inc = 1.0 / (cls.RRF_K + rank + 1)
            if prev is None:
                scored[hit.chunk_id] = (hit, inc)
            else:
                scored[hit.chunk_id] = (prev[0], prev[1] + inc)

        ranked = sorted(scored.values(), key=lambda x: x[1], reverse=True)[:top_k]
        out = []
        for hit, score in ranked:
            hit.score = score
            out.append(hit)
        return out
