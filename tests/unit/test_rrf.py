"""Unit tests for Reciprocal Rank Fusion in the hybrid retriever."""

from __future__ import annotations

from src.retrieval.hybrid_search import HybridRetriever, RetrievalHit


def _hit(cid: str, score: float = 0.0) -> RetrievalHit:
    return RetrievalHit(chunk_id=cid, text=cid, parent_text=cid, score=score, metadata={})


def test_rrf_ranks_chunks_present_in_both_lists_higher():
    dense = [_hit("a"), _hit("b"), _hit("c")]
    sparse = [_hit("c"), _hit("a"), _hit("d")]

    fused = HybridRetriever._reciprocal_rank_fusion(dense, sparse, top_k=4)
    ids = [h.chunk_id for h in fused]
    # 'a' is rank 1 in dense and rank 2 in sparse — highest combined.
    # 'c' is rank 3 in dense, rank 1 in sparse — second highest.
    assert ids[0] == "a"
    assert ids[1] == "c"


def test_rrf_returns_unique_chunks_in_correct_count():
    dense = [_hit("a"), _hit("b")]
    sparse = [_hit("b"), _hit("c")]
    fused = HybridRetriever._reciprocal_rank_fusion(dense, sparse, top_k=10)
    assert sorted(h.chunk_id for h in fused) == ["a", "b", "c"]
