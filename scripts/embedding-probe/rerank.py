"""Predeclared dev-only question/passage reranking; no app model installation."""
import argparse
from collections import Counter
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "Design/native/retrieval-quality"
PROTOCOL = EVIDENCE / "rerank-protocol.json"
PUBLICATION = "cd180fa926d794566b83faabbec0dac3c049a132"
FILES = ["config.json", "tokenizer_config.json", "tokenizer.json", "vocab.txt", "special_tokens_map.json", "model.safetensors", "README.md"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def policy():
    data = PROTOCOL.read_bytes()
    value = json.loads(data)
    if digest(data) != "3551921b67fba043d21be0db174976633b144e2de0eecd64361e3108059ebd0c":
        raise ValueError("Changed published protocol")
    if value["name"] != "question-passage-cross-encoder-dev" or value["model"]["revision"] != "233902d25c440f23af6f7d6e94d2946bac0bee0a" or value["policies"]["thresholds"] != [None, -8, -6, -4, -2, 0, 2, 4, 6, 8]:
        raise ValueError("Undeclared model/policy")
    return value, digest(data)


def save(path, value):
    if path.exists():
        raise ValueError("Output exists: " + str(path))
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fetch(destination):
    frozen, protocol_hash = policy()
    destination.mkdir(parents=True, exist_ok=False)
    model = frozen["model"]
    url = "https://huggingface.co/api/models/" + model["repository"] + "/revision/" + model["revision"] + "?blobs=true"
    with urllib.request.urlopen(url, timeout=60) as response:
        metadata = json.load(response)
    if metadata["sha"] != model["revision"]:
        raise ValueError("Revision changed")
    siblings = {f["rfilename"]: f for f in metadata["siblings"]}
    receipt = []
    for name in FILES:
        item = siblings[name]
        path = destination / name
        url = "https://huggingface.co/" + model["repository"] + "/resolve/" + model["revision"] + "/" + name
        part = path.with_suffix(path.suffix + ".part")
        length = 0
        h = hashlib.sha256()
        with urllib.request.urlopen(url, timeout=120) as response, part.open("xb") as output:
            while chunk := response.read(1024 * 1024):
                length += len(chunk)
                if length > item["size"]:
                    raise ValueError("Unexpected download size")
                output.write(chunk)
                h.update(chunk)
        if length != item["size"]:
            raise ValueError("Incomplete download")
        if "lfs" in item:
            if h.hexdigest() != item["lfs"]["sha256"] or length != model["weightsBytes"] or h.hexdigest() != model["weightsSHA256"]:
                raise ValueError("Weight pin mismatch")
        else:
            data = part.read_bytes()
            git_hash = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
            if git_hash != item["blobId"]:
                raise ValueError("Source blob mismatch")
        part.rename(path)
        receipt.append({"file": name, "bytes": length, "sha256": h.hexdigest(), "upstreamGitBlob": item["blobId"]})
        print("Verified", name, length, flush=True)
    save(destination / "receipt.json", {"protocolSHA256": protocol_hash, "protocolPublicationCommit": PUBLICATION, "repository": model["repository"], "revision": model["revision"], "license": metadata.get("cardData", {}).get("license"), "files": receipt, "bytes": sum(r["bytes"] for r in receipt)})


def load_pools(path):
    frozen, protocol_hash = policy()
    data = path.read_bytes()
    pools = json.loads(data)
    if pools["version"] != 1 or pools["protocolSHA256"] != protocol_hash or pools["configurationSHA256"] != frozen["inputs"][pools["split"] + "ConfigurationSHA256"]:
        raise ValueError("Pool protocol/input mismatch")
    if len(pools["cases"]) != {"dev": 324, "challenge": 32}[pools["split"]] or len({q["queryID"] for q in pools["cases"]}) != len(pools["cases"]):
        raise ValueError("Incomplete/duplicate queries")
    for q in pools["cases"]:
        if len(q["pool"]) > 64 or len({r["row"] for r in q["pool"]}) != len(q["pool"]):
            raise ValueError("Invalid pool")
    # Compare actual original production packets against the published replay.
    from selection import expand_report
    previous = json.loads((EVIDENCE / ("selection-" + pools["split"] + ".json")).read_bytes())
    if "compactSchema" in previous:
        previous = expand_report(previous)
    prior = {c["queryID"]: c for c in previous["cases"]}
    for q in pools["cases"]:
        old = next(p for p in prior[q["queryID"]]["policies"] if p["id"] == "minilm-production-042")
        fields = {"documentID", "start", "end", "ordinal", "sourceSHA256", "selection"}
        if any(set(p) != fields for p in q["baseline"]) or any(set(p) - fields not in [set(), {"judgment"}] for p in old["passages"]):
            raise ValueError("Unknown baseline source fields")
        prior_passages = [{k: v for k, v in p.items() if k != "judgment"} for p in old["passages"]]
        if q["baseline"] != prior_passages or q["baselineStatus"] != old["status"] or q["language"] != prior[q["queryID"]]["language"]:
            raise ValueError("Baseline packet/language drift: " + q["queryID"])
    return frozen, protocol_hash, data, pools


def score(model_dir, pool_path, output):
    import numpy as np
    import torch
    from transformers import AutoTokenizer, AutoModelForSequenceClassification
    frozen, protocol_hash, pool_data, pools = load_pools(pool_path)
    receipt = json.loads((model_dir / "receipt.json").read_bytes())
    if receipt["protocolSHA256"] != protocol_hash or receipt["revision"] != frozen["model"]["revision"]:
        raise ValueError("Changed model receipt")
    for f in receipt["files"]:
        path = model_dir / f["file"]
        if path.is_symlink() or path.stat().st_size != f["bytes"] or digest(path.read_bytes()) != f["sha256"]:
            raise ValueError("Changed model file")
    if next(f["sha256"] for f in receipt["files"] if f["file"] == "model.safetensors") != frozen["model"]["weightsSHA256"]:
        raise ValueError("Changed weights")
    torch.set_num_threads(4)
    torch.set_num_interop_threads(1)
    tokenizer = AutoTokenizer.from_pretrained(model_dir, local_files_only=True, trust_remote_code=False)
    model = AutoModelForSequenceClassification.from_pretrained(model_dir, local_files_only=True, trust_remote_code=False, use_safetensors=True, attn_implementation="eager").float().eval()
    if model.config.num_labels != 1 or model.config.max_position_embeddings != 512 or model.config.num_hidden_layers != 6:
        raise ValueError("Unexpected model architecture")
    batch_size = frozen["pairedTokenization"]["batchSize"]
    cases, windows, destinations = [], [], []
    direct_pair_controls = 0
    for qi, q in enumerate(pools["cases"]):
        state = "indexError" if "indexError" in q else "unsupportedLanguage" if q["language"] != "en" else "notNeeded" if not q["pool"] else "scored"
        query_tokens = tokenizer.encode(q["query"], add_special_tokens=False, truncation=False)
        budget = 512 - 3 - len(query_tokens)
        if state == "scored" and budget < 1:
            state = "inputLimit"
        result = {"queryID": q["queryID"], "status": state, "scores": []}
        cases.append(result)
        if state != "scored":
            continue
        for ri, row in enumerate(q["pool"]):
            tokens = tokenizer.encode(row["text"], add_special_tokens=False, truncation=False)
            if not tokens:
                raise ValueError("Empty passage")
            chunks = []
            start = 0
            while True:
                chunks.append(tokens[start:start + budget])
                if start + budget >= len(tokens):
                    break
                start += max(1, budget // 2)
            if len(chunks) == 1:
                direct = tokenizer(q["query"], row["text"], add_special_tokens=True, truncation=False)
                expected_ids = [tokenizer.cls_token_id] + query_tokens + [tokenizer.sep_token_id] + chunks[0] + [tokenizer.sep_token_id]
                expected_types = [0] * (len(query_tokens) + 2) + [1] * (len(chunks[0]) + 1)
                if direct["input_ids"] != expected_ids or direct["token_type_ids"] != expected_types or direct["attention_mask"] != [1] * len(expected_ids):
                    raise ValueError("Manual pair differs from upstream tokenizer")
                direct_pair_controls += 1
            result["scores"].append({"row": row["row"], "preparedID": row["preparedID"], "inputSHA256": digest((q["query"] + "\0" + row["text"]).encode()), "score": None, "windows": len(chunks)})
            for chunk in chunks:
                ids = [tokenizer.cls_token_id] + query_tokens + [tokenizer.sep_token_id] + chunk + [tokenizer.sep_token_id]
                types = [0] * (len(query_tokens) + 2) + [1] * (len(chunk) + 1)
                if len(ids) > 512 or len(ids) != len(types):
                    raise ValueError("Incomplete paired window")
                windows.append((ids, types))
                destinations.append((qi, ri))
    if not windows:
        raise ValueError("No scored windows")
    def inference(items):
        n = max(len(x[0]) for x in items)
        ids = [x[0] + [tokenizer.pad_token_id] * (n - len(x[0])) for x in items]
        types = [x[1] + [0] * (n - len(x[1])) for x in items]
        masks = [[1] * len(x[0]) + [0] * (n - len(x[0])) for x in items]
        with torch.inference_mode():
            values = model(input_ids=torch.tensor(ids), attention_mask=torch.tensor(masks), token_type_ids=torch.tensor(types)).logits.reshape(-1).cpu().numpy()
        if len(values) != len(items) or not np.isfinite(values).all():
            raise ValueError("Invalid model scores")
        return [float(x) for x in values]
    started = time.perf_counter()
    raw = []
    for start in range(0, len(windows), batch_size):
        raw.extend(inference(windows[start:start + batch_size]))
        if start % (batch_size * 25) == 0:
            print("Scored", min(start + batch_size, len(windows)), "/", len(windows), "windows", flush=True)
    elapsed = time.perf_counter() - started
    controls = []
    for index in sorted({0, len(windows) // 2, len(windows) - 1}):
        single = inference([windows[index]])[0]
        delta = abs(single - raw[index])
        if delta > 1e-4:
            raise ValueError("Padded/singleton score drift")
        controls.append({"window": index, "batchScore": raw[index], "singletonScore": single, "absoluteDifference": delta})
    for (qi, ri), value in zip(destinations, raw):
        old = cases[qi]["scores"][ri]["score"]
        cases[qi]["scores"][ri]["score"] = value if old is None else max(old, value)
    report = {"version": 1, "protocolSHA256": protocol_hash, "poolSHA256": digest(pool_data), "modelRevision": receipt["revision"], "weightsSHA256": frozen["model"]["weightsSHA256"], "protocolPublicationCommit": PUBLICATION, "cases": cases,
              "producer": {"secondsMacCPUInference": elapsed, "threads": 4, "windows": len(windows), "pairs": len({tuple(x) for x in destinations}), "upstreamDirectPairTokenizationControls": direct_pair_controls, "parameters": model.num_parameters(), "queryStatuses": dict(Counter(q["status"] for q in cases)), "batchSingletonControls": controls, "versions": {n: importlib.metadata.version(n) for n in ["torch", "transformers", "numpy", "safetensors"]}, "sourceSHA256": digest(Path(__file__).read_bytes()), "scope": "CPU FP32 upstream relevance only; timing excludes tokenization/loading and is not an iPhone/CoreML/live-budget claim."}}
    save(output, report)
    print(json.dumps(report["producer"]), flush=True)


def summarize(source, pool_path, scores_path, native_path, output):
    import pytrec_eval
    from corpus import checked
    frozen, protocol_hash, pool_data, pools = load_pools(pool_path)
    native = json.loads(native_path.read_bytes())
    scored = json.loads(scores_path.read_bytes())
    if native["protocolSHA256"] != protocol_hash or native["poolSHA256"] != digest(pool_data) or native["scoresSHA256"] != digest(scores_path.read_bytes()) or native["queries"] != len(pools["cases"]):
        raise ValueError("Changed native outcomes")
    if pools["split"] == "dev":
        manifest = json.loads((EVIDENCE / "nfcorpus-source.json").read_bytes())
        dev_file = next(f for f in manifest["files"] if f["path"] == "nfcorpus/qrels/dev.tsv")
        dev_data = checked(source / dev_file["path"], dev_file)
        qrels = {}
        for line in dev_data.decode().splitlines()[1:]:
            query, doc, grade = line.split("\t")
            if doc in qrels.setdefault(query, {}):
                raise ValueError("Duplicate development judgment")
            qrels[query][doc] = int(grade)
        if set(qrels) != {q["queryID"] for q in pools["cases"]}:
            raise ValueError("Development denominator changed")
        evaluator = pytrec_eval.RelevanceEvaluator(qrels, {"ndcg_cut.4", "P.4", "recall.4"})
    else:
        fixture = json.loads((ROOT / "Tests/Fixtures/RetrievalChallenge.json").read_bytes())
        if digest((ROOT / "Tests/Fixtures/RetrievalChallenge.json").read_bytes()) != frozen["inputs"]["challengeFixtureSHA256"]:
            raise ValueError("Changed support labels")
        expected = {q["id"]: q["expectedDocumentIDs"] for q in fixture["queries"]}
    def metrics(packets):
        ordered = {qid: list(dict.fromkeys(p["documentID"] for p in rows)) for qid, rows in packets.items()}
        if pools["split"] == "dev":
            run = {q: {doc: float(4 - rank) for rank, doc in enumerate(docs)} for q, docs in ordered.items() if docs}
            values = evaluator.evaluate(run)
            per = {q["queryID"]: {m: values.get(q["queryID"], {}).get(m, 0.) for m in ["ndcg_cut_4", "P_4", "recall_4"]} for q in pools["cases"]}
            summary = {m: sum(v[m] for v in per.values()) / len(per) for m in ["ndcg_cut_4", "P_4", "recall_4"]}
            summary.update(denominatorQueries=len(per), hit_4=sum(any(qrels.get(q, {}).get(d, 0) > 0 for d in docs) for q, docs in ordered.items()) / len(per))
            return summary, per
        supported = [q for q, ids in expected.items() if ids]
        unsupported = [q for q, ids in expected.items() if not ids]
        return {"supportedQueries": len(supported), "unsupportedQueries": len(unsupported), "supportedHit1": sum(bool(ordered[q]) and ordered[q][0] in expected[q] for q in supported), "supportedHit4": sum(bool(set(ordered[q]) & set(expected[q])) for q in supported), "unsupportedWithSources": sum(bool(ordered[q]) for q in unsupported), "unsupportedSelectedCases": [q for q in unsupported if ordered[q]]}, ordered
    baseline_packets = {q["queryID"]: q["baseline"] for q in pools["cases"]}
    baseline, baseline_values = metrics(baseline_packets)
    pool_docs = {q["queryID"]: {row["documentID"] for row in q["pool"]} for q in pools["cases"]}
    if pools["split"] == "dev":
        pool_metrics = {"queriesWithJudgedRelevantSource": sum(any(qrels.get(q, {}).get(doc, 0) > 0 for doc in docs) for q, docs in pool_docs.items()), "denominatorQueries": len(pool_docs), "note": "Non-English baseline fallback has no proposed rerank pool and remains in denominator."}
    else:
        pool_metrics = {"supportedQueriesWithExpectedSource": sum(bool(pool_docs[q] & set(ids)) for q, ids in expected.items() if ids), "denominatorSupported": sum(bool(ids) for ids in expected.values())}
    summaries, cases, per_policy_values = [], [], []
    for index, threshold in enumerate(frozen["policies"]["thresholds"]):
        packets = {q["queryID"]: q["policies"][index]["passages"] for q in native["cases"]}
        if any(q["policies"][index]["cutoff"] != threshold for q in native["cases"]):
            raise ValueError("Changed cutoff ordering")
        summary, values = metrics(packets)
        per_policy_values.append(values)
        summary["cutoff"] = threshold
        summary["selectionErrors"] = [q["queryID"] for q in native["cases"] if "selectionError" in q["policies"][index]]
        if pools["split"] == "dev":
            changes = {q: values[q]["ndcg_cut_4"] - baseline_values[q]["ndcg_cut_4"] for q in values}
            summary.update(ndcgDelta=summary["ndcg_cut_4"] - baseline["ndcg_cut_4"], precisionDelta=summary["P_4"] - baseline["P_4"], improved=sum(v > 1e-12 for v in changes.values()), worsened=sum(v < -1e-12 for v in changes.values()), unchanged=sum(abs(v) <= 1e-12 for v in changes.values()))
            summary["passesDeclaredPublicGate"] = summary["ndcgDelta"] >= 0.02 and summary["precisionDelta"] >= 0
        else:
            summary["passesUnchangedSupportProfile"] = summary["supportedHit4"] / summary["supportedQueries"] >= .9 and summary["unsupportedWithSources"] == 0
        summaries.append(summary)
    for q in native["cases"]:
        query_id = q["queryID"]
        if pools["split"] == "dev":
            q["baselineMetrics"] = baseline_values[query_id]
            for passage in q["baseline"]:
                passage["judgment"] = qrels[query_id].get(passage["documentID"])
            for index, result in enumerate(q["policies"]):
                result["metrics"] = per_policy_values[index][query_id]
                result["ndcgDeltaFromBaseline"] = result["metrics"]["ndcg_cut_4"] - baseline_values[query_id]["ndcg_cut_4"]
                for passage in result["passages"]:
                    passage["judgment"] = qrels[query_id].get(passage["documentID"])
        else:
            q["expectedDocumentIDs"] = expected[query_id]
            for result in q["policies"]:
                result["expectedSourceFound"] = bool(set(expected[query_id]) & {r["documentID"] for r in result["passages"]})
        cases.append(q)
    report = {"protocolSHA256": protocol_hash, "protocolPublicationCommit": PUBLICATION, "split": pools["split"], "baseline": baseline, "candidatePoolCoverage": pool_metrics, "policies": summaries, "cases": cases, "producer": scored["producer"], "native": {k: v for k, v in native.items() if k != "cases"}, "inputHashes": {"pool": digest(pool_data), "scores": digest(scores_path.read_bytes()), "native": digest(native_path.read_bytes())}, "testRetrievalScoresComputed": False, "scope": "Complete declared development-only rerank experiment, with raw upstream FP32 logits and actual native final source selection. No app integration or clinical support claim."}
    save(output, report)
    print(json.dumps({"split": report["split"], "baseline": baseline, "policies": summaries}, indent=2))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("fetch"); p.add_argument("destination", type=Path)
    p = sub.add_parser("score"); p.add_argument("model", type=Path); p.add_argument("pool", type=Path); p.add_argument("output", type=Path)
    p = sub.add_parser("summarize"); p.add_argument("source", type=Path); p.add_argument("pool", type=Path); p.add_argument("scores", type=Path); p.add_argument("native", type=Path); p.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.command == "fetch": fetch(args.destination)
    elif args.command == "score": score(args.model, args.pool, args.output)
    else: summarize(args.source, args.pool, args.scores, args.native, args.output)


if __name__ == "__main__":
    main()
