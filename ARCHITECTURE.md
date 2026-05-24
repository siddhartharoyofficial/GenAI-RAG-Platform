# Architecture

This document explains the design decisions behind the GenAI RAG platform — what we picked, what we rejected, and why. It is intentionally opinionated because most public RAG references over-index on a happy-path single-query demo and ignore what production traffic actually looks like.

## 1. Problem statement

Vanilla RAG fails under two pressures:

1. **Tail latency** balloons past 8 seconds during traffic spikes because every query traverses the full retrieve → rerank → generate pipeline.
2. **Hallucinations** surface when retrieval returns chunks that are semantically close but factually wrong, and the LLM has no signal to detect the mismatch.

Both failure modes trace back to the same root cause: treating every incoming query as if it needs the full pipeline.

## 2. The architectural inversion

The LLM call is the most expensive resource in the system — in latency, cost, and failure-mode surface area. Treat it as the last resort, not the default.

That single inversion implies two decision layers upstream of the LLM:

- A **semantic cache** that answers from prior responses when vector similarity crosses a threshold (default 0.92 cosine).
- An **intent router** that classifies the query and selects the cheapest execution path that can still satisfy it.

Everything else in the system serves one of these two layers.

## 3. Request lifecycle

A request enters the system through the API Gateway, where Cloud Armor enforces WAF rules and the Load Balancer pools connections to GKE. The API service first embeds the incoming query using `text-embedding-004` on Vertex AI, then probes Memorystore for a vector match above the threshold. On hit, the cached response streams back in well under 10 ms.

On miss, the query reaches the intent router. The router is a small classification call against Gemini 2.5 Flash with a tight prompt that returns one of four labels: `simple_lookup`, `complex_reasoning`, `agentic_tool_use`, or `clarification_needed`. Each label dispatches to a different LangGraph workflow with different retrieval depth, different reranker top-k, and a different final LLM.

Retrieval is hybrid: a dense HNSW search over `pgvector` in AlloyDB and a sparse BM25 search over the same documents, fused via Reciprocal Rank Fusion. The top 50 fused candidates pass to a Vertex AI endpoint hosting a cross-encoder reranker (Cohere Rerank 3 or BGE-Reranker-v2-m3), which truncates to the top 5. Each survivor's child chunk gets expanded to its parent (128 → 512 tokens) to give the LLM enough surrounding context.

The final synthesis call goes to either Gemini 2.5 Flash (most traffic) or Claude 3.5 Sonnet via Vertex AI Model Garden (high-stakes traffic). The response streams back token-by-token via SSE while an async write-back populates the semantic cache and updates session memory.

## 4. Component selections and rationale

### Caching: Memorystore for Redis with RediSearch
Exact key matching is wrong for natural language. We embed the query and compare it against a TTL-indexed vector store of prior question-response pairs. Memorystore is the managed path; RediSearch ships the vector similarity operator. The same Redis instance also hosts the windowed conversation memory cache, so we avoid a second hop for hot-path session reads.

### Vector store: AlloyDB with pgvector
We considered Qdrant on GKE and Vertex AI Vector Search. Qdrant is excellent but requires us to operate stateful workloads we'd rather not. Vertex AI Vector Search is fully managed but its metadata filtering is limited and its update latency is too high for write-through indexing. AlloyDB with `pgvector` and HNSW indexing gives us push-down metadata filters (critical for multi-tenant isolation), strong recall-latency tradeoffs, and one operational primitive for both the vector store and the relational session memory.

### Embedding model: text-embedding-004 on Vertex AI
Native Google Cloud, 8k-token context, multilingual, and the cost profile works at scale. For multilingual-heavy workloads we'd swap in Cohere Embed v3.

### Orchestration: LangGraph
We need stateful workflows with cycles — clarification loops, retry-on-failure with backoff, human-in-the-loop. LlamaIndex Workflows handles simpler async DAGs. Bare `asyncio` is a trap; the first failed trace replay teaches you why.

### Reranker: Cohere Rerank 3 on a Vertex AI endpoint
This step is non-negotiable. Skipping it is the single most common reason RAG systems hallucinate in production. The reranker filters noise from the top-50 candidate set down to a precision-optimized top-5, which simultaneously cuts cost, reduces latency, and improves faithfulness.

### API Gateway: GCP Load Balancer + Cloud Armor + API Gateway
Rate limiting, JWT propagation, connection pooling, WAF, and circuit breaking. Do not put LLM endpoints directly on the public internet.

### Observability: Cloud Trace + Managed Prometheus + Arize Phoenix
Cloud Trace gives us free distributed tracing across all GCP services. Managed Prometheus handles application metrics. Arize Phoenix sits at the application layer to track TTFT, Ragas faithfulness/answer-relevance/context-precision, and data drift. Without the last bucket, you fly blind, and drift will eat your accuracy three weeks after launch.

## 5. Accuracy strategy

Prompt engineering helps at the margin. Real accuracy gains come from the retrieval and ranking stack.

**Hybrid search.** Pure vector search fails predictably on exact-match content: serial numbers, SKUs, policy codes, statute references, error codes. Combining HNSW dense retrieval with BM25 sparse keyword search and fusing via Reciprocal Rank Fusion lifts recall@10 by 15-25% on enterprise corpora.

**Parent-child chunking.** Embed small chunks (~128 tokens) so vector similarity stays precise. When a child matches, expand the retrieval to its parent (~512 tokens) before passing to the LLM. This preserves matching precision while giving the model enough surrounding context to avoid the "right paragraph, wrong interpretation" failure mode.

**Two-stage reranking.** Top 50 from hybrid search → cross-encoder reranker → top 5. First stage optimizes recall; second optimizes precision.

**Metadata pre-filtering.** Push tenant_id, document_type, jurisdiction, and date_range filters into the HNSW traversal itself, not as a post-filter. This speeds retrieval and eliminates cross-tenant leakage risks.

**Closing the loop.** Ragas evaluations (faithfulness, answer relevance, context precision) wired into CI so retrieval changes cannot regress accuracy silently between deployments.

## 6. Latency strategy

Accuracy is a model problem; latency is an infrastructure problem. Treat them separately.

**Semantic caching at egress.** First move, cheapest. In real workloads with repetitive query patterns (customer support, internal knowledge bases) this serves 30-50% of traffic with sub-10ms responses.

**Token streaming.** Stream LLM tokens via SSE. Total generation time may not change, but TTFT drops below 200ms, which is what users perceive as "fast."

**Asynchronous pipeline execution.** Vector retrieval, BM25 search, memory lookup, and metadata permission checks run concurrently via `asyncio.gather()`. A 1.2-second sequential pipeline lands at 400-500ms parallelized.

**Connection pooling.** Persistent pools to AlloyDB, Redis, and Vertex AI endpoints. Cold TLS handshakes on every call are a silent latency tax.

**Edge-aware routing.** The gateway and cache layer deploy in the same region as the largest user base. A 60ms cross-region floor is something no application-layer optimization can recover.

## 7. Multi-model LLM strategy

Picking a single LLM is the most common architectural mistake. The router classifies and dispatches:

- **Gemini 2.5 Flash** handles intent classification, cache disambiguation, query rewriting, simple data extraction, and structured tool-argument generation. TTFT under 300ms and 1M-token context make it the right default for the 80% of queries that are not actually hard.
- **Claude 3.5 Sonnet (via Vertex AI Model Garden) or GPT-4o** handles the remaining 20% — multi-step reasoning, final synthesis with citations, code generation, and any output where a wrong answer carries real business consequence.

The router itself is a small supervised classification problem you can fine-tune on logged production traces within weeks of launch.

## 8. Tradeoffs and what we explicitly rejected

- **Vertex AI Vector Search.** Considered and rejected for the primary vector store because of weaker metadata filtering and higher write-path latency. Reasonable choice for read-only enterprise search; wrong choice for write-through indexing.
- **Pinecone.** Excellent product, but we wanted the vector store and the relational session store on the same operational primitive. AlloyDB wins on that axis.
- **Self-hosted Qdrant on GKE.** Stateful workload ops cost more engineering hours than we want to spend in a reference architecture.
- **A single LLM for everything.** Already covered above — collapses on either latency or cost.
- **Skipping the reranker.** Saves one network call and torches accuracy. Never the right tradeoff.

## 9. Open questions / future work

- Fine-tuning a custom embedding model on the corpus to lift retrieval beyond what off-the-shelf embeddings achieve.
- Speculative decoding for the synthesis LLM to drop generation latency another 30-40%.
- Multi-region active-active with regional cache replication for global p95.
- Adversarial robustness testing on the intent router (prompt injection paths into routing).
