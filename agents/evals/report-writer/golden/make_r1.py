#!/usr/bin/env python3
"""Golden-card round 1: hand-edited copies of build #3's report.json (out/phone/report), card 1 only.
Values, n, spreads and verdicts are build #3's; only wording, order, markers and caveat shape change.
    python3 -I make_r1.py   → golden/r1/{A-dense,B-concise,C-sorted}/report.json (+ numbers.json, checker/)"""
import copy, json, os, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "out", "phone", "report")
base = json.load(open(os.path.join(SRC, "report.json")))

QUOTE = "I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it"
WHO = "you, in the planner session (round 9 Ask)"
WHY = "Each warm generation ends with GPU lanes idle while the last battles finish, and every standard run pays for that wait."

EVIDENCE = [
    {"id": "ship", "claim": "Compact state is the one change whose gain clears both spreads.",
     "keys": ["stack_diff", "w_stack_spread", "w_base_spread", "occni_diff", "w_occni_spread"]},
    {"id": "pairs", "claim": "Compact state is faster in all three pairs of the morning A/B.",
     "keys": ["w_base_1", "w_stack_1", "w_base_2", "w_stack_2", "w_base_3", "w_stack_3"]},
    {"id": "match", "claim": "Its results match default.", "keys": ["verify_stack", "verify_stack_flagged"],
     "note": "Only the logs were compared. The checkpoint diff cites a determinism log that is not in the data."},
    {"id": "tailrows", "claim": "Tail and tail plus certain were slower than default in the 11:53 ET A/B.",
     "keys": ["tail_diff", "w_r9pre_tail_spread", "cert_diff", "w_r9pre_cert_spread", "w_r9pre_def_spread"]},
    {"id": "fullrun", "claim": "Nobody finished a full standard run.", "keys": ["full_default_wall", "full_tail_wall"]},
    {"id": "crash", "claim": "Full-tail-1 crashed.", "keys": ["ft_exit", "ft_gens", "ft_planned"]},
    {"id": "conflict", "claim": "Two files disagree on r9-ab-default-1's tail share. Both values are in the Wrong-or-missing box.",
     "keys": ["ts_r9def_runsall"], "note": "The other side is lit/evidence-profile.json, field tail_share."},
    {"id": "v2", "claim": "Tail v2 ran once, with no default run beside it.", "keys": ["w_tailv2_n"]},
    {"id": "afternoon", "claim": "The afternoon A/B lost a default run, and runs.json stores the 11:53 ET values under the afternoon names.",
     "keys": ["r9def2_gens", "w_r9def_runsall", "w_r9def_runsjson"]},
]


def variant(name, f):
    R = copy.deepcopy(base)
    f(R)
    d = os.path.join(HERE, "r1", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    shutil.copy(os.path.join(SRC, "numbers.json"), d)
    shutil.copytree(os.path.join(SRC, "checker"), os.path.join(d, "checker"))
    json.dump(R, open(os.path.join(d, "report.json"), "w"), indent=1, ensure_ascii=False)


def problem(R):
    R["problem"] = {"quote": QUOTE, "quote_from": WHO, "why": WHY}
    R["evidence"] = copy.deepcopy(EVIDENCE)


def dense(R):
    """A: first pass. Every claim on card 1 carries a numbered evidence marker; every figure shows its run."""
    problem(R)
    F = R["first"]
    F["verdict"] = "Compact state ships.[[ship]] It beats default by more than the noise in all three pairs,[[pairs]] and its results match.[[match]]"
    F["deciding"] = ("Compact state {w_stack_mean} vs default {w_base_mean} per warm gen, n = {w_stack_n|bare} vs {w_base_n|bare}, "
                     "spreads {w_stack_spread|bare} vs {w_base_spread|bare}.[[ship]]")
    F["chart"]["reading"] = ("Compact state's gap to default is {stack_diff|bare}, and it clears both spreads.[[ship]] "
                             "Occupancy's {occni_diff|bare} is inside its own spread.[[ship]]")
    F["wrong_or_missing"] = [
        "Nobody finished a full standard run, so it's not measured.[[fullrun]]",
        "Full-tail-1 crashed at gen {ft_gens|bare} of {ft_planned|bare}, so it's not run.[[crash]]",
        "Files disagree on r9-ab-default-1's tail share, {ts_r9def_runsall|bare} vs {ts_r9def_lit|bare} (conflict, evidence-profile).[[conflict]]",
        "Tail v2 ran once, no default beside it, so it's unproven.[[v2]]",
        "The afternoon A/B lost a default run, and its summary mislabels three runs (conflict).[[afternoon]]",
        "Compact state's checkpoint match cites a log that isn't in the data.[[match]]",
    ]


def concise(R):
    """B: second pass over A. Markers kept only on the verdict and the deciding number; figures bare; shorter prose;
    the two caveats that do not bear on the shipped change move to the Evidence card (card 2)."""
    problem(R)
    F = R["first"]
    F["verdict"] = "Compact state ships.[[ship]] It is faster than default in every pair and its results match."
    F["next_action"] = "Diff its checkpoints against default's, then time one full run of each."
    F["deciding"] = ("Compact state {w_stack_mean|bare} vs default {w_base_mean|bare} per warm gen, n = {w_stack_n|bare} vs {w_base_n|bare}, "
                     "spreads {w_stack_spread|bare} vs {w_base_spread|bare} ({w_stack_mean|src}).[[pairs]]")
    F["chart"]["reading"] = "Compact state is {stack_diff|bare} per gen, more than either spread. Occupancy's gap is inside its spread."
    F["wrong_or_missing"] = [
        "Nobody finished a full standard run, so it's not measured.",
        "Full-tail-1 crashed at gen {ft_gens|bare} of {ft_planned|bare}, so it's not run.",
        "Files disagree on a tail share, {ts_r9def_runsall|bare} vs {ts_r9def_lit|bare} (conflict, evidence-profile).",
        "Tail v2 ran once, so it's unproven.",
    ]


def sorted_box(R):
    """C: B with the caveats sorted by kind, and the one assumption that would flip the verdict named."""
    concise(R)
    R["first"]["wrong_or_missing"] = {
        "Not run or not measured": [
            "Nobody finished a full standard run, so it's not measured.",
            "Full-tail-1 crashed at gen {ft_gens|bare} of {ft_planned|bare}, so it's not run.",
        ],
        "Conflict": ["Files disagree on a tail share, {ts_r9def_runsall|bare} vs {ts_r9def_lit|bare} (evidence-profile)."],
        "Unproven": ["Tail v2 ran once."],
        "Assumed, and would flip the verdict": ["Its checkpoints match default's. Only the logs were compared."],
    }


variant("A-dense", dense)
variant("B-concise", concise)
variant("C-sorted", sorted_box)
print("wrote", os.path.join(HERE, "r1"))
