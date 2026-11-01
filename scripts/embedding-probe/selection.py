"""Dev-only verified-vector replay through the actual native source selector."""
import argparse
from collections import Counter
import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile

import numpy as np
import pytrec_eval
from corpus import load_dev
from evaluate import load_matrix, metric_controls
from query_variant import instruction_queries
from challenge import inputs as challenge_inputs, SOURCE_LABEL

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "Design/native/retrieval-quality"
MEASURES = {"ndcg_cut.4", "P.4", "recall.4"}
NAMES = ["ndcg_cut_4", "P_4", "recall_4"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_input(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Unsafe or missing input")
    return {"path": str(path.resolve()), "sha256": sha(path.read_bytes())}


def protocol():
    path = EVIDENCE / "selection-protocol.json"
    value = json.loads(path.read_bytes())
    if value["name"] != "complete-selection-dev-replay" or value["applicationBaseline"] != "04678c0d952d90972041c7ff9d4b90951f879342":
        raise ValueError("Undeclared replay")
    for name, key in [("retrieval-protocol.json", "retrievalProtocolSHA256"), ("instruction-protocol.json", "instructionProtocolSHA256"), ("instruction-dev-decision.json", "instructionDecisionSHA256"), ("challenge-protocol.json", "challengeProtocolSHA256"), ("corpus-native-receipts.json", "nativeReceiptsSHA256")]:
        if sha((EVIDENCE / name).read_bytes()) != value["inputs"][key]:
            raise ValueError("Frozen prior protocol or input changed")
    if sha((ROOT / "Tests/Fixtures/RetrievalChallenge.json").read_bytes()) != value["inputs"]["challengeFixtureSHA256"]:
        raise ValueError("Frozen challenge changed")
    return path, value


def prepare(source, probe, work, split):
    protocol_path, frozen = protocol()
    if work.exists():
        raise ValueError("Output exists")
    if split == "dev":
        qrels, raw_queries, corpus_ids = load_dev(source)
        corpus = source / "nfcorpus/corpus.jsonl"
        prepared_folder = probe / "corpus-prepared"
        corpus_folders = {m: probe / (m + "-corpus") for m in ["baseline", "candidate"]}
        query_folders = {"baseline": probe / "baseline-dev", "candidate": probe / "instruction-dev"}
        expected = {}
        label = "BEIR NFCorpus public research"
    else:
        _, _, fixture, corpus_bytes, raw_queries, _ = challenge_inputs()
        challenge = probe / "challenge"
        corpus = challenge / "corpus.jsonl"
        if corpus.read_bytes() != corpus_bytes:
            raise ValueError("Changed synthetic corpus")
        corpus_ids = {d["id"] for d in fixture["documents"]}
        expected = {q["id"]: q["expectedDocumentIDs"] for q in fixture["queries"]}
        prepared_folder = challenge / "prepared"
        corpus_folders = {m: challenge / (m + "-corpus") for m in ["baseline", "candidate"]}
        query_folders = {m: challenge / (m + "-queries") for m in ["baseline", "candidate"]}
        label = SOURCE_LABEL
    instructed, _ = instruction_queries(raw_queries)
    prepared_path = prepared_folder / "passages.jsonl"
    prepared_bytes = prepared_path.read_bytes()
    preparation = json.loads((prepared_folder / "preparation.json").read_bytes())
    passages = [json.loads(line) for line in prepared_bytes.decode().splitlines()]
    if preparation["inputSHA256"] != sha(corpus.read_bytes()) or preparation["preparedSHA256"] != sha(prepared_bytes) or preparation["limited"] or preparation["unrepresentedDocumentIDs"] or preparation["documents"] != len(corpus_ids) or preparation["searchedDocuments"] != len(corpus_ids) or len(passages) != preparation["passages"] or {p["documentID"] for p in passages} != corpus_ids:
        raise ValueError("Incomplete or changed passage preparation")
    models, spots, receipts = [], [], {}
    work.mkdir(parents=True, exist_ok=False)
    (work / "original-queries.jsonl").write_bytes(raw_queries)
    native_pins = json.loads((EVIDENCE / "corpus-native-receipts.json").read_bytes())
    instruction_pin = json.loads((EVIDENCE / "instruction-native-receipt.json").read_bytes())
    for model, query_bytes in [("baseline", raw_queries), ("candidate", instructed)]:
        corpus_folder, query_folder = corpus_folders[model], query_folders[model]
        cr, vectors = load_matrix(corpus_folder, "passages", sha(prepared_bytes), passages)
        qr, query_vectors = load_matrix(query_folder, "queries", sha(query_bytes), [json.loads(line) for line in query_bytes.decode().splitlines()])
        pin = native_pins[model + "-corpus"]
        if cr["compiledModelFiles"] != qr["compiledModelFiles"] or cr["compiledModelFiles"] != pin["compiledModelFiles"] or cr["vocabularySHA256"] != qr["vocabularySHA256"] or cr["vocabularySHA256"] != pin["vocabularySHA256"]:
            raise ValueError("Mismatched or unpinned model pair")
        if split == "dev":
            query_pin = instruction_pin if model == "candidate" else native_pins["baseline-dev"]
            if qr["matrixSHA256"] != query_pin["matrixSHA256"] or qr["inputSHA256"] != query_pin["inputSHA256"] or cr["matrixSHA256"] != pin["matrixSHA256"]:
                raise ValueError("Changed frozen dev vectors")
        offsets = np.array([r["offset"] for r in cr["rows"]], dtype=np.int64)
        result = np.full((len(qr["rows"]), len(passages)), -1., dtype="<f8")
        for n, row in enumerate(qr["rows"]):
            if row["status"] == "used":
                window_scores = np.clip(vectors @ query_vectors[row["offset"]], -1., 1.)
                result[n] = np.maximum.reduceat(window_scores, offsets)
        score_path = work / (model + "-scores.f64le")
        with score_path.open("xb") as stream:
            result.tofile(stream)
        models.append({"id": model, "scores": file_input(score_path), "queryStatuses": [r["status"] for r in qr["rows"]]})
        # Native comparison receives ORIGINAL Float32 components, not normalized
        # Double values; it checks the production cosine including every window.
        original_passages = np.frombuffer((corpus_folder / "vectors.f32le").read_bytes(), dtype="<f4").reshape(-1, 384)
        original_queries = np.frombuffer((query_folder / "vectors.f32le").read_bytes(), dtype="<f4").reshape(-1, 384)
        q_indices = sorted({0, len(qr["rows"]) // 2, len(qr["rows"]) - 1})
        p_indices = {0, len(passages) // 2, len(passages) - 1}
        multiwindow = next((i for i, r in enumerate(cr["rows"]) if r["vectors"] > 1), None)
        if multiwindow is not None:
            p_indices.add(multiwindow)
        for qi in q_indices:
            if qr["rows"][qi]["status"] != "used":
                raise ValueError("A native cosine control query was rejected")
            for pi in sorted(p_indices):
                r = cr["rows"][pi]
                spots.append({"model": model, "queryIndex": qi, "passageIndex": pi, "queryVector": original_queries[qr["rows"][qi]["offset"]].tolist(), "windows": original_passages[r["offset"]:r["offset"] + r["vectors"]].tolist()})
        receipts[model] = {"corpusReceipt": file_input(corpus_folder / "complete.json"), "queryReceipt": file_input(query_folder / "complete.json"), "matrixSHA256": cr["matrixSHA256"], "queryMatrixSHA256": qr["matrixSHA256"], "scoreMatrix": file_input(score_path), "queryStatuses": dict(Counter(r["status"] for r in qr["rows"]))}
    queries = [json.loads(line) for line in raw_queries.decode().splitlines()]
    config = {"version": 1, "split": split, "protocolFile": file_input(protocol_path), "corpus": file_input(corpus), "queries": file_input(work / "original-queries.jsonl"), "prepared": file_input(prepared_path), "sourceLabel": label, "expectedDocuments": len(corpus_ids), "expectedQueries": len(queries), "expectedPassages": len(passages), "models": models, "spots": spots, "expectedSources": expected}
    (work / "configuration.json").write_text(json.dumps(config, separators=(",", ":")) + "\n")
    (work / "preparation-receipt.json").write_text(json.dumps({"split": split, "protocolSHA256": sha(protocol_path.read_bytes()), "configurationSHA256": sha((work / "configuration.json").read_bytes()), "queries": len(queries), "passages": len(passages), "documents": len(corpus_ids), "models": receipts, "nativeCosineSpots": len(spots), "testRetrievalScoresComputed": False}, indent=2) + "\n")
    print(json.dumps({"prepared": split, "queries": len(queries), "passages": len(passages), "nativeCosineSpots": len(spots)}))


def unique_documents(passages):
    return list(dict.fromkeys(p["documentID"] for p in passages))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def expand_report(value):
    if value.get("compactSchema") != 1:
        raise ValueError("Unknown compact schema")
    expanded = copy.deepcopy(value)
    table = expanded.pop("policyResults")
    expected = expanded.pop("expandedOutcomeCanonicalSHA256")
    expanded.pop("compactSchema")
    if any(sha(canonical(result)) != key for key, result in table.items()):
        raise ValueError("Changed compact result")
    for case in expanded["cases"]:
        case["policies"] = [{"id": item["id"], **table[item["result"]]} for item in case["policies"]]
    if sha(canonical(expanded)) != expected:
        raise ValueError("Compact round-trip changed the complete outcome")
    return expanded


def compact_report(input_path, output):
    if output.exists():
        raise ValueError("Output exists")
    original = json.loads(input_path.read_bytes())
    compact = copy.deepcopy(original)
    table = {}
    for case in compact["cases"]:
        references = []
        for item in case["policies"]:
            result = {k: v for k, v in item.items() if k != "id"}
            key = sha(canonical(result))
            if key in table and table[key] != result:
                raise ValueError("Result hash collision")
            table[key] = result
            references.append({"id": item["id"], "result": key})
        case["policies"] = references
    compact.update(compactSchema=1, policyResults=table, expandedOutcomeCanonicalSHA256=sha(canonical(original)))
    if expand_report(compact) != original:
        raise ValueError("Incomplete compact outcome")
    output.write_text(json.dumps(compact, indent=2, sort_keys=True) + "\n")
    # Verify the saved representation, not just the in-memory transformation.
    if expand_report(json.loads(output.read_bytes())) != original:
        raise ValueError("Saved compact outcome changed")
    print(json.dumps({"allCasesPreserved": len(original["cases"]), "distinctPolicyResults": len(table), "bytesBefore": input_path.stat().st_size, "bytesAfter": output.stat().st_size, "exactRoundTrip": True}))


def summarize(source, work, output):
    protocol_path, _ = protocol()
    native = json.loads((work / "native.json").read_bytes())
    receipt = json.loads((work / "preparation-receipt.json").read_bytes())
    if not native["complete"] or native["protocolSHA256"] != sha(protocol_path.read_bytes()) or native["configurationSHA256"] != receipt["configurationSHA256"] or len(native["cases"]) != receipt["queries"]:
        raise ValueError("Incomplete native replay")
    checked_packets = 0
    for case in native["cases"]:
        for item in case["policies"]:
            passages = item["passages"]
            if len(passages) > 4 or any(count > 2 for count in Counter(p["documentID"] for p in passages).values()):
                raise ValueError("Native source-packet budget exceeded")
            for n, left in enumerate(passages):
                if left["end"] <= left["start"] or left["end"] - left["start"] > 900:
                    raise ValueError("Invalid original passage interval")
                if any(left["documentID"] == right["documentID"] and left["start"] < right["end"] and right["start"] < left["end"] for right in passages[n + 1:]):
                    raise ValueError("Overlapping native source excerpts")
            checked_packets += 1
    controls = metric_controls()
    oracle = pytrec_eval.RelevanceEvaluator({"q": {"a": 2, "b": 1, "c": 1}}, MEASURES).evaluate({"q": {"b": 3., "x": 2., "a": 1.}})["q"]
    if not math.isclose(oracle["ndcg_cut_4"], 2 / (2 + 1 / math.log2(3) + .5), abs_tol=1e-12) or oracle["P_4"] != .5 or oracle["recall_4"] != 2 / 3 or unique_documents([{"documentID": "a"}, {"documentID": "a"}, {"documentID": "b"}]) != ["a", "b"]:
        raise ValueError("Packet metric oracle")
    controls["packetConvention"] = "Duplicate excerpts consume source slots; unique document IDs keep first-selected order and P@4 denominator stays4. Graded@4/missing-result/duplicate oracle passes."
    controls["nativePacketInvariantChecks"] = checked_packets
    ids = [r["id"] for r in native["cases"][0]["policies"]]
    if any([r["id"] for r in c["policies"]] != ids for c in native["cases"]):
        raise ValueError("Partial policy cases")
    summaries = []
    if native["split"] == "dev":
        qrels, _, _ = load_dev(source)
        if {c["queryID"] for c in native["cases"]} != set(qrels) or len(native["cases"]) != len(qrels):
            raise ValueError("Incomplete dev denominator")
        evaluator = pytrec_eval.RelevanceEvaluator(qrels, MEASURES)
        baseline = None
        for policy_id in ids:
            ranking = {}
            selected = {}
            for case in native["cases"]:
                item = next(p for p in case["policies"] if p["id"] == policy_id)
                docs = unique_documents(item["passages"])
                ranking[case["queryID"]] = {doc: float(4 - n) for n, doc in enumerate(docs)}
                selected[case["queryID"]] = item
            values = evaluator.evaluate(ranking)
            if policy_id == "minilm-production-042":
                baseline = values
            row = {"id": policy_id, "denominatorQueries": len(qrels), **{n: sum(values.get(q, {}).get(n, 0.) for q in qrels) / len(qrels) for n in NAMES}, "hit_4": sum(any(qrels[q].get(d, 0) > 0 for d in ranking[q]) for q in qrels) / len(qrels), "queriesWithResults": sum(bool(ranking[q]) for q in qrels), "queriesWithoutJudgedRelevantSource": sum(not any(qrels[q].get(d, 0) > 0 for d in ranking[q]) for q in qrels), "statusCounts": dict(Counter(p.get("status", "searchError") for p in selected.values())), "selectedPassages": sum(len(p["passages"]) for p in selected.values()), "selectedUniqueDocuments": sum(len(r) for r in ranking.values())}
            if policy_id.startswith("medembed"):
                if baseline is None:
                    raise ValueError("Missing baseline")
                changes = [values.get(q, {}).get("ndcg_cut_4", 0.) - baseline.get(q, {}).get("ndcg_cut_4", 0.) for q in qrels]
                row["pairedNDCG4AgainstProductionBaseline"] = {"improved": sum(v > 1e-12 for v in changes), "worsened": sum(v < -1e-12 for v in changes), "unchanged": sum(abs(v) <= 1e-12 for v in changes), "meanDelta": sum(changes) / len(changes)}
            for case in native["cases"]:
                item = selected[case["queryID"]]
                item["metrics"] = values.get(case["queryID"], {n: 0. for n in NAMES})
                item["uniqueDocumentIDs"] = list(ranking[case["queryID"]])
                for passage in item["passages"]:
                    passage["judgment"] = qrels[case["queryID"]].get(passage["documentID"])
            summaries.append(row)
    else:
        _, _, fixture, _, _, _ = challenge_inputs()
        labels = {q["id"]: q for q in fixture["queries"]}
        if set(labels) != {c["queryID"] for c in native["cases"]}:
            raise ValueError("Incomplete challenge denominator")
        for policy_id in ids:
            hit1 = hit4 = unsupported = 0
            groups = {}
            for case in native["cases"]:
                label = labels[case["queryID"]]
                item = next(p for p in case["policies"] if p["id"] == policy_id)
                docs = unique_documents(item["passages"])
                expected = set(label["expectedDocumentIDs"])
                group = groups.setdefault(label["kind"], {"queries": 0, "hit4" if expected else "withAnySource": 0})
                group["queries"] += 1
                if expected:
                    hit1 += bool(set(docs[:1]) & expected)
                    hit4 += bool(set(docs) & expected)
                    group["hit4"] += bool(set(docs) & expected)
                else:
                    unsupported += bool(docs)
                    group["withAnySource"] += bool(docs)
                item["expectedDocumentIDs"] = sorted(expected)
            summaries.append({"id": policy_id, "supportedQueries": 17, "supportedHit1": hit1, "supportedHit4": hit4, "unsupportedQueries": 15, "unsupportedWithAnySource": unsupported, "passesUnchangedDirectSupportProfile": hit4 / 17 >= .9 and unsupported == 0, "groups": groups})
    report = {"protocolSHA256": native["protocolSHA256"], "split": native["split"], "scope": native["scope"], "nativeReportSHA256": sha((work / "native.json").read_bytes()), "preparation": receipt, "metricControls": controls, "nativeChecks": {k: native[k] for k in ["documents", "preparedPassages", "queries", "seconds", "nativeCosineSpots", "keywordSelectionOracles", "noRelatedCeilingOracles", "withdrawalChecks", "carriedExclusionChecks", "allSelectedSourcesCurrentAndValid"]}, "languageCounts": dict(Counter(c["language"] for c in native["cases"])), "indexErrors": [{"queryID": c["queryID"], "error": c["indexError"]} for c in native["cases"] if "indexError" in c], "policies": summaries, "cases": native["cases"], "testRetrievalScoresComputed": False, "appPolicyChanged": False}
    if output.exists():
        raise ValueError("Output exists")
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"split": native["split"], "policies": summaries, "languageCounts": report["languageCounts"], "nativeChecks": report["nativeChecks"]}))


def controls(binary, work, output):
    protocol()
    config = json.loads((work / "configuration.json").read_text())
    outcomes = []
    with tempfile.TemporaryDirectory(prefix="Lumen-selection-controls-") as temporary:
        root = Path(temporary)
        def rejected(name, mutate):
            value = json.loads(json.dumps(config))
            mutate(value)
            path = root / (name + ".json")
            path.write_text(json.dumps(value))
            target = root / (name + "-output.json")
            result = subprocess.run([str(binary), "--retrieval-selection-replay", str(path), str(target)], capture_output=True, text=True)
            if result.returncode == 0 or target.exists() or "Selection replay failed:" not in result.stderr:
                raise ValueError("Control did not reject: " + name)
            outcomes.append({"name": name, "exitCode": result.returncode, "diagnostic": result.stderr.strip(), "noCompletedReport": True})
        rejected("changed-score-hash", lambda c: c["models"][0]["scores"].update(sha256="0" * 64))
        def replace_scores(c, kind):
            data = Path(c["models"][0]["scores"]["path"]).read_bytes()
            if kind == "short":
                data = data[:-8]
            else:
                data = np.array([float("nan")], dtype="<f8").tobytes() + data[8:]
            file = root / (kind + ".f64le")
            file.write_bytes(data)
            c["models"][0]["scores"] = file_input(file)
        rejected("incomplete-score-matrix", lambda c: replace_scores(c, "short"))
        rejected("nonfinite-score", lambda c: replace_scores(c, "nan"))
        def duplicate(c):
            rows = Path(c["prepared"]["path"]).read_text().splitlines()
            row = json.loads(rows[0]); row["id"] = "1"; rows[1] = json.dumps(row)
            path = root / "duplicate-prepared.jsonl"; path.write_text("\n".join(rows) + "\n")
            c["prepared"] = file_input(path)
        rejected("duplicate-prepared-identity", duplicate)
        def spot(c):
            c["spots"][0]["queryVector"] = [0.] * 384
        rejected("forged-native-cosine-spot", spot)
        rejected("incomplete-query-statuses", lambda c: c["models"][0]["queryStatuses"].pop())
        def changed_source(c):
            rows = Path(c["corpus"]["path"]).read_text().splitlines()
            row = json.loads(rows[0]); row["text"] += " Changed."; rows[0] = json.dumps(row)
            path = root / "changed-corpus.jsonl"; path.write_text("\n".join(rows) + "\n")
            c["corpus"] = file_input(path)
        rejected("changed-source-fingerprint", changed_source)
        # Tiny synthetic matrix copies only. Never modify a hard link or the
        # retained original receipts while testing model-pair provenance.
        original = Path(config["corpus"]["path"]).parent
        mirror = root / "pair-mirror/challenge"
        needed = ["corpus.jsonl", "prepared/preparation.json", "prepared/passages.jsonl"]
        needed += [folder + "/" + name for folder in ["baseline-corpus", "candidate-corpus", "baseline-queries", "candidate-queries"] for name in ["complete.json", "vectors.f32le"]]
        for name in needed:
            target = mirror / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((original / name).read_bytes())
        changed = mirror / "candidate-queries/complete.json"
        value = json.loads(changed.read_text())
        value["compiledModelFiles"] = json.loads((mirror / "baseline-queries/complete.json").read_text())["compiledModelFiles"]
        changed.write_text(json.dumps(value))
        pair_output = root / "mismatched-pair-output"
        try:
            prepare(None, mirror.parent, pair_output, "challenge")
        except ValueError as error:
            if str(error) != "Mismatched or unpinned model pair" or (pair_output / "configuration.json").exists():
                raise
            outcomes.append({"name": "mismatched-native-model-pair", "diagnostic": str(error), "noCompletedConfiguration": True})
        else:
            raise ValueError("Mismatched model pair was accepted")
    if output.exists():
        raise ValueError("Output exists")
    output.write_text(json.dumps({"passed": len(outcomes), "controls": outcomes, "temporaryControlsRemoved": True}, indent=2) + "\n")
    print(json.dumps({"passedControls": len(outcomes)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    for name in ["source", "probe", "work"]:
        prep.add_argument(name, type=Path)
    prep.add_argument("--split", choices=["dev", "challenge"], required=True)
    summary = sub.add_parser("summarize")
    for name in ["source", "work", "output"]:
        summary.add_argument(name, type=Path)
    control = sub.add_parser("controls")
    for name in ["binary", "work", "output"]:
        control.add_argument(name, type=Path)
    compact = sub.add_parser("compact")
    compact.add_argument("input", type=Path)
    compact.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.source, args.probe, args.work, args.split)
    elif args.command == "summarize":
        summarize(args.source, args.work, args.output)
    elif args.command == "controls":
        controls(args.binary, args.work, args.output)
    else:
        compact_report(args.input, args.output)
