#!/usr/bin/env python3
"""Golden-card round 3: two lighter card 1s, after the user's r2 words "way too dense" (research: golden/RESEARCH.md,
ONS main points, ~15-word sentences, none over 25). Both start from r2 A (picked): quote first, verdict answers it,
chart A (absolute bars). The deciding line and the decision table move to a "The numbers" card 2 in both.
Values, n, spreads and verdicts are build #3's; only wording, order and placement change.
    python3 -I make_r3.py   → golden/r3/{A-trimmed-chart,B-main-points}/report.json (+ numbers.json, checker/)"""
import copy, json, os, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "out", "phone", "report")
base = json.load(open(os.path.join(SRC, "report.json")))

QUOTE = "I thought number 4 [round 8's recommendation 4: start the next round's battles while the GPU waits on the last ones] was one of the things I originally requested—I.e, removing unneeded wait times. I want it"
WHO = "you, in the planner session (round 9 Ask)"
WHY = "Every warm generation waits on idle GPU lanes, and every standard run pays that wait."

EVIDENCE = json.load(open(os.path.join(HERE, "r2", "A-answer-first", "report.json")))["evidence"]

WRONG = [
    "No full standard run finished, so it's not measured.",
    "Full-tail-1 crashed, so it's not run.",
    "Files disagree on a tail share, {ts_r9def_runsall|bare} vs {ts_r9def_lit|bare} (conflict, evidence-profile).",
    "Tail v2 ran once, so it's unproven.",
]


def light(R):
    R["problem"] = {"quote": QUOTE, "quote_from": WHO, "why": WHY}
    R["evidence"] = copy.deepcopy(EVIDENCE)
    F = R["first"]
    F["verdict"] = "Not yet. Both wait-time fixes ran slower than default.[[tailrows]] Compact state ships instead.[[ship]]"
    F["next_action"] = "Diff compact state's checkpoints against default's, then time one full run of each."
    F["deciding"] = ("Compact state {w_stack_mean|bare} vs default {w_base_mean|bare} per warm gen, n = {w_stack_n|bare} each, "
                     "spreads {w_stack_spread|bare} and {w_base_spread|bare} ({w_stack_mean|src}).[[pairs]]")
    F["chart"]["reading"] = "Compact state is {stack_diff|bare} per gen, more than either spread."
    F["wrong_or_missing"] = list(WRONG)


def trimmed_chart(R):
    """A: verdict, next action, the bars chart with a one-line reading, four short caveats on card 1."""
    light(R)
    R["first"]["move_down"] = ["deciding", "table"]


def main_points(R):
    """B: the chart moves down too; three ONS-style main points under the verdict take its place on card 1."""
    light(R)
    F = R["first"]
    F["verdict"] = "Not yet. Both wait-time fixes ran slower than default.[[tailrows]]"
    F["points"] = [
        "Compact state ships instead. It was faster than default in all three pairs.[[ship]]",
        "Its logs match default's. Its checkpoints have not been compared yet.",
        "Occupancy's gain is inside its own noise, so it stays unproven.",
    ]
    F["move_down"] = ["deciding", "chart", "table"]


def variant(name, f):
    R = copy.deepcopy(base)
    f(R)
    d = os.path.join(HERE, "r3", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    shutil.copy(os.path.join(SRC, "numbers.json"), d)
    shutil.copytree(os.path.join(SRC, "checker"), os.path.join(d, "checker"))
    json.dump(R, open(os.path.join(d, "report.json"), "w"), indent=1, ensure_ascii=False)


variant("A-trimmed-chart", trimmed_chart)
variant("B-main-points", main_points)
print("wrote", os.path.join(HERE, "r3"))
