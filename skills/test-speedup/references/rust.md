# Rust

Measure compile and run separately — compilation is usually the actual cost:
```
time cargo test --no-run    # compile
time cargo test             # compile (cached) + run
```

## Runner swap
`cargo-nextest` is the main win: per-test processes, parallel by default, typically 2–3x over `cargo test`. `cargo nextest run`. (It does not run doctests — keep `cargo test --doc` in CI.)

## Profile
`cargo nextest run` already prints `PASS [   1.234s] crate test::name` per test and a `Summary [...] N tests run` line, so one run gives timing, count, and profile — `measure.sh baseline` parses exactly that. Compile time is separate; measure it with `cargo test --no-run` only if the run number looks compile-dominated.

nextest can also flag slow tests as they run. `.config/nextest.toml`:
```toml
[profile.default]
slow-timeout = { period = "5s", terminate-after = 4 }
```

## Tier
`#[ignore]` on slow tests. Fast tier is the default run.
- slow tier only: `cargo nextest run --run-ignored only`
- **union: `cargo nextest run --run-ignored all`** — this runs ignored *and* normal tests, so it is the union, not a disjoint slow tier. Never sum fast + slow here.

(Older nextest spells `only` as `ignored-only`; check `--help` if it rejects the flag.) Filter expressions work too: `-E 'not test(/^slow_/)'`.

## Isolation fallback
Shared-state failures under parallelism: `cargo nextest run -j1`, or `cargo test -- --test-threads=1`. nextest already gives each test its own process, so a failure here usually means a shared external resource (port, file, DB), not shared memory.

## One test or crate (`<FILE_CMD>`)
`cargo nextest run --run-ignored all -E 'package(mycrate)'`, or `-E 'test(name_substring)'`. `--run-ignored all` is required — otherwise `#[ignore]`d tests in the target are skipped and the green is false.

## Changed-only
`cargo nextest run -E 'rdeps(changed_crate)'`

## Compile time
`codegen-units = 256` and `lto = false` under `[profile.test]`; a faster linker (`mold` or `lld` via `.cargo/config.toml`); `sccache`; split one large crate into workspace members so a change rebuilds less.

Mutation (follow-up only): `cargo-mutants`.
