"""Session memory — two-tier: Redis for hot window, AlloyDB for durable history.

Hot path reads (last N turns) come from Redis, sub-millisecond.
Long-term recall (`semantic search across conversation history`) goes to AlloyDB.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import psycopg
import redis.asyncio as redis


@dataclass(slots=True)
class Turn:
    role: str  # "user" | "assistant"
    content: str
    ts: float


class SessionMemory:
    """Conversation memory with a write-through cache and durable backing store."""

    WINDOW_SIZE = 20  # turns kept hot in Redis

    def __init__(self, redis_client: redis.Redis, pg_conn: psycopg.AsyncConnection) -> None:
        self._redis = redis_client
        self._pg = pg_conn

    async def append(self, session_id: str, turn: Turn) -> None:
        # Hot tier
        key = f"sess:{session_id}"
        await self._redis.lpush(key, json.dumps({"role": turn.role, "content": turn.content, "ts": turn.ts}))
        await self._redis.ltrim(key, 0, self.WINDOW_SIZE - 1)
        await self._redis.expire(key, 3600)
        # Durable tier
        async with self._pg.cursor() as cur:
            await cur.execute(
                "INSERT INTO session_turns(session_id, role, content, ts) VALUES (%s, %s, %s, to_timestamp(%s))",
                (session_id, turn.role, turn.content, turn.ts),
            )

    async def recent_turns(self, session_id: str, n: int = 10) -> list[Turn]:
        key = f"sess:{session_id}"
        raw = await self._redis.lrange(key, 0, n - 1)
        out = []
        for item in raw:
            payload = json.loads(item)
            out.append(Turn(role=payload["role"], content=payload["content"], ts=payload["ts"]))
        return list(reversed(out))
