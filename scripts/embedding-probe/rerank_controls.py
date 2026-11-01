"""Negative input/provenance controls for the research-only native reranker."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PROTOCOL = ROOT / "Design/native/retrieval-quality/rerank-protocol.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("helper", type=Path)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("pool", type=Path)
    parser.add_argument("scores", type=Path)
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    args.work.mkdir(exist_ok=False)
    original_pool = json.loads(args.pool.read_bytes())
    original_scores = json.loads(args.scores.read_bytes())
    first = next(i for i, q in enumerate(original_scores["cases"]) if len(q["scores"]) > 1)
    cases = []
    def test(name, update_pool=None, update_scores=None, update_protocol=None, update_configuration=None):
        folder = args.work / name
        folder.mkdir()
        pool, scores = copy.deepcopy(original_pool), copy.deepcopy(original_scores)
        if update_pool:
            update_pool(pool)
        if update_scores:
            update_scores(scores)
        pool_path, score_path = folder / "pool.json", folder / "scores.json"
        pool_path.write_text(json.dumps(pool))
        # Deliberately update the outer hash: inner live-source validation must
        # reject forged text/language/index-error metadata, not just its checksum.
        scores["poolSHA256"] = sha(pool_path)
        score_path.write_text(json.dumps(scores))
        protocol = PROTOCOL
        configuration = args.configuration
        if update_protocol:
            value = json.loads(PROTOCOL.read_bytes()); update_protocol(value)
            protocol = folder / "protocol.json"; protocol.write_text(json.dumps(value))
        if update_configuration:
            value = json.loads(args.configuration.read_bytes()); update_configuration(value)
            configuration = folder / "configuration.json"; configuration.write_text(json.dumps(value))
        output = folder / "unexpected-output.json"
        result = subprocess.run([str(args.helper), "--retrieval-rerank-select", str(configuration), str(protocol), str(pool_path), str(score_path), str(output)], capture_output=True, text=True)
        if result.returncode == 0 or output.exists() or not result.stderr.strip():
            raise ValueError("Forged input was not rejected: " + name)
        cases.append({"name": name, "rejected": True, "exitCode": result.returncode, "diagnostic": result.stderr.strip()[:600], "diagnosticSHA256": hashlib.sha256(result.stderr.encode()).hexdigest()})
    test("changed-published-protocol", update_protocol=lambda p: p.update(hypothesis="Changed declared hypothesis"))
    test("changed-frozen-configuration", update_configuration=lambda c: c.update(sourceLabel="Changed source"))
    test("changed-passage-text", update_pool=lambda p: p["cases"][first]["pool"][0].update(text="FORGED-SOURCE"))
    def fake_language(pool):
        pool["cases"][first]["language"] = "zz"
        pool["cases"][first]["pool"] = []
    def skip(scores):
        scores["cases"][first].update(status="unsupportedLanguage", scores=[])
    test("forged-language-fallback", update_pool=fake_language, update_scores=skip)
    def fake_error(pool):
        pool["cases"][first].update(indexError="queryLength", pool=[], baseline=[])
    test("forged-index-error", update_pool=fake_error, update_scores=lambda s: s["cases"][first].update(status="indexError", scores=[]))
    test("changed-live-index-count", update_pool=lambda p: p["cases"][first].update(indexedPassages=1))
    test("duplicate-score-row", update_scores=lambda s: s["cases"][first]["scores"].__setitem__(1, copy.deepcopy(s["cases"][first]["scores"][0])))
    test("missing-score-pair", update_scores=lambda s: s["cases"][first]["scores"].pop())
    test("changed-pair-input-hash", update_scores=lambda s: s["cases"][first]["scores"][0].update(inputSHA256="0" * 64))
    test("changed-prepared-identity", update_scores=lambda s: s["cases"][first]["scores"][0].update(preparedID="999999"))
    test("nonfinite-score", update_scores=lambda s: s["cases"][first]["scores"][0].update(score=float("nan")))
    test("changed-model-weight-pin", update_scores=lambda s: s.update(weightsSHA256="0" * 64))
    test("changed-score-query", update_scores=lambda s: s["cases"][first].update(queryID="unknown-query"))
    test("reordered-score-pairs", update_scores=lambda s: s["cases"][first]["scores"].reverse())
    report = {"passed": len(cases), "cases": cases, "inputs": {"protocol": sha(PROTOCOL), "pool": sha(args.pool), "scores": sha(args.scores), "helper": sha(args.helper), "source": sha(Path(__file__))}, "scope": "Malformed/forged input rejection, including self-consistent outer checksum mutations; no ranking, entailment or clinical accuracy claim."}
    (args.work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": len(cases)}))


if __name__ == "__main__":
    main()
