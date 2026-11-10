#!/usr/bin/env python3
"""Run the ep24 CDC labs: the three breaks from the episode, then a regression.

Every break is shown the way the episode tells it: the broken design passes
plain simulation (green, and wrong), then fails once you add the technique
that sees it: metastability injection, a clock ratio that exposes it, or an
assertion. The fixed design then passes with everything switched on.

    python run.py                      # the whole story + 10-seed regression
    python run.py --seeds 50           # a longer regression
    python run.py bus --broken --inject          # one run, by hand
    python run.py pulse --broken --clocks fast2slow --seed 7
    python run.py --sim icarus         # force a simulator (default: verilator if it works)

Clocks follow tb/clk_cfg.sv (1-20 ns each, random phase, either side may be
faster) and are passed to the testbench as plusargs. Exit status is 0 only if
every run matched its expected result -- including the runs expected to FAIL.
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
SVA = [os.path.join("sva", "cdc_sva.sv"), os.path.join("sva", "cdc_bind.sv")]
TESTS = ["bus", "reconv", "pulse", "handshake", "fifo", "rst", "bridge"]

# (test, broken, inject, sva, clocks, expect, what it shows)
STORY = [
    ("bus",    True,  False, False, "any",       "PASS", "Break 1, plain sim: green, and wrong"),
    ("bus",    True,  True,  False, "any",       "FAIL", "Break 1 + injection: sees a value never held"),
    ("bus",    True,  False, True,  "any",       "FAIL", "Break 1 + Gray assertion: caught with no injection"),
    ("bus",    False, True,  True,  "any",       "PASS", "Fix: cross it as Gray code"),
    ("reconv", True,  False, False, "any",       "PASS", "Break 2, plain sim: green, and wrong"),
    ("reconv", True,  True,  False, "any",       "FAIL", "Break 2 + injection: a pairing that never happened"),
    ("reconv", False, True,  True,  "any",       "PASS", "Fix: cross the pair as one word (handshake)"),
    ("pulse",  True,  True,  False, "slow2fast", "PASS", "Break 3, slow->fast: the ratio hides it"),
    ("pulse",  True,  False, False, "fast2slow", "FAIL", "Break 3, fast->slow: pulses lost"),
    ("pulse",  True,  False, True,  "fast2slow", "FAIL", "Break 3 + width assertion: fires on the first pulse"),
    ("pulse",  False, True,  True,  "fast2slow", "PASS", "Fix: cross a toggle, not the pulse"),
    ("bridge", True,  False, False, "fast2slow", "PASS", "Final lab, AXI fast / APB slow: green"),
    ("bridge", True,  True,  False, "fast2slow", "FAIL", "Final lab + injection: caught"),
    ("bridge", True,  False, False, "slow2fast", "FAIL", "Final lab, APB clock faster: caught"),
    ("bridge", False, True,  True,  "any",       "PASS", "Fix: each direction crosses as one handshake"),
]


def pick_clocks(rng, mode):
    """clk_cfg's constraints, plus the two extremes the episode says to cover."""
    even = lambda lo, hi: rng.randrange(lo, hi + 1, 2)
    if mode == "fast2slow":
        src = even(1000, 5000)
        dst = even(3 * src, 20000)
    elif mode == "slow2fast":
        dst = even(1000, 5000)
        src = even(3 * dst, 20000)
    else:
        src, dst = even(1000, 20000), even(1000, 20000)
    return src, dst, rng.randrange(0, dst)            # skew_ps < dst_ps


class Icarus:
    name = "icarus"
    sva = False                                       # no concurrent assertions, no bind

    def __init__(self):
        self.cache = {}

    def build(self, test, defines):
        key = (test, tuple(sorted(defines)))
        if key not in self.cache:
            out = os.path.join(BUILD, "icarus_%s_%d.vvp" % (test, len(self.cache)))
            # the testbench goes first so its `timescale applies to the RTL after it
            cmd = ["iverilog", "-g2012", "-I", "tb", "-s", "tb_" + test, "-o", out]
            cmd += ["-D" + d for d in defines] + [os.path.join("tb", "tb_%s.sv" % test)] + RTL
            run_tool(cmd)
            self.cache[key] = out
        return ["vvp", "-n", self.cache[key]]


class Verilator:
    name = "verilator"
    sva = True

    def __init__(self):
        self.cache = {}

    def build(self, test, defines):
        key = (test, tuple(sorted(defines)))
        if key not in self.cache:
            mdir = os.path.join(BUILD, "verilator_%s_%d" % (test, len(self.cache)))
            cmd = verilator_cmd() + ["--binary", "-j", "0", "--timing", "--assert", "-Wno-fatal", "-Wno-lint",
                   "-Wno-style", "--timescale", "1ps/1ps", "-Itb", "--top-module", "tb_" + test,
                   "--Mdir", mdir, "-o", "sim"]
            cmd += ["-D" + d for d in defines] + RTL + SVA + [os.path.join("tb", "tb_%s.sv" % test)]
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


def one(sim, test, broken, inject, sva, clocks, seed):
    """Build (cached) and run one configuration; return (PASS|FAIL, first error, clock line)."""
    rng = random.Random(seed * 1009 + TESTS.index(test))
    src, dst, skew = pick_clocks(rng, clocks)
    defines = (["BROKEN"] if broken else []) + (["CDC_INJECT"] if inject else [])
    if sva and test == "pulse":                       # N fast cycles span one slow period
        defines.append("PULSE_N=%d" % max(1, -(-dst // src) + 1))
    if sim.sva and not sva:
        defines.append("NO_SVA_BIND")
    cmd = sim.build(test, defines)
    cmd += ["+src_ps=%d" % src, "+dst_ps=%d" % dst, "+skew_ps=%d" % skew, "+seed=%d" % seed]
    if sim.name == "verilator":
        cmd.append("+verilator+seed+%d" % seed)
    p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True, timeout=300)
    log = p.stdout + p.stderr
    errs = [l.strip() for l in log.splitlines() if "ERROR" in l or "%Error" in l or "Assertion failed" in l]
    ok = re.search(r"^PASS %s\b" % test, log, re.M) and not errs and p.returncode == 0
    clk = re.search(r"^\[clk\].*", log, re.M)
    return ("PASS" if ok else "FAIL"), (errs[0] if errs else ""), (clk.group(0) if clk else "")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("test", nargs="?", choices=TESTS, help="run one configuration instead of the suite")
    ap.add_argument("--broken", action="store_true", help="use the broken design from rtl/broken")
    ap.add_argument("--inject", action="store_true", help="define CDC_INJECT (metastability injection)")
    ap.add_argument("--no-sva", action="store_true", help="leave the assertions out (Verilator only)")
    ap.add_argument("--clocks", default="any", choices=["any", "fast2slow", "slow2fast"])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--seeds", type=int, default=10, help="regression seeds per test (default 10)")
    ap.add_argument("--sim", default="auto", choices=["auto", "verilator", "icarus"])
    a = ap.parse_args()

    os.makedirs(BUILD, exist_ok=True)
    if a.sim == "auto":
        a.sim = "verilator" if verilator_works() else "icarus"
    sim = Verilator() if a.sim == "verilator" else Icarus()
    print("simulator: %s%s" % (sim.name, "" if sim.sva else "  (no concurrent SVA: assertion runs are skipped)"))

    if a.test:
        res, err, clk = one(sim, a.test, a.broken, a.inject, sim.sva and not a.no_sva, a.clocks, a.seed)
        print(clk)
        print(res, a.test, err)
        return 0 if res == "PASS" else 1

    bad = 0
    print("\n== the three breaks, as the episode tells them, then the final lab ==")
    for test, broken, inject, sva, clocks, expect, what in STORY:
        if sva and not sim.sva:
            if expect == "FAIL":                      # the assertion is what catches it
                print("  skip      %-50s (needs SVA)" % what)
                continue
            sva = False                               # a fix still runs, scoreboard only
        res, err, _ = one(sim, test, broken, inject, sva, clocks, 1)
        mark = "ok  " if res == expect else "BAD "
        bad += res != expect
        print("  %s %-4s %-50s %s" % (mark, res, what, err[:90]))

    print("\n== regression: fixed designs, injection on, %d random clock seeds each ==" % a.seeds)
    for test in TESTS:
        fails = []
        for seed in range(1, a.seeds + 1):
            res, err, clk = one(sim, test, False, True, sim.sva, "any", seed)
            if res != "PASS":
                fails.append((seed, err, clk))
        bad += len(fails)
        print("  %s %-10s %d/%d seeds pass" % ("ok  " if not fails else "BAD ", test, a.seeds - len(fails), a.seeds))
        for seed, err, clk in fails[:3]:
            print("         seed %d: %s | %s" % (seed, clk, err[:100]))

    print("\n%s" % ("ALL AS EXPECTED" if bad == 0 else "%d run(s) did not match" % bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
