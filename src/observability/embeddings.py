"""Embedding helper — single hot-path call to Vertex AI text-embedding-004."""

from __future__ import annotations

import numpy as np
from google.cloud import aiplatform
from google.cloud.aiplatform.gapic.schema import predict

from src.common.config import settings


async def embed_text(text: str) -> np.ndarray:
    """Return a numpy vector for the input text.

    In production this hits Vertex AI; for tests we stub it via dependency
    injection or fixtures.
    """
    cfg = settings()
    client = aiplatform.gapic.PredictionServiceAsyncClient(
        client_options={"api_endpoint": f"{cfg.region}-aiplatform.googleapis.com"}
    )
    endpoint = f"projects/{cfg.project_id}/locations/{cfg.region}/publishers/google/models/{cfg.embedding_model}"
    instances = [predict.instance.TextEmbeddingPredictionInstance(content=text).to_value()]
    response = await client.predict(endpoint=endpoint, instances=instances)
    values = response.predictions[0]["embeddings"]["values"]
    return np.asarray(values, dtype=np.float32)
