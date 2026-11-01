"""Pinned inputs for the predeclared development-only answerability experiment."""
import base64
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "Design/native/answer-support"
PROTOCOL = EVIDENCE / "protocol.json"
PROTOCOL_SHA = "85b1e6ad885d7064cbda9b75d71111162467036f75a99c08ddd816b2a1be8b99"
PUBLICATION = "e87f49dbf7af6d2b5ab9c9bbb8a24083505f6fdd"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def policy():
    data = PROTOCOL.read_bytes()
    if sha(data) != PROTOCOL_SHA:
        raise ValueError("Changed published answerability protocol")
    return json.loads(data)


def save(path, value):
    if path.exists():
        raise ValueError("Output already exists: " + str(path))
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def checked(path, expected):
    if path.is_symlink() or not path.is_file() or sha(path.read_bytes()) != expected:
        raise ValueError("Changed or unsafe input: " + str(path))
    return path.read_bytes()


def fetch(work):
    frozen = policy()
    model_dir = work / "model"
    model_dir.mkdir(exist_ok=False)
    model = frozen["model"]
    with urllib.request.urlopen("https://huggingface.co/api/models/" + model["repository"] + "/revision/" + model["revision"] + "?blobs=true", timeout=60) as response:
        metadata = json.load(response)
    if metadata["sha"] != model["revision"]:
        raise ValueError("Changed model revision")
    names = ["config.json", "tokenizer_config.json", "special_tokens_map.json", "vocab.txt", "model.safetensors", "README.md"]
    siblings = {row["rfilename"]: row for row in metadata["siblings"]}
    files = []
    for name in names:
        pin = siblings[name]
        path = model_dir / name
        url = "https://huggingface.co/" + model["repository"] + "/resolve/" + model["revision"] + "/" + name
        part = path.with_suffix(path.suffix + ".part")
        size, digest = 0, hashlib.sha256()
        with urllib.request.urlopen(url, timeout=120) as response, part.open("xb") as stream:
            while block := response.read(1024 * 1024):
                size += len(block)
                if size > pin["size"]:
                    raise ValueError("Oversized model input")
                stream.write(block); digest.update(block)
        if size != pin["size"]:
            raise ValueError("Incomplete model input")
        if "lfs" in pin:
            if digest.hexdigest() != model["weightsSHA256"] or digest.hexdigest() != pin["lfs"]["sha256"] or size != model["weightsBytes"]:
                raise ValueError("Changed model weights")
        else:
            data = part.read_bytes()
            if hashlib.sha1(b"blob " + str(size).encode() + b"\0" + data).hexdigest() != pin["blobId"]:
                raise ValueError("Changed model source blob")
        part.rename(path)
        files.append({"file": name, "bytes": size, "sha256": digest.hexdigest(), "upstreamGitBlob": pin["blobId"]})
        print("Verified", name, size, flush=True)
    save(model_dir / "receipt.json", {"protocolSHA256": PROTOCOL_SHA, "protocolPublicationCommit": PUBLICATION, "repository": model["repository"], "revision": model["revision"], "license": metadata.get("cardData", {}).get("license"), "files": files, "bytes": sum(f["bytes"] for f in files)})
    for key, name in [("publicDataset", "dev-v2.0.json"), ("officialEvaluator", "evaluate-v2.0.py")]:
        pin = frozen[key]
        url = "https://api.github.com/repos/" + pin["repository"] + "/git/blobs/" + pin["gitBlobSHA"]
        with urllib.request.urlopen(url, timeout=60) as response:
            blob = json.load(response)
        data = base64.b64decode(blob["content"])
        if blob["sha"] != pin["gitBlobSHA"] or len(data) != pin["bytes"] or hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() != pin["gitBlobSHA"]:
            raise ValueError("Changed official dataset/evaluator")
        (work / name).write_bytes(data)
        save(work / (name + ".receipt.json"), {"repository": pin["repository"], "path": pin["path"], "gitBlobSHA": pin["gitBlobSHA"], "bytes": len(data), "sha256": sha(data), "scope": pin["scope"]})
        print("Verified", name, len(data), flush=True)


def prepare(work):
    frozen = policy()
    dataset_path = work / "dev-v2.0.json"
    receipt = json.loads((work / "dev-v2.0.json.receipt.json").read_bytes())
    public = json.loads(checked(dataset_path, receipt["sha256"]))
    examples, labels = [], {}
    for article in public["data"]:
        for paragraph in article["paragraphs"]:
            context = paragraph["context"]
            for qa in paragraph["qas"]:
                key = qa["id"]
                if key in labels:
                    raise ValueError("Duplicate public question")
                for answer in qa["answers"]:
                    if context[answer["answer_start"]:answer["answer_start"] + len(answer["text"])] != answer["text"]:
                        raise ValueError("Changed gold answer anchor")
                examples.append({"id": key, "group": "public", "question": qa["question"], "context": context, "regions": [{"id": "provided-paragraph", "start": 0, "end": len(context), "bodySHA256": sha(context.encode())}]})
                labels[key] = {"isImpossible": qa["is_impossible"], "answers": qa["answers"]}
    if len(examples) != 11873 or sum(not q["isImpossible"] for q in labels.values()) != 5928:
        raise ValueError("Incomplete public development data")
    gold = json.loads(checked(ROOT / "Tests/Fixtures/AnswerSupportGold.json", frozen["synthetic"]["goldSHA256"]))
    fixture = json.loads(checked(ROOT / "Tests/Fixtures/RetrievalChallenge.json", frozen["synthetic"]["originalFixtureSHA256"]))
    docs = {d["id"]: d for d in fixture["documents"]}
    queries = {q["id"]: q for q in fixture["queries"]}
    expected = {q["queryID"]: q for q in gold["cases"]}
    for item in frozen["inputFiles"]:
        checked(Path(item["path"]), item["sha256"])
    pool_path = next(Path(f["path"]) for f in frozen["inputFiles"] if Path(f["path"]).name == "challenge-pools.json")
    pools = {q["queryID"]: q for q in json.loads(pool_path.read_bytes())["cases"]}
    outcome = json.loads((ROOT / "Design/native/retrieval-quality/rerank-challenge.json").read_bytes())
    synthetic, synthetic_labels = [], {}
    for case in outcome["cases"]:
        query_id = case["queryID"]
        if queries[query_id]["expectedDocumentIDs"] != expected[query_id]["expectedDocumentIDs"]:
            raise ValueError("Changed original source labels")
        for name, passages in [("baseline", case["baseline"]), ("reranked", case["policies"][0]["passages"])]:
            key = name + "/" + query_id
            context, regions = "", []
            for index, passage in enumerate(passages):
                doc = docs[passage["documentID"]]
                row = next((r for r in pools[query_id]["pool"] if all(r[k] == passage[k] for k in ["documentID", "start", "end", "sourceSHA256"])), None)
                # The17 frozen source bodies are short, plain single excerpts;
                # verify the raw body instead of assuming character conventions.
                if row is None or passage["start"] != 0 or passage["end"] != len(doc["body"]) or row["text"] != doc["title"][:160] + "\n" + doc["body"]:
                    raise ValueError("Changed native source/body binding")
                context += ("\n\n" if context else "") + "[Source " + str(index + 1) + "] " + doc["title"] + "\n"
                start = len(context); context += doc["body"]
                regions.append({"id": doc["id"] + ":" + str(passage["start"]) + ":" + str(passage["end"]), "documentID": doc["id"], "start": start, "end": len(context), "bodySHA256": sha(doc["body"].encode()), "nativeSourceSHA256": passage["sourceSHA256"]})
            synthetic.append({"id": key, "group": name, "question": queries[query_id]["text"], "context": context, "regions": regions})
            synthetic_labels[key] = expected[query_id]
    stress = json.loads(checked(ROOT / "Tests/Fixtures/AnswerSupportStress.json", frozen["synthetic"]["stressSHA256"]))
    for case in stress["cases"]:
        key = "stress/" + case["id"]
        synthetic.append({"id": key, "group": "stress", "question": case["question"], "context": case["context"], "regions": [{"id": case["id"], "documentID": case["id"], "start": 0, "end": len(case["context"]), "bodySHA256": sha(case["context"].encode())}]})
        synthetic_labels[key] = {"expectedDocumentIDs": [case["id"]] if case["answers"] else [], "acceptableAnswers": case["answers"]}
    for name, rows, answers in [("public", examples, labels), ("synthetic", synthetic, synthetic_labels)]:
        if len({q["id"] for q in rows}) != len(rows) or set(answers) != {q["id"] for q in rows}:
            raise ValueError("Incomplete input/label mapping")
        dest = work / (name + "-inputs.jsonl")
        if dest.exists():
            raise ValueError("Output exists")
        dest.write_text("".join(json.dumps(q, ensure_ascii=False, separators=(",", ":")) + "\n" for q in rows))
        save(work / (name + "-labels.json"), answers)
        save(work / (name + "-prepared.json"), {"protocolSHA256": PROTOCOL_SHA, "inputsSHA256": sha(dest.read_bytes()), "labelsSHA256": sha((work / (name + "-labels.json")).read_bytes()), "questions": len(rows), "groups": {g: sum(q["group"] == g for q in rows) for g in sorted({q["group"] for q in rows})}, "scope": "Complete input/label files kept separate; model inference receives question/context/regions only, never gold answers."})
        print("Prepared", name, len(rows), flush=True)
