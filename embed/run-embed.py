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
import resource
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ADAPTERS = {
    "cpp": HERE / "adapters" / "cpp-embed",
    "rust": HERE / "adapters" / "rust-embed",
    "c-abi": HERE / "adapters" / "c-abi",
    "go": HERE / "adapters" / "go-embed",
    "cs": HERE / "adapters" / "cs-embed",
    "js": HERE / "adapters" / "js-embed",
    "py": HERE / "adapters" / "py-embed",
}
CASES_DIR = HERE / "cases"

REQ_PATH_KEYS = ("current_output", "page_path", "template_path")


def matches_expected(expected, actual):
    """Match an adapter result against a frozen expectation.

    Normal fields must be JSON-equal. The `error` field is exact. The
    deliberately narrow `error_prefix` mode (implementation-detail diagnostics
    such as JSON parser wording) requires the actual error to start with the
    frozen prefix AND contain additional non-empty diagnostic text. A case may
    specify `error` or `error_prefix`, never both (validated at load time).
    """
    if expected.get("error_prefix") is not None:
        prefix = expected["error_prefix"]
        error = actual.get("error")
        if not isinstance(error, str) or not error.startswith(prefix):
            return False
        if len(error) <= len(prefix):
            return False
        rest = {k: v for k, v in actual.items() if k != "error"}
        rest_exp = {k: v for k, v in expected.items() if k != "error_prefix"}
        return rest == rest_exp
    return actual == expected


def load_cases():
    cases = []
    for path in sorted(CASES_DIR.glob("*.json")):
        case = json.loads(path.read_text())
        expected = case["expected"]
        if "error" in expected and "error_prefix" in expected:
            raise SystemExit(
                f"invalid corpus case {case['name']}: both 'error' and 'error_prefix' specified"
            )
        cases.append(case)
    return cases


FAILURES_DIR = HERE / "failures"


def _record_failure(case_name, adapter, argv, proc, wall, request):
    """Durably capture the full diagnostic of an adapter failure so no corpus
    failure can ever be lost to shell piping. Written even when the caller
    discards stdout; the file persists across runs (gitignored)."""
    import time as _time
    try:
        FAILURES_DIR.mkdir(parents=True, exist_ok=True)
        stamp = _time.strftime("%Y%m%d-%H%M%S")
        path = FAILURES_DIR / f"{stamp}-{adapter}.json"
        record = {
            "timestamp": stamp,
            "case": case_name,
            "adapter": adapter,
            "argv": argv,
            "returncode": proc.returncode,
            "signal": -proc.returncode if proc.returncode < 0 else None,
            "wall_time_s": round(wall, 4),
            "stdout": proc.stdout[:4000],
            "stderr": proc.stderr[:4000],
            "system_loadavg": os.getloadavg(),
            "parent_rlimits": {"cpu": resource.getrlimit(resource.RLIMIT_CPU),
                               "as": resource.getrlimit(resource.RLIMIT_AS),
                               "nofile": resource.getrlimit(resource.RLIMIT_NOFILE)},
            "request": request,
        }
        path.write_text(json.dumps(record, indent=2, ensure_ascii=False))
    except Exception as exc:  # pragma: no cover - diagnostics must never crash the runner
        try:
            (FAILURES_DIR / "error.log").open("a").write(f"{case_name} {adapter}: {exc}\n")
        except Exception:
            pass


def run_adapter(adapter, request, case_name=""):
    import time as _time
    argv = [str(adapter)]
    start = _time.perf_counter()
    proc = subprocess.run(argv, input=json.dumps(request), capture_output=True, text=True)
    wall = _time.perf_counter() - start
    if proc.returncode != 0:
        _record_failure(case_name, adapter.name, argv, proc, wall, request)
        detail = f"adapter crashed (rc={proc.returncode}): " + proc.stderr.strip()
        return {"ok": False, "error": detail}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        _record_failure(case_name, adapter.name, argv, proc, wall, request)
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
        results = {name: run_adapter(adapter, request, case["name"]) for name, adapter in ADAPTERS.items()}
        checks = {f"{name}==expected": matches_expected(expected, results[name]) for name in ADAPTERS}
        if "error_prefix" in expected:
            # Implementation-detail diagnostics (e.g. JSON parser wording) are
            # not byte-identical across adapters by contract; the invariant is
            # that every adapter satisfies the frozen expectation family.
            checks["all-equal"] = all(matches_expected(expected, r) for r in results.values())
        else:
            checks["all-equal"] = len({json.dumps(r, sort_keys=True) for r in results.values()}) == 1
        return case["name"], checks, results, expected
    finally:
        shutil.rmtree(root, ignore_errors=True)


def run_main():
    cases = load_cases()
    if not cases:
        print("error: no cases in", CASES_DIR, file=sys.stderr)
        return 1
    failures = 0
    for case in cases:
        name, checks, results, expected = run_case(case)
        if all(checks.values()):
            print("PASS", name)
        else:
            failures += 1
            print("FAIL", name)
            for key, ok in checks.items():
                if not ok:
                    print("   ", key, "false")
            print("      expected:", json.dumps(expected, sort_keys=True)[:220])
            for adapter_name, result in results.items():
                print(f"      {adapter_name:5}:", json.dumps(result, sort_keys=True)[:220])
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

    # 1. A perturbed frozen expectation must fail (all adapters wrong against
    #    it even though they agree with each other).
    perturbed = copy.deepcopy(target)
    if perturbed["expected"].get("ok"):
        perturbed["expected"]["output"] = "PERTURBED-EXPECTATION"
    else:
        perturbed["expected"]["error"] = "PERTURBED-EXPECTATION"
    _, checks, results, _ = run_case(perturbed)
    if results["cpp"] == results["rust"] == results["c-abi"]:
        print("  self-test: all adapters agree after perturbation (expected)")
    else:
        print("  self-test: adapters disagree after perturbation (unexpected)", file=sys.stderr)
        return 1
    if all(not checks[f"{name}==expected"] for name in ADAPTERS):
        print("  self-test: perturbed expectation correctly FAILS all adapters")
    else:
        print("  self-test: perturbed expectation did not fail (broken)", file=sys.stderr)
        return 1

    # 2. Agreement alone must never pass: force all adapters onto the same
    #    WRONG result (a different rendered output) while the frozen
    #    expectation is the original one. All adapters agree, but each must
    #    FAIL vs expected.
    composed = next(c for c in cases if c["name"] == "composed-text")
    broken = copy.deepcopy(composed)
    broken["request"] = dict(broken["request"])
    broken["request"]["page"] = "<h2>DIFFERENT</h2>"
    _, checks, results, _ = run_case(broken)
    if len({json.dumps(r, sort_keys=True) for r in results.values()}) != 1:
        print("  self-test: broken request gave different results (unexpected)", file=sys.stderr)
        return 1
    if all(not checks[f"{name}==expected"] for name in ADAPTERS):
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
