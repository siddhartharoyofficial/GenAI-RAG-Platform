"""Intent router — classify the query into a retrieval/generation strategy.

Why a small dedicated model:
    A 1B-param classifier wrapped around Gemini 2.5 Flash gives us TTFT < 300ms
    on routing decisions. Anchoring the entire pipeline on a frontier model just
    to ask "is this a simple lookup?" is wasteful.

Outputs:
    Intent("simple_lookup" | "complex_reasoning" | "agentic_tool_use" | "clarification_needed")
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

import structlog
from google import genai
from google.genai import types

from src.common.config import Settings

log = structlog.get_logger()

IntentLabel = Literal["simple_lookup", "complex_reasoning", "agentic_tool_use", "clarification_needed"]


@dataclass(slots=True)
class Intent:
    label: IntentLabel
    confidence: float
    rewritten_query: str | None = None


_ROUTER_PROMPT = """You are an intent classifier for a retrieval pipeline.

Classify the user query into exactly one of:
  - simple_lookup: a single factual question answerable from one or two passages
  - complex_reasoning: multi-hop synthesis across multiple passages or sources
  - agentic_tool_use: requires calling tools, APIs, or executing actions
  - clarification_needed: the query is too vague or ambiguous to answer well

Return JSON: {"label": "<one of the four>", "confidence": <0..1>, "rewritten_query": "<optional rewrite>"}

Query: {query}
"""


class IntentRouter:
    """Wraps the Vertex AI Gemini call. Keep this class boring and fast."""

    def __init__(self, cfg: Settings) -> None:
        self._client = genai.Client(vertexai=True, project=cfg.project_id, location=cfg.region)
        self._model = cfg.router_model

    async def classify(self, query: str) -> Intent:
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=_ROUTER_PROMPT.format(query=query),
            config=types.GenerateContentConfig(
                temperature=0.0,
                max_output_tokens=128,
                response_mime_type="application/json",
            ),
        )
        try:
            data = response.parsed if hasattr(response, "parsed") else self._loose_parse(response.text)
            return Intent(
                label=data.get("label", "simple_lookup"),
                confidence=float(data.get("confidence", 0.5)),
                rewritten_query=data.get("rewritten_query"),
            )
        except Exception as exc:  # noqa: BLE001
            log.warning("router.parse_failed", error=str(exc))
            return Intent(label="simple_lookup", confidence=0.0)

    @staticmethod
    def _loose_parse(text: str) -> dict:
        import json
        # Strip fenced blocks if the model wrapped JSON in them.
        cleaned = text.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        return json.loads(cleaned)
