# Contributing

Thanks for considering a contribution. A few ground rules to keep the project healthy.

## Development setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pre-commit install
```

## Branching

- `main` is always deployable to staging.
- Feature branches use the format `feat/short-description` or `fix/short-description`.
- Squash-merge into `main` with a Conventional Commit subject line.

## Commit messages

We use Conventional Commits:

```
feat(retrieval): add hybrid BM25 + dense fusion
fix(cache): correct TTL on negative cache entries
docs(arch): clarify intent router fallback path
refactor(api): extract streaming response helper
```

## Pull requests

Before opening a PR:

1. `make lint` passes.
2. `make test` passes.
3. `terraform validate` and `terraform fmt -recursive -check` pass.
4. The Ragas evaluation suite shows no regression on faithfulness or context precision.
5. The PR description explains *why*, not just *what*.

## Architecture changes

Significant architectural changes need an ADR in `docs/adr/`. Use the existing ADRs as templates. Don't merge changes to the request lifecycle, the retrieval stack, or the LLM routing logic without one.

## Reporting issues

Open a GitHub issue with:
- A minimal reproduction.
- Expected vs. actual behavior.
- Relevant trace IDs from Cloud Trace if applicable.

## Code of conduct

Be kind. Assume good faith. Disagree without being disagreeable.
