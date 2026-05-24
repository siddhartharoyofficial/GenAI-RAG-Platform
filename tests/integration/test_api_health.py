"""Integration test for the API health and readiness endpoints.

Run against a locally-composed stack (docker compose up).
"""

from __future__ import annotations

import os

import httpx
import pytest

BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:8080")


@pytest.mark.asyncio
async def test_healthz_returns_ok():
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await client.get(f"{BASE_URL}/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
