# Ruby

## RSpec
**One pass gives all three numbers** — use `measure.sh baseline 50`. Hand fallback: `bundle exec rspec --profile 50`, which prints the slowest examples, the `N examples, M failures` count, and the total time from a single run. Never run a plain `rspec` first just for timing.
Parallel: `parallel_tests` gem → `bundle exec parallel_rspec spec/` (needs per-worker DBs: `rake parallel:create parallel:prepare`).
Tier: tag `:slow`, then default-exclude in `.rspec`:
```
--tag ~slow
```
Slow tier: `bundle exec rspec --tag slow`. **Union: `bundle exec rspec -O /dev/null`** (`-O` swaps the options file, dropping the `.rspec` default exclusion).
Isolation fallback: shared-state failures under `parallel_rspec` usually mean workers sharing a DB or fixture dir — confirm `TEST_ENV_NUMBER` is used in database.yml; if not resolvable, run the colliding files serially with plain `rspec`.
One file (`<FILE_CMD>`): `bundle exec rspec -O /dev/null spec/path/thing_spec.rb` — `-O /dev/null` drops the `.rspec` `--tag ~slow` default, so a slow example in that file still runs.
Changed-only: `bundle exec rspec $(git diff --name-only origin/main | grep _spec.rb)`. Also enable `--only-failures` by setting `example_status_persistence_file_path` in spec_helper.

## Fixed cost every example pays (step 4, rung 2)
- Boot time dominates a Rails suite: `bootsnap` in `spec_helper`, and `spring` for local runs.
- `config.before(:each)` in `spec_helper` applies to every example — audit it before anything else.
- Fixtures over factories for the objects most specs need; `let!` forces creation whether the example uses it or not.
- `--require rails_helper` from files that only need `spec_helper` pulls the whole app into unit specs.

## Minitest
`parallelize(workers: :number_of_processors)` in test_helper; `PARALLEL_WORKERS` to override.

## Rails slow tail
`use_transactional_fixtures = true`; `webmock`/`vcr` for HTTP; avoid `Timecop.sleep`; eager-load fixtures once rather than per example.

Mutation (follow-up only): `mutant`.
