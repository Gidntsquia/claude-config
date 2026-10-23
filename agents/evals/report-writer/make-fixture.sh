#!/usr/bin/env bash
# Rebuilds fixture/ from the pogo GPU round 8-9 study (2026-10-17). Run once; the result is committed.
# Everything under fixture/data is a byte copy of the named pogo file, except the planted traps listed in fixture/TRAPS.md.
set -euo pipefail
P="${POGO:-$HOME/files/pogo-gbl-team-generator}"
F="$(cd "$(dirname "$0")" && pwd)/fixture"
S="$P/out/gpu/study"
rm -rf "$F/data" "$F/plans" "$F/bad-reports"
mkdir -p "$F/data/prof" "$F/data/stack" "$F/data/occ" "$F/data/tail" "$F/data/forks" "$F/data/runs" "$F/plans/archive" "$F/bad-reports/round8-cards" "$F/bad-reports/round9/phone"
cp "$S"/{runs.json,ab.log,chain.log,forks.jsonl,det-r9.txt} "$F/data/"
cp "$S"/prof/{metrics.json,result.json,gen-split.json,lanes-time.json,tail-timeline.json,ncu-attempt.log} "$F/data/prof/"
cp "$S"/stack/{runs-final.json,runs-final.txt,ab-runs.json,result.json,verify3v3-stack.log} "$F/data/stack/"
cp "$S"/occ/{result.json,runs.json} "$F/data/occ/"
cp "$S"/tail/{verify3v3-tail.log,verify3v3-tail-certain.log} "$F/data/tail/"
for k in streams cpushare queue pool lockstep split early width; do cp "$S/$k/result.json" "$F/data/forks/$k.json"; done
# Raw per-run files behind every warm s/gen number: the run log and gpu-profile.json (generations[].wall).
for r in ab-base-1 ab-base-2 ab-base-3 ab-stack-1 ab-stack-2 ab-stack-3 ab-occni-1 ab-occni-2 ab-occni-3 r9-ab-default-1 r9-ab-tail-1 r9-ab-certain-1; do
  mkdir -p "$F/data/runs/$r"; cp "$P/out/evolve-gpu8-$r.log" "$F/data/runs/$r/run.log"
  [ -f "$P/out/evolve-gpu8-$r/gpu-profile.json" ] && cp "$P/out/evolve-gpu8-$r/gpu-profile.json" "$F/data/runs/$r/gpu-profile.json"
done
# One scored row per out/evolve-gpu8-* run, by the study's own scorer (round 8 R8 definitions in its header).
( cd "$P" && node gpu/gpu/study/runs.mjs --json ) > "$F/data/runs-all.json"
cp "$P/plans/PLAN.md" "$F/plans/PLAN.md"
cp "$P/plans/WORKER_NOTES.md" "$F/plans/WORKER_NOTES.md"
cp "$P/plans/archive/PLAN-2026-10-17-gpu-round-8-profile-first.md" "$P/plans/archive/EVAL-2026-10-17-gpu-round-8-r1.md" "$P/plans/archive/EVAL-2026-10-17-gpu-round-8-r2.md" "$F/plans/archive/"
cp "$P"/plans/eval-artifacts/r9/card-*.png "$F/bad-reports/round8-cards/"
cp "$P/out/gpu-study.html" "$F/bad-reports/round9/gpu-study.html"
cp "$S"/phone/[0-9]*.png "$F/bad-reports/round9/phone/"
cp "$S"/page-numbers.json "$S"/check.log "$F/bad-reports/round9/"
echo "copied; now planting traps"
python3 - "$F" <<'PY'
import json, sys, os
F = sys.argv[1]
# Trap 1: a second file with a different tail share for the same run (runs.json says 0.4258 for r9-ab-default-1).
os.makedirs(f"{F}/data/lit", exist_ok=True)
json.dump({"note": "literature fork, evidence profile of the production path (tail = time after half the main battles ended / launch span)",
           "run": "r9-ab-default-1", "tail_share": 0.352, "tail_s": 3.98, "warm_s_per_gen": 10.91,
           "source": "out/gpu/study/lit/evidence-profile.json"}, open(f"{F}/data/lit/evidence-profile.json", "w"), indent=1)
# Trap 2: a crashed run (exit 1) that still carries a numeric wall.
os.makedirs(f"{F}/data/full", exist_ok=True)
json.dump({"name": "full-tail-1", "env": "POGO_GPU_STUDY=tail", "recipe": "recipes/standard.json", "exit": 1,
           "gens_done": 14, "gens_planned": 40, "wall_s": 612.4, "start": "2026-10-17 12:40 ET",
           "note": "process exited 1 at gen 14 (sidecar lost the GPU lock); no evolve-DONE marker"},
          open(f"{F}/data/full/full-tail-1.json", "w"), indent=1)
# Trap 3: a candidate with a single run and a large gain.
json.dump({"name": "r9-ab-tailv2-1", "env": "POGO_GPU_STUDY=tail,v2", "exit": 0, "gens": 10, "sat": 4,
           "warmPerGen": 9.10, "total": 118.2, "note": "one run only; v2 = speculation threshold 25% instead of 50%"},
          open(f"{F}/data/ab-tailv2.json", "w"), indent=1)
# Trap 4 is in question.txt: the full standard run's total wall is asked for, and no file measures it for default
# (runs.json "full": all null; full/full-tail-1.json crashed).
PY
cat > "$F/question.txt" <<'Q'
Which GPU change, if any, should ship, and what is the next build?
Decide by warm seconds per generation in the same-hour interleaved A/B (10-gen halving-3 standard command), with the ship checks from plans/PLAN.md R6: identical results (verify 100%, same-seed checkpoints identical), gain beyond both spreads, tail share drop, and the full standard run's total wall. Also give the full standard run's total wall for the shipped change against default.
Q
du -sh "$F"; find "$F" -type f | wc -l
