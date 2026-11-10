#!/usr/bin/env python3
"""Run the ep26 PCIe labs: the three breaks from the episode, then a regression.

Every break is shown the way the episode tells it, and none of them is a
broken packet. Break 1 and Break 3 run a correct design against a testbench
that keeps the books wrong; Break 2 is the receiver from the cold open, whose
discard path keeps the credit. Each break fails here, each fix passes, and
the fixes then pass a random regression.

    python run.py                          # the whole story + 10-seed regression
    python run.py --seeds 50               # a longer regression
    python run.py split --broken --story   # one run, by hand
    python run.py credit --broken --seed 26 --nocheck
    python run.py --sim icarus             # force a simulator (default: verilator if it works)

Exit status is 0 only if every run matched its expected result -- including
the runs expected to FAIL.
"""
import argparse
import os
import random
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
RTL = sorted(os.path.join("rtl", f) for f in os.listdir(os.path.join(HERE, "rtl")) if f.endswith(".sv"))
RTL += sorted(os.path.join("rtl", "broken", f) for f in os.listdir(os.path.join(HERE, "rtl", "broken")))
TESTS = ["split", "credit", "replay"]

# the episode's credit-leak model: a write misses every BAR with this chance
MISS_P, STORY_SEED = 1.0 / 250, 26

# (test, broken, plusargs, seed, expect, error to show, what it shows)
STORY = [
    ("split",  True,  ["+story"],      1,  "FAIL", "short read",     "Break 1: the scoreboard that expects one"),
    ("split",  False, ["+story"],      1,  "PASS", None,             "Fix: track bytes per tag, retire at zero"),
    ("credit", True,  ["+nocheck"],    26, "FAIL", "hang",           "Break 2: the cold open, 2312 writes then nothing"),
    ("credit", True,  ["+writes=200"], 26, "FAIL", "credits leaked", "Break 2 + end-of-test credit check"),
    ("credit", False, [],              26, "PASS", None,             "Fix: a discarded write gives its credit back"),
    ("replay", True,  ["+story"],      1,  "FAIL", "counted twice",  "Break 3: a wire monitor counts the replay"),
    ("replay", False, ["+story"],      1,  "PASS", None,             "Fix: the scoreboard watches the transaction layer"),
]


def miss_file(seed, p):
    """Which writes miss every BAR, drawn exactly as the episode's model draws them."""
    path = os.path.join(BUILD, "miss_%d_%d.txt" % (seed, round(1 / p)))
    if not os.path.exists(path):
        rng = random.Random(seed)
        with open(path, "w") as f:
            f.write("".join("%d\n" % (rng.random() < p) for _ in range(8192)))
    return os.path.relpath(path, HERE).replace("\\", "/")


class Icarus:
    name = "icarus"

    def __init__(self):
        self.cache = {}

    def build(self, test, defines):
        key = (test, tuple(sorted(defines)))
        if key not in self.cache:
            out = os.path.join(BUILD, "icarus_%s_%d.vvp" % (test, len(self.cache)))
            cmd = ["iverilog", "-g2012", "-I", "tb", "-s", "tb_" + test, "-o", out]
            cmd += ["-D" + d for d in defines] + [os.path.join("tb", "tb_%s.sv" % test)] + RTL
            run_tool(cmd)
            self.cache[key] = out
        return ["vvp", "-n", self.cache[key]]


class Verilator:
    name = "verilator"

    def __init__(self):
        self.cache = {}

    def build(self, test, defines):
        key = (test, tuple(sorted(defines)))
        if key not in self.cache:
            mdir = os.path.join(BUILD, "verilator_%s_%d" % (test, len(self.cache)))
            cmd = verilator_cmd() + ["--binary", "-j", "0", "--timing", "-Wno-fatal", "-Wno-lint",
                                     "-Wno-style", "-Itb", "--top-module", "tb_" + test,
                                     "--Mdir", mdir, "-o", "sim"]
            cmd += ["-D" + d for d in defines] + RTL + [os.path.join("tb", "tb_%s.sv" % test)]
            run_tool(cmd)
            self.cache[key] = os.path.join(mdir, "sim")
        return [self.cache[key]]


def run_tool(cmd):
    p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit("build failed: %s\n%s%s" % (" ".join(cmd), p.stdout, p.stderr))


def verilator_cmd():
    """The `verilator` launcher is a Perl script. On Windows it usually can't
    run (OSS CAD Suite ships no Perl, and Git's Perl lacks Pod::Usage), but the
    binary it wraps builds on its own, given VERILATOR_ROOT."""
    if os.name != "nt" and shutil.which("verilator"):
        return ["verilator"]
    exe = shutil.which("verilator_bin")
    if exe:
        root = os.path.join(os.path.dirname(exe), os.pardir, "share", "verilator")
        # forward slashes: make's recipes may run under a POSIX sh, which eats backslashes
        os.environ.setdefault("VERILATOR_ROOT", os.path.normpath(root).replace("\\", "/"))
        return [exe]
    return ["verilator"] if shutil.which("verilator") else []


def verilator_works():
    """Verilator needs a C++ compiler and make; check by building something tiny."""
    if not verilator_cmd():
        return False
    probe = os.path.join(BUILD, "probe")
    os.makedirs(probe, exist_ok=True)
    src = os.path.join(probe, "t.sv")
    open(src, "w").write("module t; initial begin $display(\"ok\"); $finish; end endmodule\n")
    try:
        p = subprocess.run(verilator_cmd() + ["--binary", "--Mdir", probe, "-o", "t", src],
                           capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return p.returncode == 0


def one(sim, test, broken, plusargs, seed, show=None):
    """Build (cached) and run one configuration; return (PASS|FAIL, the error to show, cfg line)."""
    cmd = sim.build(test, ["BROKEN"] if broken else []) + list(plusargs) + ["+seed=%d" % seed]
    if test == "credit":
        # the story seed uses the episode's miss rate; other seeds vary it
        p = MISS_P if seed == STORY_SEED else random.Random(seed).choice([1 / 500, 1 / 250, 1 / 100, 1 / 50])
        cmd.append("+missfile=" + miss_file(seed, p))
        if not any(x.startswith("+writes=") for x in plusargs) and seed != STORY_SEED:
            cmd.append("+writes=3000")
    try:
        p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return "FAIL", "ERROR the simulation did not finish in 300 s", ""
    log = p.stdout + p.stderr
    errs = [l.strip() for l in log.splitlines() if "ERROR" in l or "%Error" in l]
    ok = re.search(r"^PASS %s\b" % test, log, re.M) and not errs and p.returncode == 0
    pick = [e for e in errs if show and show in e] or errs
    cfg = re.search(r"^\[cfg\].*", log, re.M)
    return ("PASS" if ok else "FAIL"), (pick[0] if pick else ""), (cfg.group(0) if cfg else "")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("test", nargs="?", choices=TESTS, help="run one configuration instead of the suite")
    ap.add_argument("--broken", action="store_true", help="the broken scoreboard / receiver / monitor")
    ap.add_argument("--story", action="store_true", help="the episode's exact example (split, replay)")
    ap.add_argument("--nocheck", action="store_true", help="credit: no end-of-test credit check")
    ap.add_argument("--writes", type=int, help="credit: how many writes to send")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--seeds", type=int, default=10, help="regression seeds per test (default 10)")
    ap.add_argument("--sim", default="auto", choices=["auto", "verilator", "icarus"])
    a = ap.parse_args()

    os.makedirs(BUILD, exist_ok=True)
    if a.sim == "auto":
        a.sim = "verilator" if verilator_works() else "icarus"
    sim = Verilator() if a.sim == "verilator" else Icarus()
    print("simulator: %s" % sim.name)

    if a.test:
        plus = (["+story"] if a.story else []) + (["+nocheck"] if a.nocheck else [])
        plus += ["+writes=%d" % a.writes] if a.writes else []
        res, err, cfg = one(sim, a.test, a.broken, plus, a.seed)
        print(cfg)
        print(res, a.test, err)
        return 0 if res == "PASS" else 1

    bad = 0
    print("\n== the three breaks, as the episode tells them ==")
    for test, broken, plus, seed, expect, show, what in STORY:
        res, err, _ = one(sim, test, broken, plus, seed, show)
        mark = "ok  " if res == expect else "BAD "
        bad += res != expect
        print("  %s %-4s %-50s %s" % (mark, res, what, err[:96]))

    print("\n== regression: fixed designs and checkers, %d random seeds each ==" % a.seeds)
    for test in TESTS:
        seeds = [s for s in range(1, a.seeds + 1) if not (test == "credit" and s == STORY_SEED)]
        fails = []
        for seed in seeds:
            res, err, cfg = one(sim, test, False, [], seed)
            if res != "PASS":
                fails.append((seed, err, cfg))
        bad += len(fails)
        print("  %s %-8s %d/%d seeds pass" % ("ok  " if not fails else "BAD ", test,
                                             len(seeds) - len(fails), len(seeds)))
        for seed, err, cfg in fails[:3]:
            print("         seed %d: %s | %s" % (seed, cfg, err[:100]))

    print("\n%s" % ("ALL AS EXPECTED" if bad == 0 else "%d run(s) did not match" % bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
