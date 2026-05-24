# requirements/

All Python dependency manifests live here. Splitting them keeps the runtime
image lean and prevents pip's resolver from blowing up on transitive conflicts
between core deps and heavy ML libraries.

| File | When to install | What's in it |
|---|---|---|
| `requirements.txt` | Always (runtime, container image) | FastAPI, Vertex AI client, LangGraph, AlloyDB driver, Redis client, OpenTelemetry |
| `requirements-dev.txt` | Local development, CI lint/test | ruff, black, mypy, pytest, pre-commit |
| `requirements-eval.txt` | Only when running Ragas evals | ragas, datasets, arize-phoenix (heavy ML deps that conflict with the runtime resolver) |

## Install commands

```bash
# Production / runtime only
uv pip install -r requirements/requirements.txt

# Local dev (lint, format, test)
uv pip install -r requirements/requirements-dev.txt

# Eval suite (Ragas, drift checks)
uv pip install -r requirements/requirements.txt -r requirements/requirements-eval.txt
```

## Why this split

A single combined `requirements.txt` containing both the runtime libs and the
eval libs (`ragas`, `datasets`, `arize-phoenix`) triggered pip's
`resolution-too-deep` error in CI. The eval stack pulls in a wide tree of ML
transitive deps that don't need to be in the production image. Splitting them
gave us:

- A fast, deterministic CI install (~30 seconds with uv).
- A smaller runtime container image.
- A clean line between "what the API needs to serve traffic" and "what the
  offline evaluation tools need to grade it."
