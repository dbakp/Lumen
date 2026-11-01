"""Independent public metrics and literal synthetic completion; no policy fitting."""
import argparse
from collections import Counter
import gzip
import importlib.util
import json
from pathlib import Path
import re
import string
import subprocess
import sys

from common import EVIDENCE, PROTOCOL_SHA, PUBLICATION, ROOT, checked, policy, save, sha


def normalize_public(text):
    # Implement independently from the official evaluator and compare every case.
    text = text.lower().translate(str.maketrans("", "", string.punctuation))
    return " ".join(re.sub(r"\b(?:a|an|the)\b", " ", text).split())


def public_score(prediction, golds):
    predicted = normalize_public(prediction).split()
    exact, f1 = 0, 0.0
    for gold in golds:
        expected = normalize_public(gold).split()
        exact = max(exact, int(predicted == expected))
        if not expected or not predicted:
            score = float(expected == predicted)
        else:
            overlap = sum(min(predicted.count(token), expected.count(token)) for token in set(predicted))
            score = 2.0 * overlap / (len(predicted) + len(expected))
        f1 = max(f1, score)
    return exact, f1


def literal_complete(prediction, aliases):
    value = " ".join(prediction.split())
    return any(value == " ".join(alias.split()) or value == " ".join(alias.split()) + "." for alias in aliases)


def read_run(work, name):
    prepared = json.loads((work / (name + "-prepared.json")).read_bytes())
    run = json.loads((work / (name + "-run-r1.json")).read_bytes())
    if prepared["protocolSHA256"] != PROTOCOL_SHA or run["protocolSHA256"] != PROTOCOL_SHA or run["inputsSHA256"] != prepared["inputsSHA256"]:
        raise ValueError("Changed published policy/input mapping")
    examples = [json.loads(line) for line in checked(work / (name + "-inputs.jsonl"), prepared["inputsSHA256"]).splitlines()]
    predictions = [json.loads(line) for line in checked(work / (name + "-predictions-r1.jsonl"), run["predictionsSHA256"]).splitlines()]
    labels = json.loads(checked(work / (name + "-labels.json"), prepared["labelsSHA256"]))
    if [q["id"] for q in examples] != [p["id"] for p in predictions] or set(labels) != {q["id"] for q in examples} or len(examples) != prepared["questions"]:
        raise ValueError("Incomplete quality denominator")
    for name, digest in run["producerSHA256AtStart"].items():
        checked(Path(__file__).with_name(name), digest)
    for example, prediction in zip(examples, predictions):
        if prediction["status"] == "inputLimit" or prediction["status"] not in ("noSource", "answered", "abstained", "scored"):
            raise ValueError("Incomplete/unscored quality case")
        if prediction["group"] != example["group"]:
            raise ValueError("Changed case group")
        candidate = prediction.get("bestCandidate")
        if candidate:
            a, b = candidate["start"], candidate["end"]
            region = next(r for r in example["regions"] if r["id"] == candidate["regionID"])
            if not region["start"] <= a < b <= region["end"] or candidate["sourceBodySHA256"] != region["bodySHA256"] or candidate["documentID"] != region.get("documentID"):
                raise ValueError("Invalid source ownership")
            if example["context"][a:b] != candidate["text"] or example["context"].encode()[candidate["byteStart"]:candidate["byteEnd"]] != candidate["text"].encode():
                raise ValueError("Invalid literal original span")
            if (prediction["nullMinusSpan"] > 0) != (prediction["status"] == "abstained"):
                raise ValueError("Changed fixed abstention decision")
            if prediction["answer"] != ("" if prediction["status"] == "abstained" else candidate["text"]):
                raise ValueError("Rewritten answer")
        elif prediction["answer"] or prediction["windows"] or prediction["status"] != "noSource" or example["regions"]:
            raise ValueError("Unexplained missing model output")
    return examples, predictions, labels, run


def evaluate(work, evidence=EVIDENCE):
    frozen = policy()
    evidence.mkdir(exist_ok=True)
    examples, predictions, labels, run = read_run(work, "public")
    receipt = json.loads((work / "evaluate-v2.0.py.receipt.json").read_bytes())
    evaluator = work / "evaluate-v2.0.py"
    checked(evaluator, receipt["sha256"])
    if receipt["gitBlobSHA"] != frozen["officialEvaluator"]["gitBlobSHA"]:
        raise ValueError("Changed official evaluator")
    # Full pinned source inspected before this import. Import does not run main.
    spec = importlib.util.spec_from_file_location("official_squad2", evaluator)
    official = importlib.util.module_from_spec(spec); spec.loader.exec_module(official)
    dataset_receipt = json.loads((work / "dev-v2.0.json.receipt.json").read_bytes())
    dataset = json.loads(checked(work / "dev-v2.0.json", dataset_receipt["sha256"]))["data"]
    source_rows = {qa["id"]: (qa, paragraph["context"]) for article in dataset for paragraph in article["paragraphs"] for qa in paragraph["qas"]}
    if len(source_rows) != 11873 or set(source_rows) != set(labels):
        raise ValueError("Incomplete official development set")
    pred_map = {row["id"]: row["answer"] for row in predictions}
    official_exact, official_f1 = official.get_raw_scores(dataset, pred_map)
    outcomes = []
    for example, prediction in zip(examples, predictions):
        key = example["id"]
        source, context = source_rows[key]
        if source["question"] != example["question"] or context != example["context"] or source["answers"] != labels[key]["answers"] or source["is_impossible"] != labels[key]["isImpossible"]:
            raise ValueError("Changed original public query/context/gold")
        golds = [answer["text"] for answer in labels[key]["answers"] if normalize_public(answer["text"])] or [""]
        exact, f1 = public_score(prediction["answer"], golds)
        if exact != official_exact[key] or abs(f1 - official_f1[key]) > 1e-12:
            raise ValueError("Independent/official per-case metric disagreement")
        candidate = prediction.get("bestCandidate")
        outcomes.append({"id": key, "answer": prediction["answer"], "status": prediction["status"],
            "answerable": not labels[key]["isImpossible"], "exact": exact, "f1": f1, "windows": prediction["windows"],
            "nullMinusSpan": prediction.get("nullMinusSpan"),
            "bestCandidate": {k: candidate[k] for k in ("text", "start", "end", "byteStart", "byteEnd", "tokens")} if candidate else None})
    metrics = {}
    for group, rows in [("all", outcomes), ("answerable", [q for q in outcomes if q["answerable"]]), ("unanswerable", [q for q in outcomes if not q["answerable"]])]:
        metrics[group] = {"questions": len(rows), "exactMatchPercent": 100 * sum(q["exact"] for q in rows) / len(rows),
                          "f1Percent": 100 * sum(q["f1"] for q in rows) / len(rows), "emptyAnswers": sum(not q["answer"] for q in rows)}
    save(evidence / "official-predictions-r1.json", pred_map)
    output = evidence / "official-metrics-r1.json"
    subprocess.run([sys.executable, str(evaluator), str(work / "dev-v2.0.json"), str(evidence / "official-predictions-r1.json"), "--out-file", str(output)], check=True)
    official_metrics = json.loads(output.read_bytes())
    for group, prefix in [("all", ""), ("answerable", "HasAns_"), ("unanswerable", "NoAns_")]:
        for ours, theirs in [("questions", "total"), ("exactMatchPercent", "exact"), ("f1Percent", "f1")]:
            if abs(metrics[group][ours] - official_metrics[prefix + theirs]) > 1e-10:
                raise ValueError("Official CLI aggregate mismatch")
    packed = evidence / "public-outcomes.jsonl.gz"
    if packed.exists():
        raise ValueError("Outcomes already exist")
    with packed.open("xb") as stream, gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0) as compressed:
        for row in outcomes:
            compressed.write((json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode())
    public_pass = metrics["all"]["exactMatchPercent"] >= 74 and metrics["all"]["f1Percent"] >= 77 and metrics["unanswerable"]["emptyAnswers"] / metrics["unanswerable"]["questions"] >= .70
    save(evidence / "public-results.json", {"protocolSHA256": PROTOCOL_SHA, "metrics": metrics, "officialCLI": official_metrics,
        "perCaseMetricComparisons": 2 * len(outcomes), "aggregateMetricComparisons": 9, "publicReproductionPassed": public_pass,
        "run": run, "outcomesSHA256": sha(packed.read_bytes()), "datasetReceipt": dataset_receipt, "evaluatorReceipt": receipt,
        "scope": "Full SQuAD2 development replication, not unseen generalization or clinical validation. No best-threshold/probability fitting. Public derived outcomes CC BY-SA4.0; see ATTRIBUTION.md."})
    examples, predictions, labels, synthetic_run = read_run(work, "synthetic")
    rows = []
    for example, prediction in zip(examples, predictions):
        gold = labels[example["id"]]
        supported = bool(gold["acceptableAnswers"])
        owner = prediction.get("bestCandidate", {}).get("documentID")
        complete = literal_complete(prediction["answer"], gold["acceptableAnswers"]) and owner in gold["expectedDocumentIDs"] if supported else not prediction["answer"]
        classification = "complete" if supported and complete else "abstained-supported" if supported and not prediction["answer"] else "nonmatching-supported" if supported else "unsupported-nonempty" if prediction["answer"] else "empty-unsupported"
        rows.append({"input": example, "gold": gold, "prediction": prediction, "strictPassed": complete, "classification": classification})
    groups = {}
    for group in ("baseline", "reranked", "stress"):
        members = [row for row in rows if row["input"]["group"] == group]
        supported = [r for r in members if r["gold"]["acceptableAnswers"]]
        unsupported = [r for r in members if not r["gold"]["acceptableAnswers"]]
        groups[group] = {"questions": len(members), "supported": len(supported), "supportedComplete": sum(r["strictPassed"] for r in supported),
                         "unsupported": len(unsupported), "unsupportedNonempty": sum(bool(r["prediction"]["answer"]) for r in unsupported),
                         "sourceEmpty": sum(r["prediction"]["status"] == "noSource" for r in members), "classificationCounts": dict(Counter(r["classification"] for r in members))}
    component_pass = any(groups[group]["supportedComplete"] >= 16 and groups[group]["unsupportedNonempty"] == 0 for group in ("baseline", "reranked")) and groups["stress"]["supportedComplete"] == 4 and groups["stress"]["unsupportedNonempty"] == 0
    save(evidence / "synthetic-results.json", {"protocolSHA256": PROTOCOL_SHA, "groups": groups, "syntheticComponentPassed": component_pass,
        "run": synthetic_run, "cases": rows, "scope": "Frozen self-authored development cases, not independent clinical evidence. Strict alias failures may contain correct facts plus extra wording; inspect qualitative review before interpreting them as factual errors."})
    save(evidence / "decision.json", {"protocolSHA256": PROTOCOL_SHA, "protocolPublicationCommit": PUBLICATION,
        "publicReproductionPassed": public_pass, "syntheticComponentPassed": component_pass, "integrityPassed": True,
        "advanceComponent": public_pass and component_pass, "appReaderPromoted": False,
        "applicationBaseline": frozen["applicationBaseline"], "heldOutTestScoresComputed": False,
        "decision": "Continue component work only" if public_pass and component_pass else "Reject this fixed reader policy; retain all failures and unchanged app",
        "scope": "Public reproduction cannot override synthetic completion/abstention failures or establish full conversational/clinical/provider/device quality."})
    print(json.dumps({"public": metrics, "synthetic": groups, "advance": public_pass and component_pass}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("work", type=Path)
    parser.add_argument("--output", type=Path, default=EVIDENCE)
    args = parser.parse_args()
    evaluate(args.work, args.output)
