"""Unit tests for the intent router parsing logic."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from src.router.intent_router import IntentRouter


def test_loose_parse_handles_fenced_json():
    text = """```json
    {"label": "complex_reasoning", "confidence": 0.87}
    ```"""
    parsed = IntentRouter._loose_parse(text)
    assert parsed["label"] == "complex_reasoning"
    assert parsed["confidence"] == pytest.approx(0.87)


def test_loose_parse_handles_plain_json():
    text = '{"label": "simple_lookup", "confidence": 0.95}'
    parsed = IntentRouter._loose_parse(text)
    assert parsed["label"] == "simple_lookup"


def test_loose_parse_raises_on_invalid():
    with pytest.raises(json.JSONDecodeError):
        IntentRouter._loose_parse("not json at all")
