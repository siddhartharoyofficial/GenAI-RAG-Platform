"""Semantic cache backed by Memorystore Redis with RediSearch vector index.

Why semantic and not exact-key:
    Natural-language queries that are paraphrases of each other should hit the
    same cache entry. Exact key matching misses 80% of real-world hit potential.

Lookup path:
    1. Embed the incoming query.
    2. Run a KNN search against the vector index, scoped to tenant_id.
    3. If the top match exceeds the similarity threshold, return its payload.

Write path:
    Hash the query, store {embedding, answer, citations, trace_id, ts} with TTL.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any

import redis.asyncio as redis
import structlog

from src.common.config import Settings
from src.observability.embeddings import embed_text

log = structlog.get_logger()


@dataclass(slots=True)
class CachedResult:
    answer: str
    citations: list[dict[str, Any]]
    trace_id: str


class SemanticCache:
    """Thin wrapper around Redis with vector similarity lookup."""

    INDEX_NAME = "idx:semantic_cache"

    def __init__(self, client: redis.Redis, threshold: float, ttl: int) -> None:
        self._client = client
        self._threshold = threshold
        self._ttl = ttl

    @classmethod
    async def connect(cls, cfg: Settings) -> "SemanticCache":
        client = redis.Redis(
            host=cfg.redis_host,
            port=cfg.redis_port,
            password=cfg.redis_auth or None,
            ssl=True,
            decode_responses=False,
            socket_connect_timeout=1.0,
            socket_timeout=1.0,
        )
        await client.ping()
        # Idempotent index creation handled by an init job in CI/CD.
        return cls(client, cfg.cache_similarity_threshold, cfg.cache_ttl_seconds)

    async def ping(self) -> None:
        await self._client.ping()

    async def close(self) -> None:
        await self._client.aclose()

    @staticmethod
    def _key(query: str, tenant_id: str | None) -> str:
        salt = tenant_id or "global"
        h = hashlib.sha256(f"{salt}::{query}".encode()).hexdigest()[:16]
        return f"qa:{salt}:{h}"

    async def lookup(self, query: str, tenant_id: str | None = None) -> CachedResult | None:
        """Return the cached result for a semantically-similar query, or None."""
        embedding = await embed_text(query)
        # FT.SEARCH with KNN; in production we use the proper RediSearch client.
        # Pseudo-call retained here for clarity:
        try:
            hits = await self._client.execute_command(
                "FT.SEARCH",
                self.INDEX_NAME,
                f"(@tenant_id:{{{tenant_id or 'global'}}})=>[KNN 1 @vec $vec AS score]",
                "PARAMS", "2", "vec", embedding.tobytes(),
                "SORTBY", "score",
                "DIALECT", "2",
                "LIMIT", "0", "1",
            )
        except redis.ResponseError as exc:
            log.warning("cache.lookup_failed", error=str(exc))
            return None

        if not hits or len(hits) < 3:
            return None
        # hits layout: [count, key, [field, value, ...]]
        score = float(hits[2][1])
        if score < self._threshold:
            return None
        payload = json.loads(hits[2][3])
        log.info("cache.hit", score=score, tenant=tenant_id)
        return CachedResult(**payload)

    async def write(self, query: str, result: Any, tenant_id: str | None = None) -> None:
        """Best-effort write-back. Failures are logged, not raised."""
        try:
            embedding = await embed_text(query)
            key = self._key(query, tenant_id)
            payload = json.dumps({
                "answer": result.answer,
                "citations": result.citations,
                "trace_id": result.trace_id,
            })
            await self._client.hset(key, mapping={
                "vec": embedding.tobytes(),
                "payload": payload,
                "tenant_id": tenant_id or "global",
            })
            await self._client.expire(key, self._ttl)
        except Exception as exc:  # noqa: BLE001
            log.warning("cache.write_failed", error=str(exc))
