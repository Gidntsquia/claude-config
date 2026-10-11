# first-project: a tip calculator built through the planner → worker → evaluator loop

A tiny web page: type a bill, pick a tip percent (15/18/20/25 or a custom one), see the tip and the total.
React + TypeScript + Vite + Tailwind + shadcn-style components, run with Bun.

This folder is the finished result of one trip around the loop, kept as a worked example.
Unlike a normal project, its `plans/` folder is committed here so you can read what each agent wrote. A real project puts `plans/` in `.gitignore` (the planner adds that line); this example leaves it out of `.gitignore` on purpose so the files below are in the repo:

- `plans/PLAN.md`: what the planner wrote (the spec and its acceptance criteria).
- `plans/WORKER_NOTES.md`: what the worker wrote (how to launch it, what it checked, what it fixed on the rerun).
- `plans/EVAL.md`: what the evaluator wrote (your answers, the verdict).
- `plans/archive/`: earlier versions, if any (the first evaluator run said `rerun worker`; the worker fixed it; the second run said `ship`).

## Run it

```
bun install
bun run dev
```

Open the address it prints (usually http://localhost:5173). `bun test` runs the math tests; `bun run build` makes `dist/`.

## Replay the loop on it

Copy this folder somewhere, delete its `plans/` folder, and run the three agents from inside the copy:

```
cp -r ~/files/claude-config/examples/first-project ~/files/my-tip-calculator
cd ~/files/my-tip-calculator && rm -rf plans
claude --agent planner "A tip calculator web page: type a bill amount and a tip percent, see the tip and the total"
claude --agent worker "."
claude --agent evaluator "."
```

Each command is its own session: when an agent finishes, type `/exit`, then the next command. Read `plans/EVAL.md` for the verdict: **ship** means done; **rerun worker** means `claude --agent worker "."` again; **replan** means `claude --agent planner "Replan based on plans/EVAL.md"`.

Stuck? In a second terminal: `claude --agent helper`.
