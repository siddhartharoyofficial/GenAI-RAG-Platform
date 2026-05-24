"""Ragas evaluation harness.

Wired into CI so retrieval/prompting changes cannot regress accuracy silently.
The golden dataset lives in tests/evaluation/golden.jsonl.
"""

from __future__ import annotations

import json
import pathlib

import pytest

GOLDEN = pathlib.Path(__file__).parent / "golden.jsonl"

# Thresholds the suite enforces. Drop below and CI fails.
FAITHFULNESS_MIN = 0.90
ANSWER_RELEVANCE_MIN = 0.85
CONTEXT_PRECISION_MIN = 0.80


@pytest.mark.skipif(not GOLDEN.exists(), reason="golden.jsonl not present")
def test_ragas_metrics_above_thresholds():
    from ragas import evaluate
    from ragas.metrics import answer_relevancy, context_precision, faithfulness
    from datasets import Dataset

    records = [json.loads(line) for line in GOLDEN.read_text().splitlines() if line.strip()]
    ds = Dataset.from_list(records)
    result = evaluate(ds, metrics=[faithfulness, answer_relevancy, context_precision])

    assert result["faithfulness"] >= FAITHFULNESS_MIN, result
    assert result["answer_relevancy"] >= ANSWER_RELEVANCE_MIN, result
    assert result["context_precision"] >= CONTEXT_PRECISION_MIN, result
