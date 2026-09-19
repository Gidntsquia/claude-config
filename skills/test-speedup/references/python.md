# Python / pytest

**One pass gives all three numbers** — use `measure.sh baseline 50`. Hand fallback:
`time pytest -q -p no:randomly --durations=50`
`-p no:randomly` keeps before/after comparable; the summary line is the count; the `Ns` lines are the profile. Only run `pytest --collect-only -q` separately if that count came back unknown.

## Parallel — pytest-xdist
Dev dep `pytest-xdist`. Config, not CLI:
```toml
[tool.pytest.ini_options]
addopts = "-n auto"
```
Step 2 adds `-n auto` only; step 3 appends the tier filter to this same line.
Shared-state failures → `-n auto --dist loadfile` (whole file on one worker). Still red → `--dist loadgroup` plus `@pytest.mark.xdist_group(name=...)` on the colliding tests.
Worker startup costs roughly 0.5–1s each; if the suite runs under ~10s, skip xdist and say so in the report.

## Tier
```toml
markers = ["slow: IO, network, or DB bound", "integration: crosses a process boundary"]
```
Step 3 extends addopts to `-n auto -m 'not slow'` and marks tests with `@pytest.mark.slow`. Because `-m` takes the last value given, the CLI overrides that default:
- slow tier: `pytest -m slow`
- **union (the step 3 count check and the step 5 run): `pytest -m ''`**

## One file (`<FILE_CMD>`)
`pytest -m '' -n0 path/to/test_file.py`
`-m ''` cancels the `not slow` default from addopts — without it a slow test in that file is silently skipped and the agent gets a false green. `-n0` because xdist worker startup dominates a single file.

## Changed-only
`pytest-testmon` → `pytest --testmon -n0` (testmon doesn't work under xdist; first run builds `.testmondata`, add it to .gitignore).
Lighter git-based alternative: `pytest-picked` → `pytest --picked`.

## Fixed cost every test pays (step 4, rung 2)
Time collection alone: `time pytest --collect-only -q`. That number is import cost, paid before a single assertion runs, and on a big suite it is often 20–60s of the total.
- Heavy imports at module scope in `conftest.py` or test files — move them inside the test or fixture.
- `--import-mode=importlib` with `consider_namespace_packages`, and drop `__init__.py` from test dirs, to skip the slow rootdir walk.
- Disable plugins you don't use: `-p no:cacheprovider -p no:randomly` in addopts. Each one imports at startup.
- An `autouse=True` fixture applied suite-wide is a per-test tax — scope it or narrow it.
- Django: `--reuse-db --nomigrations` (pytest-django) turns per-run schema creation into a one-off; `--no-migrations` alone is usually the single biggest Django win.
- factory_boy building a full object graph per test → `build()` instead of `create()` where the DB isn't asserted on.

## Slow tail
Widen fixture scope (`@pytest.fixture(scope="session")`); `time-machine` or `freezegun` instead of `time.sleep`; `responses` or `respx` to stub HTTP; Django → `--reuse-db --nomigrations`; SQLAlchemy → wrap each test in a transaction and roll back instead of recreating schema.

Mutation (follow-up only): `mutmut run`.
