#!/usr/bin/env python3
"""Run the ep20 AXI VIP lab: the three breaks, their fixes, then a regression.

The VIP is built once. Each break is the same test with one component swapped
in through the factory, the way the episode says a test overrides a piece
without editing the env (C1). In all three the two numbers come out green --
zero mismatches, 100% coverage -- and the run is still wrong. Each is caught
by a different part of the VIP: the scoreboard's count, the register model's
read-back, the protocol assertions on the pins. Each break fails here, each
fix passes, and the fixed VIP then passes a random regression.

    python run.py                          # the whole story + 10-seed regression
    python run.py --seeds 50               # a longer regression
    python run.py axi_test_no_strb         # one run, by hand
    python run.py axi_test --seed 7 --journey   # follow one register write and one write
    python run.py axi_test --busy 60 --txns 2000

Verilator only. The VIP is SystemVerilog classes with constraints, mailboxes,
virtual interfaces and a covergroup, and Icarus supports none of those yet.

Exit status is 0 only if every run matched its expected result -- including
the runs expected to FAIL.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
SOURCES = ["tb/axi_if.sv", "vip/uvm_lite.sv", "vip/axi_vip_pkg.sv", "rtl/axi_slave.sv",
           "sva/axi_sva.sv", "tb/tb_top.sv"]
TESTS = ["axi_test", "axi_test_no_sb", "axi_test_no_strb", "axi_test_backoff"]
TIMEOUT = 300                                  # seconds, per run

# (test, seed, expect, error to show, what it shows)
STORY = [
    ("axi_test_no_sb",   1, "FAIL", "scoreboard compared", "Break 1: coverage subscribed, scoreboard not"),
    ("axi_test",         1, "PASS", None,                  "Fix: connect the monitor to both"),
    ("axi_test_no_strb", 1, "FAIL", "RegModel",            "Break 2: an adapter that drops byte enables"),
    ("axi_test",         1, "PASS", None,                  "Fix: the adapter passes byte_en to WSTRB"),
    ("axi_test_backoff", 1, "FAIL", "WVALID dropped",      "Break 3: a driver that backs off when stalled"),
    ("axi_test",         1, "PASS", None,                  "Fix: once VALID is up, hold it until READY"),
]


class Verilator:
    name = "verilator"

    def __init__(self):
        self.sim = None

    def build(self):
        if self.sim is None:
            mdir = os.path.join(BUILD, "verilator")
            cmd = verilator_cmd() + ["--binary", "-j", "0", "--timing", "--assert", "-Wno-fatal",
                                     "-Wno-lint", "-Wno-style", "-Ivip", "--top-module", "tb_top",
                                     "--Mdir", mdir, "-o", "sim"] + SOURCES
            run_tool(cmd)
            self.sim = os.path.join(mdir, "sim")
        return [self.sim]


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


def one(sim, test, seed, extra=(), show=None, echo=False):
    """Run one test; return (PASS|FAIL, the error to show, the [report] line, the [cfg] line)."""
    cmd = sim.build() + ["+UVM_TESTNAME=" + test, "+seed=%d" % seed, "+verilator+seed+%d" % seed]
    cmd += list(extra)
    try:
        p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "FAIL", "ERROR hang: the simulation did not finish in %d s" % TIMEOUT, "", ""
    log = p.stdout + p.stderr
    if echo:
        print("\n".join(l for l in log.splitlines() if not l.startswith("- ")))
    errs = [l.strip() for l in log.splitlines() if "ERROR" in l or "%Error" in l]
    ok = re.search(r"^PASS %s\b" % test, log, re.M) and not errs and p.returncode == 0
    if not ok and not errs:
        errs = ["ERROR the run ended without a verdict (exit %d)" % p.returncode]
    pick = [e for e in errs if show and show in e] or errs
    err = re.sub(r"^\[cycle \d+\] ", "", pick[0]) if pick else ""
    rep = re.search(r"^\[report\] (\d+) mismatches, ([\d.]+)% covered", log, re.M)
    nums = "%s mismatches, %s%% covered" % rep.groups() if rep else "(no report)"
    cfg = re.search(r"^\[cfg\].*", log, re.M)
    return ("PASS" if ok else "FAIL"), err, nums, (cfg.group(0) if cfg else "")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("test", nargs="?", choices=TESTS, help="run one test instead of the suite")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--seeds", type=int, default=10, help="regression seeds (default 10)")
    ap.add_argument("--journey", action="store_true", help="print one register write's and one write's trip")
    ap.add_argument("--busy", type=int, help="percent of cycles the slave drops READY (default 25)")
    ap.add_argument("--txns", type=int, help="random transactions after configuration (default 300)")
    ap.add_argument("--sim", default="auto", choices=["auto", "verilator", "icarus"])
    a = ap.parse_args()

    os.makedirs(BUILD, exist_ok=True)
    if a.sim == "icarus":
        sys.exit("this lab runs on Verilator only: the VIP is SystemVerilog classes with constraints,\n"
                 "mailboxes, virtual interfaces and a covergroup, and Icarus supports none of those yet.")
    if not verilator_works():
        sys.exit("Verilator can't build here (it needs a C++ compiler and make; see README, Setup).\n"
                 "This lab runs on Verilator only.")
    sim = Verilator()
    print("simulator: %s" % sim.name)
    print("building the VIP (about a minute the first time)", flush=True)
    sim.build()

    if a.test:
        extra = (["+journey"] if a.journey else []) + (["+busy=%d" % a.busy] if a.busy is not None else [])
        extra += ["+txns=%d" % a.txns] if a.txns else []
        res, err, nums, cfg = one(sim, a.test, a.seed, extra, echo=a.journey)
        if not a.journey:
            print(cfg)
        print(res, a.test, "|", nums, "|", err)
        return 0 if res == "PASS" else 1

    bad = 0
    print("\n== the three breaks: both numbers green, and still wrong ==")
    for test, seed, expect, show, what in STORY:
        res, err, nums, _ = one(sim, test, seed, show=show)
        mark = "ok  " if res == expect else "BAD "
        bad += res != expect
        print("  %s %-4s %-46s %-30s %s" % (mark, res, what, nums, err[:100]))

    print("\n== regression: the fixed VIP, %d random seeds ==" % a.seeds)
    fails = []
    for seed in range(1, a.seeds + 1):
        res, err, nums, cfg = one(sim, "axi_test", seed)
        if res != "PASS":
            fails.append((seed, err, cfg))
    bad += len(fails)
    print("  %s %-10s %d/%d seeds pass" % ("ok  " if not fails else "BAD ", "axi_test",
                                         a.seeds - len(fails), a.seeds))
    for seed, err, cfg in fails[:3]:
        print("         seed %d: %s | %s" % (seed, cfg, err[:100]))

    print("\n%s" % ("ALL AS EXPECTED" if bad == 0 else "%d run(s) did not match" % bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
