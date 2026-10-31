"""Retain all per-query metrics, top-four choices and ranking digests, without text."""
import argparse
import copy
import hashlib
import json
from pathlib import Path


def compact(report):
    result = copy.deepcopy(report)
    for case in result["cases"]:
        ranking = case.pop("top100")
        case["top4"] = ranking[:4]
        case["top100SHA256"] = hashlib.sha256(json.dumps(ranking, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        case["firstJudgedRelevantRank"] = next((i + 1 for i, item in enumerate(ranking) if item["judgedRelevant"]), None)
        case["judgedRelevantAt100"] = sum(item["judgedRelevant"] for item in ranking)
    result["retention"] = "Every dev query and metric, all top-four selections/judgments, first relevant rank, relevant count@100 and full top100 digests retained; raw public text/vectors/full rankings remain outside Git"
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Output exists")
    data = args.input.read_bytes()
    result = compact(json.loads(data))
    result["fullReportSHA256"] = hashlib.sha256(data).hexdigest()
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
