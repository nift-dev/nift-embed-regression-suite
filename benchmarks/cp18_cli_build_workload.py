#!/usr/bin/env python3
"""CP18 part A - Nift CLI/build final performance workload.

Covers the roadmap's CLI/build split exactly:
  10k full build, no-op incremental, single-page incremental,
  shared-dependency rebuild, many-directory, modified/hash/hybrid modes.

Measurements are evidence, not gates: no correctness/semantic claims are made.
"""
import argparse, json, pathlib, statistics, subprocess, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument("--nift", required=True)
ap.add_argument("--pages", type=int, default=10000)
ap.add_argument("--runs", type=int, default=3)
a = ap.parse_args()


def timed(root, *args):
    start = time.perf_counter()
    p = subprocess.run([a.nift, *args], cwd=root,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if p.returncode:
        raise SystemExit(p.stderr.decode(errors="replace"))
    return time.perf_counter() - start


def write_project(root, pages, mode, threads=1, directories=None):
    (root / ".nift").mkdir(parents=True)
    (root / "content").mkdir()
    (root / "templates").mkdir()
    (root / "public").mkdir()
    (root / ".nift/config.json").write_text(json.dumps({"config": {
        "content-dir": "content/", "content-ext": ".html", "output-dir": "public/",
        "output-ext": ".html", "default-template": "templates/template.html",
        "build-threads": threads, "incremental-mode": mode, "minify-exts": []}}))
    tracked = [{"name": f"p{i}", "title": f"P{i}",
                "template": "templates/template.html"} for i in range(pages)]
    if directories:
        tracked = []
        for i in range(pages):
            d = f"d{i % directories}"
            (root / "content" / d).mkdir(parents=True, exist_ok=True)
            tracked.append({"name": f"{d}/p{i}", "title": f"P{i}",
                            "template": "templates/template.html"})
    (root / ".nift/tracked.json").write_text(
        json.dumps({"tracked": tracked}, separators=(",", ":")))
    (root / "templates/parts").mkdir(parents=True, exist_ok=True)
    (root / "templates/template.html").write_text("@content\n@input(\"templates/parts/footer.html\")\n")
    for i in range(pages):
        d = f"d{i % directories}" if directories else ""
        (root / "content" / d / f"p{i}.html").write_text(f"<p>{i}</p>\n")
    (root / "templates/parts/footer.html").write_text("<footer>F</footer>\n")


def measure_build_workload(root, pages, page_path=None):
    timed(root, "build", "--all")  # warm
    full = [timed(root, "build", "--all") for _ in range(a.runs)]
    noop = [timed(root, "build") for _ in range(a.runs)]
    page = root / "content" / f"p{pages // 2}.html" if page_path is None else page_path
    original = page.read_text()
    page.write_text(original + "<!-- edit -->\n")
    single = timed(root, "build")
    page.write_text(original)
    timed(root, "build")
    tpl = root / "templates/parts/footer.html"
    tpl.write_text(tpl.read_text() + "\n")
    shared = timed(root, "build")
    return statistics.median(full), statistics.median(noop), single, shared


results = {}

# 1. 10k full / no-op / single-page / shared-dependency (modified mode).
with tempfile.TemporaryDirectory(prefix="nift-cp18a-") as td:
    root = pathlib.Path(td) / "flat"
    root.mkdir()
    write_project(root, a.pages, "modified", threads=-1)
    full, noop, single, shared = measure_build_workload(root, a.pages)
    results["flat-10k"] = {"full": full, "noop": noop, "single": single, "shared": shared}
    print(f"flat 10k  full={full:.6f}s noop={noop:.6f}s single={single:.6f}s shared={shared:.6f}s")

# 2. many-directory: 10k pages spread across 200 directories.
with tempfile.TemporaryDirectory(prefix="nift-cp18a-") as td:
    root = pathlib.Path(td) / "many"
    root.mkdir()
    write_project(root, a.pages, "modified", threads=-1, directories=200)
    full, noop, single, shared = measure_build_workload(
        root, a.pages, page_path=root / "content" / f"d{(a.pages // 2) % 200}" / f"p{a.pages // 2}.html")
    results["manydir-200"] = {"full": full, "noop": noop, "single": single, "shared": shared}
    print(f"manydir200  full={full:.6f}s noop={noop:.6f}s single={single:.6f}s shared={shared:.6f}s")

# 3. incremental-mode comparison: modified / hash / hybrid (full + no-op).
for mode in ("modified", "hash", "hybrid"):
    with tempfile.TemporaryDirectory(prefix="nift-cp18a-") as td:
        root = pathlib.Path(td) / mode
        root.mkdir()
        write_project(root, a.pages, mode, threads=-1)
        timed(root, "build", "--all")
        full = [timed(root, "build", "--all") for _ in range(a.runs)]
        noop = [timed(root, "build") for _ in range(a.runs)]
        results[f"mode-{mode}"] = {
            "full": statistics.median(full), "noop": statistics.median(noop)}
        print(f"mode {mode:8s}  full={statistics.median(full):.6f}s "
              f"noop={statistics.median(noop):.6f}s")

print("CP18 part A complete (measurements are evidence, not gates)")
