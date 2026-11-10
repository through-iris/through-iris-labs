#!/usr/bin/env python3
"""Run the ep29 formal labs: three ways a formal result lies, in episode order.

Each break runs the way the episode tells it. The lie shows up first (a
counterexample that is not a bug, a proof that checks nothing, a bounded pass),
then the check that exposes it, then the fix. Every row has an expected result
and an expected cycle. A FAIL can be the right answer.

    python run.py                    # the whole story + the final lab
    python run.py arb2 real          # one SymbiYosys task, by hand
    python run.py fifo bmc80
    python run.py skid bad           # the final lab: find the bug

Needs `sby` (SymbiYosys) from the OSS CAD Suite on PATH. Work directories go
to build/ (one per task, replaced on every run). Exit status is 0 only if every
row matched what it should do -- including the rows expected to FAIL.
"""
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAL = os.path.join(HERE, "formal")
BUILD = os.path.join(HERE, "build")
JOBS = ("arb2", "fifo", "skid")

# (job, task, expected status, expected detail, what the row shows)
#   detail: ("fail", prop, cycle) -- that assertion fails, first visible on that cycle
#           ("unreached", cover)  -- that cover is unreachable within the bound
#           ("reached", cover, cycle) -- that cover is first reached on that cycle
#           None                  -- just the status
STORY = [
    ("Break 1: too few assumptions", [
        ("arb2", "spurious", "FAIL", ("fail", "as_m", 2), "no input assumptions: a counterexample..."),
        ("arb2", "real",     "FAIL", ("fail", "as_m", 2), "assume the VALID rule on the inputs: the real bug (cold open)"),
        ("arb2", "fixed",    "PASS", None,                 "fix: hold the grant during a stall -> proven"),
    ]),
    ("Break 2: too many assumptions", [
        ("arb2", "over",     "PASS", None,                 "bug back in + 'never both' assumption: proves anyway"),
        ("arb2", "over_cov", "FAIL", ("unreached", "co_both"), "the covers catch it: both-requesting is unreachable"),
        ("arb2", "cover",    "PASS", ("reached", "co_both", 1), "honest assumptions: every cover reached"),
    ]),
    ("Break 3: too little depth", [
        ("fifo", "bmc20",    "PASS",    None,                        "6-bit count, bounded to depth 20: passes"),
        ("fifo", "kind20",   "UNKNOWN", None,                        "k-induction at depth 20: inconclusive"),
        ("fifo", "bmc80",    "FAIL",    ("fail", "as_not_empty", 65), "bounded to depth 80: the bug, on cycle 65"),
        ("fifo", "pdr",      "FAIL",    ("fail", "as_not_empty", 65), "an unbounded engine (abc pdr): cycle 65"),
        ("fifo", "fixed",    "PASS",    None,                        "fix: a 7-bit count -> proven at every depth"),
        ("fifo", "cov20",    "FAIL",    ("unreached", "co_full"),    "guard 1: cover 'full' at bound 20 -> unreachable"),
        ("fifo", "cov80",    "PASS",    ("reached", "co_full", 65),  "...at bound 80: first full on cycle 65"),
        ("fifo", "small",    "FAIL",    ("fail", "as_not_empty", 5), "guard 2: DEPTH 4, CW 2 -> the same bug, cycle 5"),
    ]),
    ("Final lab: find the bug in the skid buffer", [
        ("skid", "bad",      "FAIL", ("fail", "as_count", 4), "rtl/broken/skid_bad.sv: caught -- which line? (SOLUTION.md)"),
        ("skid", "fixed",    "PASS", None,                    "rtl/skid.sv: proven"),
        ("skid", "cover",    "PASS", ("reached", "co_drain", 3), "...and its covers reached"),
    ]),
]


def find_sby():
    """sby on PATH. On Windows, OSS CAD Suite's tools also need its lib/ on PATH."""
    exe = shutil.which("sby")
    if not exe:
        sys.exit("sby not found. Put the OSS CAD Suite's bin/ on PATH (see README: Setup).")
    lib = os.path.normpath(os.path.join(os.path.dirname(exe), os.pardir, "lib"))
    if os.path.isdir(lib) and lib not in os.environ.get("PATH", ""):
        os.environ["PATH"] = os.environ["PATH"] + os.pathsep + lib
    return exe


def run_task(sby, job, task):
    """Run one sby task; return its parsed log."""
    os.makedirs(BUILD, exist_ok=True)
    prefix = os.path.join(BUILD, job)
    t0 = time.time()
    subprocess.run([sby, "-f", "--prefix", prefix, job + ".sby", task], cwd=FORMAL,
                   capture_output=True, text=True)
    secs = time.time() - t0
    logf = prefix + "_" + task
    logf = os.path.join(logf, "logfile.txt")
    log = open(logf).read() if os.path.exists(logf) else ""
    m = re.search(r"DONE \((\w+), rc=\d+\)", log)
    status = m.group(1) if m else "ERROR"
    # sby names a property  arb2.\u_props.as_m  (the instance path, then the label)
    fails = {p: int(s) for p, s in re.findall(r"failed assertion \S*?\.(\w+) at \S+ step (\d+)", log)}
    reached = {p: int(s) for p, s in re.findall(r"reached cover statement \S*?\.(\w+) at \S+ step (\d+)", log)}
    unreached = {n.split(".")[-1] for n in re.findall(r"Unreached cover statement at \S+ (\S+)\s*$", log, re.M)}
    errs = [l for l in log.splitlines() if "ERROR" in l and "DONE" not in l]
    return dict(status=status, fails=fails, reached=reached, unreached=unreached,
                secs=secs, err=errs[0].strip() if errs else "", dir=os.path.dirname(logf))


def read_vcd(path):
    """The design's own signals (top scope only) from an sby trace, one dict per
    step. yosys-smtbmc writes step k at time 10*k (and the clock's fall at +5)."""
    if not os.path.exists(path):
        return []
    ids, depth, cur, snaps, t = {}, 0, {}, [], None
    for ln in open(path):
        w = ln.split()
        if not w:
            continue
        if w[0] == "$scope":
            depth += 1
        elif w[0] == "$upscope":
            depth -= 1
        elif w[0] == "$var" and depth == 1:
            ids.setdefault(w[3], w[4])
        elif w[0].startswith("#"):
            if t is not None:
                snaps.append((t, dict(cur)))
            t = int(w[0][1:])
        elif w[0][0] in "01xz" and w[0][1:] in ids:
            cur[ids[w[0][1:]]] = int(w[0][0]) if w[0][0] in "01" else None
        elif w[0][0] == "b" and len(w) > 1 and w[1] in ids:
            cur[ids[w[1]]] = int(w[0][1:], 2) if set(w[0][1:]) <= set("01") else None
    if t is not None:
        snaps.append((t, dict(cur)))
    return [v for t, v in snaps if t % 10 == 0]


def explain_arb2(res, step):
    """What the arbiter's counterexample shows on the cycle it breaks."""
    tr = read_vcd(os.path.join(res["dir"], "engine_0", "trace.vcd"))
    c = cycle(step)
    if len(tr) <= c:
        return ""
    p, n = tr[c - 1], tr[c]
    if p.get("s0_valid") and not p.get("s0_ready") and not n.get("s0_valid"):
        return "-> M0 dropped VALID mid-stall: illegal input, SPURIOUS"
    if p.get("s1_valid") and not p.get("s1_ready") and not n.get("s1_valid"):
        return "-> M1 dropped VALID mid-stall: illegal input, SPURIOUS"
    if p.get("owner") != n.get("owner"):
        return "-> inputs legal, grant flipped M%d->M%d mid-stall: REAL" % (p.get("owner"), n.get("owner"))
    return ""


def cycle(step):
    """sby counts steps from the reset step, and a clocked property reports on the
    step AFTER the cycle it sampled -- so the visible cycle is step - 1."""
    return step - 1


def check(res, expect, detail):
    """Does a parsed run match its row? Returns (ok, what to print)."""
    ok = res["status"] == expect
    note = ""
    if detail and detail[0] == "fail":
        _, prop, cyc = detail
        step = res["fails"].get(prop)
        ok = ok and step is not None and cycle(step) == cyc
        note = "%s fails: step %s = cycle %s" % (prop, step, cycle(step) if step else "-")
        if step and prop == "as_m":
            note += "  " + explain_arb2(res, step)
    elif detail and detail[0] == "unreached":
        _, cov = detail
        ok = ok and cov in res["unreached"]
        note = "%s UNREACHED%s" % (cov, "" if cov in res["unreached"] else " -- expected, not seen")
    elif detail and detail[0] == "reached":
        _, cov, cyc = detail
        step = res["reached"].get(cov)
        ok = ok and step is not None and cycle(step) == cyc and not res["unreached"]
        note = "%s reached: step %s = cycle %s" % (cov, step, cycle(step) if step else "-")
        if len(res["reached"]) > 1 and not res["unreached"]:
            note += "  (all %d covers reached)" % len(res["reached"])
    elif res["fails"]:
        p, s = sorted(res["fails"].items(), key=lambda kv: kv[1])[0]
        note = "%s fails: step %d = cycle %d" % (p, s, cycle(s))
        if p == "as_m":
            note += "  " + explain_arb2(res, s)
    if res["status"] == "ERROR":
        note = res["err"][:100]
    return ok, note


def main():
    sby = find_sby()
    args = sys.argv[1:]
    if args:
        if len(args) != 2 or args[0] not in JOBS:
            sys.exit("usage: python run.py [<%s> <task>]" % "|".join(JOBS))
        res = run_task(sby, args[0], args[1])
        _, note = check(res, res["status"], None)
        print("%s %s/%s  %s  (%.0f s)\n  log + trace: %s" % (res["status"], args[0], args[1], note,
                                                          res["secs"], os.path.relpath(res["dir"], HERE)))
        for p, s in sorted(res["reached"].items()):
            print("  cover %-10s reached on cycle %d" % (p, cycle(s)))
        for p in sorted(res["unreached"]):
            print("  cover %-10s UNREACHED" % p)
        return 0

    print("Cycles count from reset = cycle 0. sby reports a clocked property on the step")
    print("after the cycle it sampled, so its 'step N' is cycle N-1 here and in the episode.")
    bad, t_all = 0, time.time()
    for head, rows in STORY:
        print("\n== %s ==" % head)
        for job, task, expect, detail, what in rows:
            res = run_task(sby, job, task)
            ok, note = check(res, expect, detail)
            bad += not ok
            print("  %s %-7s %-62s %s  [%.0fs]" % ("ok  " if ok else "BAD ", res["status"], what, note, res["secs"]))
    print("\n%s  (%.0f s)" % ("ALL AS EXPECTED" if bad == 0 else "%d row(s) did not match" % bad,
                              time.time() - t_all))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
