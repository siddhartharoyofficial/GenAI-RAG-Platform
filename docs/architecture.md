# Architecture deep dive

A longer-form walkthrough complementing the root [`ARCHITECTURE.md`](../ARCHITECTURE.md). This document is the reference for new engineers joining the project.

## Layers, end to end

### 1. Ingress
External traffic terminates at a global HTTPS Load Balancer fronted by Cloud Armor. The WAF enforces an OWASP top-10 ruleset and applies per-IP rate limits (100 rpm with a 10-minute ban for offenders). TLS termination happens at the LB; everything inside the VPC is mTLS via Workload Identity short-lived tokens.

### 2. API service (GKE Autopilot)
The main FastAPI service owns the request lifecycle. Workload Identity binds the Kubernetes ServiceAccount to a GCP ServiceAccount with the minimum roles needed: `aiplatform.user`, `redis.editor`, `alloydb.databaseUser`, `secretmanager.secretAccessor`, plus the observability log/trace/metric writer roles. No long-lived credentials are mounted into pods.

### 3. Embedding + cache probe
The API embeds the incoming query via `text-embedding-004` on Vertex AI, then probes the semantic cache. The cache is a Memorystore Redis instance with a RediSearch vector index. We use cosine similarity with a 0.92 threshold, scoped by `tenant_id` so multi-tenant deployments do not cross-leak. TTL is 1 hour by default, tunable per workload.

### 4. Intent routing
On cache miss, the API calls the intent router (Gemini 2.5 Flash via Vertex AI). The router is deployed as a Cloud Run service for two reasons: it's stateless, latency-sensitive, and scales to zero off-peak; and isolating it from the main API lets us experiment with router models without touching the orchestration deployment.

The router returns one of four labels and an optional rewritten query. Confidence below 0.5 falls through to `simple_lookup` as a safe default.

### 5. Retrieval (hybrid)
The retrieval node runs two concurrent searches against AlloyDB:

- **Dense.** pgvector HNSW index, cosine distance, k=50, with metadata pre-filters (tenant, document_type, jurisdiction, date_range) pushed into the WHERE clause so filtering happens during traversal rather than post-hoc.
- **Sparse.** Postgres FTS over the same chunks using `tsvector` and `plainto_tsquery`.

Both results lists pass through Reciprocal Rank Fusion (k=60), which gives us a single ranked list without weight tuning per query type.

### 6. Reranking
The top-50 fused candidates go to a Vertex AI endpoint hosting Cohere Rerank 3 multilingual. The endpoint returns top-5 by relevance. This is the single most accuracy-impactful step in the pipeline and is non-negotiable.

### 7. Parent chunk expansion
Each surviving top-5 child chunk (~128 tokens) gets expanded to its parent (~512 tokens) before being passed to the synthesis LLM. This preserves the precision of matching on small chunks while giving the model enough surrounding context to avoid the "right paragraph, wrong interpretation" failure mode.

### 8. Synthesis
LangGraph routes to one of two synthesis paths based on the intent:

- `simple_lookup` and `agentic_tool_use` → Gemini 2.5 Flash
- `complex_reasoning` → Claude 3.5 Sonnet via Vertex AI Model Garden

The response streams token-by-token via Server-Sent Events. The synthesis prompt includes citation anchors so the application layer can wire the cited chunks back to source documents in the UI.

### 9. Write-back
After the response streams, two async tasks fire (non-blocking):

- **Cache write.** Embedding + answer + citations + trace_id, with the configured TTL.
- **Memory update.** Append the user turn and assistant turn to the durable session store in AlloyDB and refresh the hot-window cache in Redis.

### 10. Observability
Every span exports to Cloud Trace via OpenTelemetry. Custom metrics (cache hit ratio, retrieval recall@k from the eval suite, Ragas faithfulness/answer-relevance/context-precision) ship to Managed Prometheus. Arize Phoenix sits on the application layer for LLM-specific observability (TTFT, token budgets, drift on input embeddings).

## Data model

```
documents
  id, title, source_uri, tenant_id, jurisdiction, document_type, ingested_at

parent_chunks
  parent_id, document_id, text, position, token_count

chunks
  chunk_id, parent_id, document_id, tenant_id, text, position,
  embedding vector(768),  -- pgvector
  fts tsvector,           -- BM25
  metadata jsonb

session_turns
  session_id, role, content, ts, tenant_id
```

Indices:
- `chunks` HNSW on `embedding` (m=16, ef_construction=128).
- `chunks` GIN on `fts`.
- `chunks` btree on `(tenant_id, document_type)` for filter push-down.
- `session_turns` btree on `(session_id, ts desc)`.

## Failure modes and mitigations

| Failure | Mitigation |
|---|---|
| Vertex AI embedding timeout | 1s deadline + retry once with exponential backoff. Fall through to no-cache path. |
| Redis unavailable | Circuit breaker opens; bypass cache layer entirely. Surface degraded-mode header. |
| AlloyDB primary lag | Replica reads handle retrieval. Writes block briefly; we surface 503 only if both are down. |
| Reranker endpoint timeout | Drop to top-5 by RRF score. Log the degradation and emit a `degraded_rerank` metric. |
| LLM 429 | Retry once with backoff; on second failure, return cache-only fallback or graceful "try again" message. |
| Cross-tenant leak | Defense in depth: tenant filter at SQL layer, JWT scope check at API layer, audit log of any retrieval where the tenant didn't match the session. |

## What we deliberately did not build

- A custom embedding model. The cost of fine-tuning vs. the marginal accuracy lift didn't justify it at this stage. Revisit after launch with real production traces.
- Speculative decoding on the synthesis LLM. Vertex AI doesn't expose it yet for the models we use; revisit when it ships.
- Active-active multi-region. The complexity tax on a single-region p95 < 1.5s target wasn't worth it. We documented the path forward in the open questions section of the root ARCHITECTURE.md.
