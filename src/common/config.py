"""Centralized settings — loaded from env, validated by Pydantic."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration.

    Values come from environment variables. In GKE we mount Secret Manager
    references via the Secret Store CSI driver; in Cloud Run we use direct
    Secret Manager bindings.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # GCP context
    project_id: str = Field(..., alias="GCP_PROJECT_ID")
    region: str = Field("us-central1", alias="GCP_REGION")

    # Cache
    redis_host: str = Field(..., alias="REDIS_HOST")
    redis_port: int = Field(6379, alias="REDIS_PORT")
    redis_auth: str = Field("", alias="REDIS_AUTH")
    cache_similarity_threshold: float = Field(0.92, alias="CACHE_SIMILARITY_THRESHOLD")
    cache_ttl_seconds: int = Field(3600, alias="CACHE_TTL_SECONDS")

    # AlloyDB
    alloydb_host: str = Field(..., alias="ALLOYDB_HOST")
    alloydb_port: int = Field(5432, alias="ALLOYDB_PORT")
    alloydb_database: str = Field("ragdb", alias="ALLOYDB_DATABASE")
    alloydb_user: str = Field("postgres", alias="ALLOYDB_USER")
    alloydb_password_secret: str = Field(..., alias="ALLOYDB_PASSWORD_SECRET")

    # Vertex AI / models
    embedding_model: str = Field("text-embedding-004", alias="EMBEDDING_MODEL")
    router_model: str = Field("gemini-2.5-flash", alias="ROUTER_MODEL")
    synthesis_fast_model: str = Field("gemini-2.5-flash", alias="SYNTH_FAST_MODEL")
    synthesis_quality_model: str = Field("claude-3-5-sonnet@20241022", alias="SYNTH_QUALITY_MODEL")
    reranker_endpoint_id: str = Field(..., alias="RERANKER_ENDPOINT_ID")

    # Retrieval
    retrieval_top_k: int = Field(50, alias="RETRIEVAL_TOP_K")
    rerank_top_k: int = Field(5, alias="RERANK_TOP_K")
    child_chunk_tokens: int = Field(128, alias="CHILD_CHUNK_TOKENS")
    parent_chunk_tokens: int = Field(512, alias="PARENT_CHUNK_TOKENS")

    # Observability
    otel_exporter: str = Field("gcp-trace", alias="OTEL_EXPORTER")
    phoenix_endpoint: str = Field("", alias="PHOENIX_ENDPOINT")


@lru_cache(maxsize=1)
def settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
