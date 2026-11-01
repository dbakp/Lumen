"""All-case mechanical/coverage outcomes; semantic review remains explicit."""
import argparse
from collections import Counter
import json
from pathlib import Path

from common import EVIDENCE, PROTOCOL_SHA, ROOT, checked, file_digest, policy, save, sha
from contract import completion, validate


def whole_alias(answer, aliases):
    text = " ".join(answer.split())
    return any(text == " ".join(alias.split()) or text == " ".join(alias.split()) + "." for alias in aliases)


def evaluate(work):
    frozen = policy()
    run = json.loads((work / "run-complete.json").read_bytes())
    if run["protocolSHA256"] != PROTOCOL_SHA:
        raise ValueError("Changed completed run policy")
    examples = [json.loads(line) for line in checked(work / "synthetic-inputs.jsonl", run["inputsSHA256"]).splitlines()]
    outputs = [json.loads(line) for line in checked(work / "synthetic-outputs.jsonl", run["outputsSHA256"]).splitlines()]
    if len(examples) != len(outputs) or len(outputs) != 72 or [e["id"] for e in examples] != [o["id"] for o in outputs]:
        raise ValueError("Incomplete quality denominator")
    for name, digest in run["producerSHA256AtStart"].items():
        checked(Path(__file__).with_name(name), digest)
    gold_rows = json.loads(checked(EVIDENCE / "clause-gold.json", frozen["gold"]["sha256"]))["cases"]
    gold = {row["queryID"]: row for row in gold_rows}
    old = json.loads(checked(ROOT / frozen["synthetic"]["source"], frozen["synthetic"]["sha256"]))
    strict = {row["input"]["id"]: row["gold"] for row in old["cases"]}
    rows = []
    for example, output in zip(examples, outputs):
        key = example["id"]; expected = gold[key.split("/", 1)[1]]
        if output["seed"] != int(sha(key.encode())[:8], 16):
            raise ValueError("Changed per-case sampling seed")
        mechanical, error = None, None
        try:
            mechanical = validate(output["rawText"], example["sources"], output["generationComplete"])
        except (ValueError, RecursionError) as failure:
            error = str(failure)
        passed = completion(mechanical, expected, example["owners"]) if mechanical else False
        supported = bool(expected["requiredParts"])
        answer = mechanical["reply"]["answer"] if mechanical else None
        owners = [example["owners"][anchor["sourceID"]] for anchor in mechanical["anchors"]] if mechanical else []
        strict_pass = (whole_alias(answer, strict[key]["acceptableAnswers"]) and any(owner in strict[key]["expectedDocumentIDs"] for owner in owners)) if mechanical and supported else (not mechanical["reply"]["answerable"] if mechanical else False)
        rows.append({"input": example, "gold": expected, "rawOutput": output, "mechanical": mechanical,
            "mechanicalError": error, "literalClauseComplete": passed, "strictBatch33AliasDiagnostic": strict_pass,
            "semanticReview": "pending; exact quotes/literal coverage alone do not establish semantic entailment"})
    groups = {}
    for name in ("baseline", "reranked", "stress"):
        members = [row for row in rows if row["input"]["group"] == name]
        positive = [row for row in members if row["gold"]["requiredParts"]]
        negative = [row for row in members if not row["gold"]["requiredParts"]]
        groups[name] = {"questions": len(members), "supported": len(positive),
            "literalClauseComplete": sum(row["literalClauseComplete"] for row in positive),
            "strictBatch33AliasDiagnosticComplete": sum(row["strictBatch33AliasDiagnostic"] for row in positive),
            "unsupported": len(negative),
            "unsupportedNonemptyValidReplies": sum(bool(row["mechanical"] and row["mechanical"]["reply"]["answer"]) for row in negative),
            "unsupportedMechanicallyInvalid": sum(row["mechanical"] is None for row in negative),
            "unsupportedValidAbstentions": sum(row["literalClauseComplete"] for row in negative),
            "mechanicallyValid": sum(row["mechanical"] is not None for row in members),
            "emptySourceInputs": sum(not row["input"]["sources"] for row in members)}
    all_valid = all(row["mechanical"] is not None for row in rows)
    pipeline = any(groups[name]["literalClauseComplete"] >= 16 and groups[name]["unsupportedValidAbstentions"] == 15 for name in ("baseline", "reranked"))
    stress = groups["stress"]["literalClauseComplete"] == 4 and groups["stress"]["unsupportedValidAbstentions"] == 4
    mechanical_candidate = all_valid and pipeline and stress
    save(EVIDENCE / "synthetic-results.json", {"protocolSHA256": PROTOCOL_SHA, "run": run, "groups": groups,
        "allMechanicallyValid": all_valid, "mechanicalAndLiteralStageCandidate": mechanical_candidate,
        "publicStageAuthorizedByResults": False, "semanticReviewComplete": False, "cases": rows,
        "evaluatorSHA256": file_digest(Path(__file__)), "contractSHA256": file_digest(Path(__file__).with_name("contract.py")),
        "scope": "No public stage may start until every primary semantic review also passes. Invalid/incomplete output never gains abstention credit. Literal-clause coverage and strict Batch33 whole-alias diagnostic remain separate."})
    print(json.dumps({"groups": groups, "allMechanicallyValid": all_valid, "mechanicalAndLiteralStageCandidate": mechanical_candidate}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("work", type=Path)
    evaluate(parser.parse_args().work)
