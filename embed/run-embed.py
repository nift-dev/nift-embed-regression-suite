#!/usr/bin/env python3
"""Nift Embed contract runner (capability layer 2).

Each case in embed/cases/ is CASE + FROZEN EXPECTATION (static data committed
to the repository). The runner does NOT derive expectations from any
implementation:

    CASE + EXPECTATION
         |            \
         |             \
   C++ adapter    nift-rs adapter
         |             |
   result ---- compare ---- result
         |      (secondary invariant)
         v
   C++ == EXPECTATION and nift-rs == EXPECTATION

Cross-implementation equality is reported as an additional invariant, never as
the definition of correctness.

Run:
    CPP_HARNESS=... RUST_HARNESS=... ./embed/run-embed.py
    ./embed/run-embed.py --self-test     # negative checks
"""
import argparse
import copy
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ADAPTERS = {
    "cpp": HERE / "adapters" / "cpp-embed",
    "rust": HERE / "adapters" / "rust-embed",
}
CASES_DIR = HERE / "cases"

REQ_PATH_KEYS = ("current_output", "page_path", "template_path")


def load_cases():
    cases = []
    for path in sorted(CASES_DIR.glob("*.json")):
        cases.append(json.loads(path.read_text()))
    return cases


def run_adapter(adapter, request):
    proc = subprocess.run(
        [str(adapter)], input=json.dumps(request), capture_output=True, text=True
    )
    if proc.returncode != 0:
        return {"ok": False, "error": "adapter crashed: " + proc.stderr.strip()}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"ok": False, "error": "adapter emitted non-JSON: " + proc.stdout.strip()}


def build_request(root, request):
    req = dict(request)
    req["root"] = str(root)
    for key in REQ_PATH_KEYS:
        value = req.get(key)
        if value:
            req[key] = str((root / value).resolve())
    return req


def run_case(case):
    root = pathlib.Path(tempfile.mkdtemp(prefix="nift-embed-case-"))
    try:
        for rel, content in case.get("fixture", {}).items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        request = build_request(root, case["request"])
        expected = case["expected"]
        cpp = run_adapter(ADAPTERS["cpp"], request)
        rust = run_adapter(ADAPTERS["rust"], request)
        checks = {
            "cpp==expected": cpp == expected,
            "rust==expected": rust == expected,
            "cpp==rust": cpp == rust,
        }
        return case["name"], checks, cpp, rust, expected
    finally:
        shutil.rmtree(root, ignore_errors=True)


def run_main():
    cases = load_cases()
    if not cases:
        print("error: no cases in", CASES_DIR, file=sys.stderr)
        return 1
    failures = 0
    for case in cases:
        name, checks, cpp, rust, expected = run_case(case)
        if all(checks.values()):
            print("PASS", name)
        else:
            failures += 1
            print("FAIL", name)
            for key, ok in checks.items():
                if not ok:
                    print("   ", key, "false")
                    print("      expected:", json.dumps(expected, sort_keys=True)[:220])
                    print("      cpp     :", json.dumps(cpp, sort_keys=True)[:220])
                    print("      rust    :", json.dumps(rust, sort_keys=True)[:220])
    print()
    print(f"Embed contract: {len(cases) - failures} passed, {failures} failed")
    return 1 if failures else 0


def run_self_test():
    """Negative checks: the suite must FAIL when an expectation is wrong, and
    must FAIL when both adapters agree on the same wrong result."""
    cases = load_cases()
    if not cases:
        print("error: no cases", file=sys.stderr)
        return 1
    target = cases[0]

    # 1. A perturbed frozen expectation must fail (C++ and Rust both wrong
    #    against it even though they agree with each other).
    perturbed = copy.deepcopy(target)
    if perturbed["expected"].get("ok"):
        perturbed["expected"]["output"] = "PERTURBED-EXPECTATION"
    else:
        perturbed["expected"]["error"] = "PERTURBED-EXPECTATION"
    _, checks, cpp, rust, _ = run_case(perturbed)
    if cpp == rust:
        print("  self-test: both adapters agree after perturbation (expected)")
    else:
        print("  self-test: adapters disagree after perturbation (unexpected)", file=sys.stderr)
        return 1
    if not checks["cpp==expected"] and not checks["rust==expected"]:
        print("  self-test: perturbed expectation correctly FAILS both adapters")
    else:
        print("  self-test: perturbed expectation did not fail (broken)", file=sys.stderr)
        return 1

    # 2. Agreement alone must never pass: force both adapters onto the same
    #    WRONG result (a different rendered output) while the frozen
    #    expectation is the original one. cpp==rust holds, but both must FAIL
    #    vs expected.
    composed = next(c for c in cases if c["name"] == "composed-text")
    broken = copy.deepcopy(composed)
    broken["request"] = dict(broken["request"])
    broken["request"]["page"] = "<h2>DIFFERENT</h2>"
    _, checks, cpp, rust, _ = run_case(broken)
    if cpp != rust:
        print("  self-test: broken request gave different results (unexpected)", file=sys.stderr)
        return 1
    if not checks["cpp==expected"] and not checks["rust==expected"]:
        print("  self-test: agreement-only result correctly FAILS against expectation")
    else:
        print("  self-test: agreement-only result passed (broken)", file=sys.stderr)
        return 1

    print("self-test: negative checks passed (suite cannot be gamed by agreement)")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return run_self_test()
    return run_main()


if __name__ == "__main__":
    sys.exit(main())
