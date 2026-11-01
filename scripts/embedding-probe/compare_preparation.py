"""Verify frozen Library preparation timing and complete packet equivalence."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics

from selection import expand_report, summarize, canonical

ROOT = Path(__file__).resolve().parents[2]
PROTOCOL = ROOT / "Design/native/retrieval-quality/sort-performance-protocol.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def timing(work, output):
    if output.exists():
        raise ValueError("Output exists")
    protocol_bytes = PROTOCOL.read_bytes()
    policy = json.loads(protocol_bytes)
    runs = []
    values = {"baseline": {}, "optimized": {}}
    signatures = {}
    config = None
    for number in range(1, 4):
        for variant in ["baseline", "optimized"]:
            path = work / f"{variant}-{number}.json"
            data = path.read_bytes()
            run = json.loads(data)
            if not run["complete"] or not run["warmAndMeasuredSignaturesEqual"] or run["protocolSHA256"] != sha(protocol_bytes) or [q["queryID"] for q in run["queries"]] != policy["queryIDs"]:
                raise ValueError("Incomplete or changed timing run")
            if config is None:
                config = run["configurationSHA256"]
            if config != run["configurationSHA256"]:
                raise ValueError("Changed timing configuration")
            for q in run["queries"]:
                if not math.isfinite(q["seconds"]) or q["seconds"] <= 0:
                    raise ValueError("Invalid timing")
                signature = (q["indexSHA256"], q["preparedPassages"], q["keywordCandidates"])
                if q["queryID"] in signatures and signatures[q["queryID"]] != signature:
                    raise ValueError("Ordered rows or complete keyword ranking changed")
                signatures[q["queryID"]] = signature
                values[variant].setdefault(q["queryID"], []).append(q["seconds"])
            runs.append({"variant": variant, "number": number, "reportSHA256": sha(data), "queries": run["queries"]})
    medians = {name: statistics.median(v for group in per_query.values() for v in group) for name, per_query in values.items()}
    paired = [{"queryID": q, "baselineSeconds": statistics.median(values["baseline"][q]), "optimizedSeconds": statistics.median(values["optimized"][q])} for q in policy["queryIDs"]]
    for row in paired:
        row["optimizedToBaselineRatio"] = row["optimizedSeconds"] / row["baselineSeconds"]
    ratio = medians["optimized"] / medians["baseline"]
    passed = ratio <= .8 and all(r["optimizedToBaselineRatio"] <= 1.1 for r in paired)
    result = {"protocolSHA256": sha(protocol_bytes), "gatePassed": passed, "allFullIndexAndKeywordSignaturesEqual": True,
              "timedQueriesPerVariant": 21, "medianSeconds": medians, "optimizedToBaselineRatio": ratio,
              "medianReductionPercent": (1 - ratio) * 100, "perQueryMedians": paired, "runs": runs,
              "scope": "Warmed Release Mac production candidates, same exact inputs and driver. Input loading/signature generation excluded. No whole-app/cold-start/iPhone/model/provider latency claim."}
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: result[k] for k in ["gatePassed", "medianSeconds", "medianReductionPercent", "allFullIndexAndKeywordSignaturesEqual"]}))
    if not passed:
        raise ValueError("Frozen performance gate not met")


def packets(baseline, work, source, output):
    if output.exists():
        raise ValueError("Output exists")
    original = expand_report(json.loads(baseline.read_bytes()))
    current_path = output.with_suffix(".expanded.json")
    summarize(source, work, current_path)
    current = json.loads(current_path.read_bytes())
    fields = ["split", "protocolSHA256", "preparation", "metricControls", "languageCounts", "indexErrors", "policies", "cases"]
    changed = [key for key in fields if current[key] != original[key]]
    old_checks, new_checks = dict(original["nativeChecks"]), dict(current["nativeChecks"])
    old_checks.pop("seconds"); new_checks.pop("seconds")
    if old_checks != new_checks:
        changed.append("nativeChecks except seconds")
    result = {"split": current["split"], "allEqual": not changed, "changedFields": changed,
              "questions": len(current["cases"]), "policyPackets": sum(len(c["policies"]) for c in current["cases"]),
              "canonicalCasesSHA256": sha(canonical(current["cases"])), "canonicalPolicyMetricsSHA256": sha(canonical(current["policies"])),
              "publishedBaselineCompactSHA256": sha(baseline.read_bytes()), "currentNativeOutputSHA256": sha((work / "native.json").read_bytes()),
              "currentExpandedOutputSHA256": sha(current_path.read_bytes()), "nativeChecks": current["nativeChecks"],
              "scope": "Every complete per-query/per-policy source packet, offset/fingerprint/method/status/metric/language/index/privacy outcome equals the published development baseline; elapsed replay time is excluded. Held-out scores remain uncomputed."}
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: result[k] for k in ["split", "allEqual", "questions", "policyPackets", "changedFields"]}))
    if changed:
        raise ValueError("Published source packet behavior changed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    t = sub.add_parser("timing")
    for name in ["work", "output"]:
        t.add_argument(name, type=Path)
    p = sub.add_parser("packets")
    for name in ["baseline", "work", "source", "output"]:
        p.add_argument(name, type=Path)
    args = parser.parse_args()
    if args.mode == "timing":
        timing(args.work, args.output)
    else:
        packets(args.baseline, args.work, args.source, args.output)
