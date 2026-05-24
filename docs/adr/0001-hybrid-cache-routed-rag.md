# ADR 0001: Hybrid semantic-cache and routed multi-agent RAG

- Status: Accepted
- Date: 2026-05-25
- Authors: Siddhartha Roy

## Context

Vanilla RAG implementations break under production conditions on two axes: tail latency past 8 seconds during traffic spikes, and hallucinations from semantically close but factually wrong retrievals. The team has prior production scars on both.

## Decision

We adopt a hybrid semantic-cache and routed multi-agent RAG architecture with three explicit decision points upstream of the LLM:

1. A semantic cache that answers from prior responses when cosine similarity ≥ 0.92.
2. An intent router (Gemini 2.5 Flash) that selects one of four execution paths.
3. A multi-model synthesis layer that uses Gemini 2.5 Flash for ~80% of traffic and Claude 3.5 Sonnet (via Vertex AI Model Garden) for ~20% requiring frontier reasoning.

Retrieval is hybrid (dense pgvector + BM25 FTS) fused via Reciprocal Rank Fusion, followed by a non-negotiable cross-encoder reranker step before parent-chunk expansion.

## Consequences

**Positive.**
- Cache hits serve a substantial fraction of traffic at sub-10ms TTFT.
- Multi-model routing keeps p95 latency low without sacrificing accuracy on the hard 20%.
- Hybrid search lifts recall@10 by 15-25% on enterprise corpora over pure vector search.

**Negative.**
- More moving parts to operate. The intent router becomes a critical dependency.
- Multi-model means multiple SDK integrations and quota relationships to manage.

**Mitigations.**
- Each layer has a documented degraded-mode path (skip cache, skip reranker, drop to single model).
- Observability is wired into every span so we can see where time goes in real time.

## Alternatives considered

**Single-model, no router, no cache.** Simpler but anchors on either cost (GPT-4o everywhere) or accuracy (Gemini Flash everywhere). Rejected.

**Vertex AI Vector Search as the primary vector store.** Fully managed, but weaker metadata filtering and higher write-path latency. Rejected; we'd need a second store for relational session memory anyway.

**Skip the reranker.** Saves one network call and torches accuracy. Rejected as a non-starter.
