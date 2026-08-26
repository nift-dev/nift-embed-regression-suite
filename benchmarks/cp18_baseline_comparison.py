#!/usr/bin/env python3
"""CP18 part A - pre-Embed baseline (8a818f2) vs current canonical candidate.

Same generated projects, same workload definitions, interleaved/alternating
runs so machine drift does not favour one candidate. The baseline uses the
older CLI spelling (build-all); the candidate uses build --all. Reports
medians and candidate/baseline ratios. Measurements are evidence, not gates.
"""
import argparse, json, pathlib, statistics, subprocess, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument("--baseline", required=True)
ap.add_argument("--candidate", required=True)
ap.add_argument("--pages", type=int, default=10000)
ap.add_argument("--rounds", type=int, default=3)
a = ap.parse_args()


def write_project(root, pages, mode, threads=1, directories=None):
    (root / ".nift").mkdir(parents=True)
    (root / "content").mkdir()
    (root / "templates").mkdir()
    (root / "public").mkdir()
    (root / ".nift/config.json").write_text(json.dumps({"config": {
        "content-dir": "content/", "content-ext": ".html", "output-dir": "public/",
        "output-ext": ".html", "default-template": "templates/template.html",
        "build-threads": threads, "incremental-mode": mode, "minify-exts": []}}))
    (root / "templates/parts").mkdir(parents=True, exist_ok=True)
    (root / "templates/template.html").write_text(
        "@content\n@input(\"templates/parts/footer.html\")\n")
    tracked = []
    for i in range(pages):
        d = f"d{i % directories}" if directories else ""
        if directories:
            (root / "content" / d).mkdir(parents=True, exist_ok=True)
        tracked.append({"name": f"{d}/p{i}" if directories else f"p{i}",
                        "title": f"P{i}", "template": "templates/template.html"})
    (root / ".nift/tracked.json").write_text(
        json.dumps({"tracked": tracked}, separators=(",", ":")))
    for i in range(pages):
        d = f"d{i % directories}" if directories else ""
        (root / "content" / d / f"p{i}.html").write_text(f"<p>{i}</p>\n")
    (root / "templates/parts/footer.html").write_text("<footer>F</footer>\n")


def timed(binary, old_cli, root, *args):
    cmd = [binary]
    if old_cli and len(args) >= 2 and args[0] == "build" and args[1] == "--all":
        cmd += ["build-all"] + list(args[2:])
    else:
        cmd += list(args)
    start = time.perf_counter()
    p = subprocess.run(cmd, cwd=root, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE)
    if p.returncode:
        raise SystemExit(f"{cmd} failed: {p.stderr.decode(errors='replace')[:200]}")
    return time.perf_counter() - start


# workload(name, binary, old_cli) -> dict of metric: seconds, using a fresh temp project.
def w_flat(binary, old_cli, pages, mode, threads, directories, page_path_factory):
    with tempfile.TemporaryDirectory(prefix="nift-cp18cmp-") as td:
        root = pathlib.Path(td)
        write_project(root, pages, mode, threads=threads, directories=directories)
        timed(binary, old_cli, root, "build", "--all")
        page = page_path_factory(root, pages, directories)
        full = statistics.median(
            timed(binary, old_cli, root, "build", "--all") for _ in range(a.rounds))
        noop = statistics.median(
            timed(binary, old_cli, root, "build") for _ in range(a.rounds))
        original = page.read_text()
        page.write_text(original + "<!-- edit -->\n")
        single = timed(binary, old_cli, root, "build")
        page.write_text(original)
        timed(binary, old_cli, root, "build")
        footer = root / "templates/parts/footer.html"
        footer.write_text(footer.read_text() + "\n")
        shared = timed(binary, old_cli, root, "build")
        return {"full": full, "noop": noop, "single": single, "shared": shared}


def w_modes(binary, old_cli, mode):
    with tempfile.TemporaryDirectory(prefix="nift-cp18cmp-") as td:
        root = pathlib.Path(td)
        write_project(root, a.pages, mode, threads=-1)
        timed(binary, old_cli, root, "build", "--all")
        full = statistics.median(
            timed(binary, old_cli, root, "build", "--all") for _ in range(a.rounds))
        noop = statistics.median(
            timed(binary, old_cli, root, "build") for _ in range(a.rounds))
        return {"full": full, "noop": noop}


def flat_page(root, pages, directories):
    return root / "content" / f"p{pages // 2}.html"


def many_page(root, pages, directories):
    return root / "content" / f"d{(pages // 2) % directories}" / f"p{pages // 2}.html"


def interleaved(fn):
    """Run fn(tag, binary, old_cli) once per round, alternating which binary runs first."""
    def run():
        bvals, cvals = [], []
        for i in range(a.rounds):
            if i % 2 == 0:
                bvals.append(fn("b", a.baseline, True)["x"])
                cvals.append(fn("c", a.candidate, False)["x"])
            else:
                cvals.append(fn("c", a.candidate, False)["x"])
                bvals.append(fn("b", a.baseline, True)["x"])
        return statistics.median(bvals), statistics.median(cvals)
    return run


workloads = {
    "flat10k": lambda b, o: w_flat(b, o, a.pages, "modified", -1, None, flat_page),
    "manydir200": lambda b, o: w_flat(b, o, a.pages, "modified", -1, 200, many_page),
}
metrics = ["full", "noop", "single", "shared"]
print(f"rounds={a.rounds} pages={a.pages} (candidate/baseline ratio)")
for wname, wf in workloads.items():
    for metric in metrics:
        def make(tag, binary, old_cli, _wf=wf, _m=metric):
            return {"x": _wf(binary, old_cli)[_m]}
        bmed, cmed = interleaved(make)()
        print(f"{wname:12s} {metric:6s}: baseline={bmed:.6f}s candidate={cmed:.6f}s ratio={cmed/bmed:.2f}x")

for mode in ("modified", "hash", "hybrid"):
    for metric in ("full", "noop"):
        def make(tag, binary, old_cli, _m=mode, _mm=metric):
            return {"x": w_modes(binary, old_cli, _m)[_mm]}
        bmed, cmed = interleaved(make)()
        print(f"mode-{mode:8s} {metric:6s}: baseline={bmed:.6f}s candidate={cmed:.6f}s ratio={cmed/bmed:.2f}x")
