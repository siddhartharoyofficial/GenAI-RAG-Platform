-- Schema bootstrap for AlloyDB. Idempotent.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS documents (
    id              UUID PRIMARY KEY,
    title           TEXT NOT NULL,
    source_uri      TEXT,
    tenant_id       TEXT NOT NULL,
    jurisdiction    TEXT,
    document_type   TEXT,
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS documents_tenant_idx
    ON documents (tenant_id, document_type);

CREATE TABLE IF NOT EXISTS parent_chunks (
    parent_id       UUID PRIMARY KEY,
    document_id     UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    text            TEXT NOT NULL,
    position        INT NOT NULL,
    token_count     INT NOT NULL
);

CREATE INDEX IF NOT EXISTS parent_chunks_doc_idx
    ON parent_chunks (document_id, position);

CREATE TABLE IF NOT EXISTS chunks (
    chunk_id        UUID PRIMARY KEY,
    parent_id       UUID NOT NULL REFERENCES parent_chunks(parent_id) ON DELETE CASCADE,
    document_id     UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    tenant_id       TEXT NOT NULL,
    text            TEXT NOT NULL,
    position        INT NOT NULL,
    embedding       vector(768),
    fts             tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED,
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- HNSW index for dense ANN.
CREATE INDEX IF NOT EXISTS chunks_embedding_idx
    ON chunks USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 128);

-- GIN index for sparse BM25 / FTS.
CREATE INDEX IF NOT EXISTS chunks_fts_idx
    ON chunks USING GIN (fts);

-- Tenant filter push-down.
CREATE INDEX IF NOT EXISTS chunks_tenant_idx
    ON chunks (tenant_id, document_id);

CREATE TABLE IF NOT EXISTS session_turns (
    id              BIGSERIAL PRIMARY KEY,
    session_id      TEXT NOT NULL,
    role            TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content         TEXT NOT NULL,
    ts              TIMESTAMPTZ NOT NULL DEFAULT now(),
    tenant_id       TEXT
);

CREATE INDEX IF NOT EXISTS session_turns_sid_ts_idx
    ON session_turns (session_id, ts DESC);
