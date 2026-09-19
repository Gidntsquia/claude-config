# Node — jest / vitest

Pick by dependency in package.json.

## jest
**One pass gives all three numbers** — use `measure.sh baseline 50`. Hand fallback:
`npx jest --silent --json --outputFile=/tmp/jest.json` — then `jq .numTotalTests /tmp/jest.json` for the count and
`jq -r '.testResults[].assertionResults[] | [.duration/1000, .fullName] | @tsv' /tmp/jest.json | sort -rn | head -50` for the profile.
Never `--listTests` for a count: it counts files, not tests.

Jest is already parallel; the real wins, in order:
1. TypeScript repos: swap `ts-jest` for `@swc/jest`. Usually the single biggest cut.
2. Delete any `--runInBand` from scripts.
3. `maxWorkers: '50%'` in config; on 2-core CI runners `--maxWorkers=2` beats auto.
4. CI: `--shard=1/N` across parallel jobs.

Tier: two `projects` entries with different `testMatch` (`**/*.test.ts` vs `**/*.integration.test.ts`); default script runs `--selectProjects unit`. Slow tier `--selectProjects integration`; **union: `npx jest` with no `--selectProjects`** (projects are disjoint here, but use the union anyway for the step 3 count check and the step 5 run).

One file (`<FILE_CMD>`): `npx jest path/to/file.test.ts` — a positional path filter applies across every project, so it is already the union for that file. Don't add `--selectProjects`, which would re-exclude the integration half.
Isolation fallback: jest is already one worker per file, so shared-state failures mean a shared external resource. Scope `--runInBand` to the colliding project rather than the whole suite, or give each worker its own DB/port via `JEST_WORKER_ID`.
Changed-only: `"test:quick": "jest --onlyChanged"`, or `--changedSince=origin/main`.

## Fixed cost every test pays (step 4, rung 2)
Jest pays module transform + environment setup **per test file**, so this is where a flat profile hides.
- `testEnvironment: 'node'` unless the file needs a DOM. jsdom construction per file is tens of ms each.
- `@swc/jest` over `ts-jest` (see above), or `isolatedModules: true` if ts-jest must stay.
- `setupFiles`/`setupFilesAfterEnv` run once per file — anything expensive in there is multiplied by file count.
- Check `transformIgnorePatterns` isn't forcing `node_modules` through babel.
- Make sure the jest cache directory survives between runs locally and in CI.

## vitest
One pass: `npx vitest run --reporter=json --outputFile=/tmp/vitest.json` — `numTotalTests` plus per-test durations from the same file. `--reporter=verbose` if you only want it on stdout.
Parallel is default — tune `poolOptions.threads.maxThreads`; switch `pool: 'forks'` if tests mutate globals.
Tier: separate `vitest.integration.config.ts`, or `test.exclude` in the default config; union runs both configs.
Isolation fallback: `--no-file-parallelism`, or `pool: 'forks'` with `isolate: true`.
One file (`<FILE_CMD>`): `npx vitest run path/to/file.test.ts`; if the slow tier lives in its own config, name it — `npx vitest run -c vitest.integration.config.ts path/to/file`.
Changed-only: `npx vitest run --changed origin/main`.

Mutation (follow-up only): stryker.
