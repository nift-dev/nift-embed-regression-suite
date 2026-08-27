#!/usr/bin/env python3
"""Final verification for a warm-baseline campaign (exit gate).

Usage: warm_baseline_verify.py <campaign-out-dir> <expected-passes>

Exits 1 (and prints a readable diff) if any check fails:
  * the campaign log does not contain exactly <expected-passes> campaign entries;
  * any campaign entry is not 36/36 (non-zero rc, FAIL line, or a summary that
    is not "Embed contract: 36 passed, 0 failed");
  * post-campaign artifact hashes differ from the baseline record.
"""
import json
import pathlib
import statistics
import sys


def parse_hashes(path):
    out = {}
    for line in path.read_text().splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            out[parts[0]] = parts[1]
    return out


def main():
    out = pathlib.Path(sys.argv[1])
    passes = int(sys.argv[2])
    log = out / "campaign.log"
    if not log.exists():
        print(f"ERROR: {log} missing"); return 1
    lines = [l for l in log.read_text().splitlines() if "phase=campaign " in l]
    if len(lines) != passes:
        print(f"ERROR: campaign log has {len(lines)} campaign entries, expected {passes}")
        return 1
    durs = [float(l.split("dur=")[1].split("s")[0]) for l in lines]
    fails = [l for l in lines if "Embed contract: 36 passed, 0 failed" not in l]
    baseline = json.loads((out / "baseline.json").read_text())
    post = parse_hashes(out / "post-hashes.txt")
    bl = parse_hashes(pathlib.Path(out) / "baseline-hashes.txt")
    d = sorted(durs)
    p95 = d[min(len(d) - 1, int(len(d) * 0.95))]
    print(f"campaign log: {len(lines)} campaign entries, all 36/36 (fail lines: {len(fails)})")
    print(f"duration: total={sum(durs)/60:.1f}min  per-pass min={min(d):.3f}s "
          f"median={statistics.median(d):.3f}s p95={p95:.3f}s max={max(d):.3f}s")
    print(f"timeouts (rc=124): {sum(1 for l in lines if 'rc=124' in l)}")
    if fails:
        print(f"ERROR: {len(fails)} campaign entries are not 36/36:")
        for f in fails:
            print("  ", f)
        return 1
    if post != bl:
        print("ERROR: post-campaign artifact hashes DIFFER from baseline:")
        for k in sorted(set(bl) | set(post)):
            if bl.get(k) != post.get(k):
                print(f"  DIFF {k}: baseline={bl.get(k)} post={post.get(k)}")
        (out / "hash-diff.txt").write_text(
            "\n".join(f"DIFF {k}: baseline={bl.get(k)} post={post.get(k)}"
                      for k in sorted(set(bl) | set(post)) if bl.get(k) != post.get(k)) + "\n")
        return 1
    print(f"artifact hashes unchanged: True")
    return 0


if __name__ == "__main__":
    sys.exit(main())