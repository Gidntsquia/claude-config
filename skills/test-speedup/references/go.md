# Go

**One pass gives all three numbers** — use `measure.sh baseline 50`. Hand fallback:
```
go test -count=1 -json ./... > /tmp/go.json      # the only run you need
jq -rs '[.[]|select(.Test!=null and (.Action=="pass" or .Action=="fail" or .Action=="skip"))|.Package+"."+.Test]|unique|length' /tmp/go.json
jq -rs '.[]|select(.Test!=null and .Action=="pass")|[.Elapsed,(.Package+"."+.Test)]|@tsv' /tmp/go.json | sort -rn | head -50
```
`-count=1` is required — go caches test results, so without it the number is meaningless. Same flag for the after-measurement.

## Parallel
`-p` (packages in parallel) already defaults to GOMAXPROCS, so it's rarely the problem. The win is `t.Parallel()` inside the slow packages from the profile. Add `-shuffle=on` to the CI command to surface order dependence before parallelism does.

## Tier
Build tags beat `testing.Short()` — they exclude at compile time:
```go
//go:build integration
```
Fast: `go test ./...`. Slow tier and **union**: `go test -tags=integration ./...`.

Build tags are additive — `-tags=integration` runs the tagged files *plus* everything else, so the slow command is a superset of the fast one, not a disjoint tier. It is the union command; never sum fast + slow here.

## Isolation fallback
Shared-state failures under parallelism: `-p 1` serializes packages; within a package, drop `t.Parallel()` from the colliding tests. `-shuffle=on` names them faster than bisecting.

## One package (`<FILE_CMD>`)
`go test -tags=integration -count=1 ./path/to/pkg/...` — the unit here is the package, not the file. Tags are additive, so this is the union for that package; without `-tags=integration` its integration tests don't compile in and you get a false green. Narrow further with `-run TestName`.

## Fixed cost every test pays (step 4, rung 2)
- **Leave `-count=1` out of the day-to-day commands.** Go caches test results per package: with the cache on, an unchanged package returns in milliseconds, which is most of the value of a changed-files run. `-count=1` belongs in the measurement and in CI, nowhere else.
- Compilation is counted inside `go test`; a cold build cache makes the first run look far worse than the steady state. Time a second run before concluding anything.
- Package-level `TestMain` setup runs once per package — a per-test container or DB build there is the usual flat-profile culprit.
- `-vet=off` on the local fast command; vet still runs in CI.

## Changed-only
```
go test $(git diff --name-only origin/main | grep '\.go$' | xargs -rn1 dirname | sort -u | sed 's|^|./|')
```

## Slow tail
Shared setup into `TestMain`; `httptest` instead of live servers; channels or `testing/synctest` instead of `time.Sleep`; one shared DB container with per-test transactions.

Mutation (follow-up only): `go-mutesting`.
