# Runbook

Operational guide for engineers on call. Each scenario has a symptom, a triage path, and a remediation.

## Alert: API p95 latency > 1.5s

**Symptoms.** Cloud Monitoring alert fires; latency dashboard shows the spike.

**Triage.**
1. Check semantic cache hit ratio (`custom.googleapis.com/genai_rag/cache_hit_ratio`). If it dropped, the cache layer is the cause — usually a Redis incident or a deployment that invalidated keys.
2. Check Vertex AI endpoint latency for the reranker and the synthesis models. The Cloud Trace flame graph shows which span owns the time.
3. Check AlloyDB query latency. A slow plan often indicates the HNSW index needs `REINDEX` after bulk writes.

**Remediation.**
- Cache-layer issue → confirm Memorystore HA failover state, scale memory if eviction rate is high.
- LLM endpoint issue → fail over to the secondary model (Gemini Flash) by flipping the router config flag.
- AlloyDB index issue → `REINDEX INDEX CONCURRENTLY chunks_embedding_idx;` on the replica first.

## Alert: Cache hit ratio < 20% for 15 min

**Symptoms.** Cache alert fires; downstream LLM cost rises.

**Triage.**
1. Did we just ship an embedding-model change? A new model invalidates the cache by definition; expect a 30-minute warm-up.
2. Has the input distribution shifted? Phoenix's drift dashboard shows the input embedding distribution by week.
3. Is the similarity threshold misconfigured? Confirm `CACHE_SIMILARITY_THRESHOLD` in the ConfigMap.

**Remediation.**
- Expected drift → wait it out, the cache rebuilds.
- Unexpected drift → roll back the recent embedding-model change.
- Threshold misconfig → patch the ConfigMap and roll the API.

## Incident: Hallucinations spike in production traces

**Symptoms.** Ragas faithfulness drops below 0.85 on the rolling window.

**Triage.**
1. Inspect a sample of failing traces in Phoenix. Look at the retrieved chunks vs. the answer.
2. Verify the reranker endpoint returned non-empty results. If it timed out, the pipeline degraded to RRF-only ranking — this is the most common silent cause.
3. Check for corpus changes (new docs ingested without their parent chunks).

**Remediation.**
- Reranker degradation → scale the Vertex AI endpoint up; verify min/max replicas.
- Ingestion bug → freeze new ingest, validate the chunk-parent join, replay missing parents.

## Incident: Cross-tenant data leak suspected

**This is a security incident.** Treat as P0.

1. Identify the affected tenants from the trace logs.
2. Confirm whether the leak happened at the retrieval layer (`SELECT` returned other-tenant rows) or the cache layer (semantic cache key was tenant-agnostic).
3. Quarantine: flip the global feature flag `disable_cache_reads=true` and `force_strict_tenant_filter=true`.
4. Snapshot AlloyDB state for forensic analysis.
5. Notify per the incident communication plan.

**Common cause.** A new code path bypassing the `tenant_id` filter. Add a regression test before re-enabling.

## Procedure: Rotate the deploy service account key

Workload Identity Federation eliminates the long-lived key, so this is a sanity check rather than a rotation:

```bash
gcloud iam service-accounts keys list --iam-account=github-deploy@${PROJECT_ID}.iam.gserviceaccount.com
# Confirm only the system-managed key exists.
```

If a user-managed key exists, delete it. CI should authenticate via WIF only.

## Procedure: Force-evict the semantic cache

```bash
# Connect to Memorystore via a bastion or the in-cluster client.
redis-cli -h $REDIS_HOST -a $REDIS_AUTH FLUSHDB
```

This is destructive. Use only when you need to invalidate every cached answer (model change, contractual data deletion, etc.).

## Procedure: AlloyDB failover

AlloyDB primary-to-replica failover is initiated via the API:

```bash
gcloud alloydb clusters failover genai-rag-prod-alloydb --region us-central1
```

The pgvector HNSW index replicates with the data, so search works immediately on the new primary. Expect 30-90 seconds of write unavailability.

## Quarterly chores

- Review IAM bindings (`gcloud projects get-iam-policy $PROJECT_ID`). Remove anything stale.
- Re-evaluate the model router thresholds against the last quarter of production traces.
- Run a chaos drill: kill the Vertex AI endpoint, verify the degraded path works.
- Confirm AlloyDB backup retention and run a restore drill to a scratch cluster.
