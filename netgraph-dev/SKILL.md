---
name: netgraph-dev
description: >
  NetGraph contributor development workflow. Use when: setting up dev environment,
  running tests or lint, fixing CI failures, comparing scenario performance,
  troubleshooting venv issues, or asking about make targets.
  For running scenarios and interpreting results, use netgraph-dsl instead.
---

# NetGraph development

For people changing NetGraph itself. To write or run scenarios, use the `netgraph-dsl` skill.

## Setup

```bash
make dev    # creates ./venv, installs NetGraph with its dev extras, installs the pre-commit hooks
```

NetGraph needs Python 3.11 or later. Its engine, NetGraph-Core (`netgraph-core`), is installed
from PyPI within the version bounds in `pyproject.toml`.

Run tools from the venv directly, so the shell's own Python never gets in the way:

```bash
./venv/bin/python -m pytest tests/dsl/
./venv/bin/ngraph inspect scenarios/square_mesh.yaml
```

## Make targets

| Command | What it does |
|---------|--------------|
| `make qt` | Quick tests: no coverage, skips tests marked `slow` |
| `make test` | All tests, with coverage |
| `make check` | Before a commit: pre-commit hooks (fixing what they can), `make validate`, all tests, then `make lint` |
| `make check-ci` | What CI runs: `make lint`, `make validate`, `make test` and `make docs-check`; it does not rewrite source files |
| `make lint` | Checks formatting and lint (ruff) and types (pyright); it does not rewrite source files |
| `make format` | Formats the code with ruff |
| `make validate` | Checks the YAML under `scenarios/` and `tests/integration/` against the scenario schema, and checks that the results schema matches the code |
| `make docs` | Regenerates `docs/reference/api-full.md` and the diagrams |
| `make docs-check` | Checks the generated API reference and builds the docs with `mkdocs build --strict` |
| `make perf` | The scenario timing driver; `make perf PERF_ARGS='...'` passes arguments, and without them it prints its help |
| `make perf-tool-test` | Tests the timing driver itself; it times nothing |

## Changing code

1. Make the change, with tests for the new behavior or the fixed bug.
2. Run `make qt` while you work.
3. Run `make check` before you commit.
4. If a public API changed, run `make docs`. If a result record changed, run
   `./venv/bin/python dev/generate_results_schema.py`: it rewrites `ngraph/schemas/results.json`
   and `docs/reference/results.md`, and refuses a field without a description.

When a test fails, fix the code, not the test, unless the test is wrong.

## CI

CI (`.github/workflows/python-test.yml`) runs `make check-ci` on Python 3.11, 3.12, 3.13, 3.14
and free-threaded 3.14t. When it fails, run `make check-ci` locally on the same Python version.
The pre-commit hooks run on every commit; `make hooks` runs them on all files.

## Scenario performance

`dev/scenario_perf.py` (`make perf`) times complete scenarios, old code against new, in A/B/A
order, from a JSON manifest. Timing needs a quiet machine. `dev/dev.md` describes the manifest
and the procedure. Benchmarks of the engine itself belong to NetGraph-Core.

## Tools in `dev/`

| File | Purpose |
|------|---------|
| `dev/dev.md` | Short development guide: commands, publishing, performance comparisons |
| `dev/run-checks.sh` | The checks behind `make check` |
| `dev/generate_results_schema.py` | Writes the results schema and `docs/reference/results.md`; `--check` (used by `make validate`) only compares |
| `dev/generate_api_docs.py` | Writes the API reference (used by `make docs`) |
| `dev/check_api_docs.py` | Checks that the API reference is up to date (used by `make docs-check`) |
| `dev/check_core_integration.sh` | Tests NetGraph against a chosen NetGraph-Core build in an isolated venv: `bash dev/check_core_integration.sh /absolute/path/to/NetGraph-Core` |
| `dev/scenario_perf.py` | The scenario timing driver (`make perf`) |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No `./venv` | `make dev` |
| Import errors after a pull | `./venv/bin/pip install -e '.[dev]'` |
| Pre-commit reformatted files | `make format`, then `make check` |
| The venv's Python differs from the newest one installed | `make check-python` warns; recreate with `make clean-venv` and `make dev` |
