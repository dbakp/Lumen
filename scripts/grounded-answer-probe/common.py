"""Frozen inputs and direct downloads for the staged complete-answer trial."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "Design/native/grounded-answer"
PROTOCOL_SHA = "614a25920e72730f29aefc7256c6fdeae20e929aaa69c4a0a263a989df75f1f1"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked(path, digest):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Unsafe/missing input: " + str(path))
    data = path.read_bytes()
    if sha(data) != digest:
        raise ValueError("Changed input: " + str(path))
    return data


def policy():
    return json.loads(checked(EVIDENCE / "protocol.json", PROTOCOL_SHA))


def save(path, value):
    with path.open("x") as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def file_digest(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def fetch_model(work):
    frozen = policy(); model = frozen["model"]
    directory = work / "model"; directory.mkdir(exist_ok=False)
    results = []
    for pin in model["selectedFiles"]:
        name = pin["rfilename"]
        destination = directory / name
        part = destination.with_suffix(destination.suffix + ".part")
        url = "https://huggingface.co/" + model["repository"] + "/resolve/" + model["revision"] + "/" + name
        size = 0; digest = hashlib.sha256()
        with urllib.request.urlopen(url, timeout=120) as response, part.open("xb") as stream:
            while block := response.read(1024 * 1024):
                size += len(block)
                if size > pin["size"]:
                    raise ValueError("Oversized upstream input")
                stream.write(block); digest.update(block)
        if size != pin["size"]:
            raise ValueError("Incomplete upstream input")
        if "lfs" in pin:
            if digest.hexdigest() != pin["lfs"]["sha256"]:
                raise ValueError("Changed pinned upstream LFS object")
        else:
            data = part.read_bytes()
            if hashlib.sha1(b"blob " + str(size).encode() + b"\0" + data).hexdigest() != pin["blobId"]:
                raise ValueError("Changed upstream Git blob")
        part.rename(destination)
        results.append({"file": name, "bytes": size, "sha256": digest.hexdigest(), "upstreamGitBlob": pin["blobId"]})
        print("Verified", name, size, flush=True)
    save(directory / "receipt.json", {"protocolSHA256": PROTOCOL_SHA, "repository": model["repository"],
        "revision": model["revision"], "license": model["license"], "files": results, "bytes": sum(row["bytes"] for row in results)})


def prepare(work):
    frozen = policy()
    source = json.loads(checked(ROOT / frozen["synthetic"]["source"], frozen["synthetic"]["sha256"]))
    fixture = json.loads((ROOT / "Tests/Fixtures/RetrievalChallenge.json").read_bytes())
    titles = {d["id"]: d["title"] for d in fixture["documents"]}
    rows = []
    for case in source["cases"]:
        original = case["input"]
        sources, owners, hashes = [], {}, {}
        for index, region in enumerate(original["regions"]):
            key = "source_" + str(index + 1)
            body = original["context"][region["start"]:region["end"]]
            if sha(body.encode()) != region["bodySHA256"]:
                raise ValueError("Changed original source body")
            sources.append({"id": key, "title": titles.get(region["documentID"], "Provided saved text"), "savedText": body})
            owners[key] = region["documentID"]
            hashes[key] = region["bodySHA256"]
        rows.append({"id": original["id"], "group": original["group"], "question": original["question"],
                     "sources": sources, "owners": owners, "sourceBodySHA256": hashes})
    if len(rows) != 72 or len({row["id"] for row in rows}) != 72:
        raise ValueError("Incomplete frozen synthetic questions")
    destination = work / "synthetic-inputs.jsonl"
    with destination.open("x") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    save(work / "prepared.json", {"protocolSHA256": PROTOCOL_SHA, "inputsSHA256": file_digest(destination),
        "questions": len(rows), "groups": {group: sum(row["group"] == group for row in rows) for group in ("baseline", "reranked", "stress")},
        "scope": "Only question and complete original source bodies/titles/opaque IDs go to the model. Ownership/hashes remain local. No gold/previous predictions passed to inference."})
    print("Prepared", len(rows), "synthetic inputs", flush=True)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(); parser.add_argument("work", type=Path)
    args = parser.parse_args(); args.work.mkdir(exist_ok=False)
    prepare(args.work)
    fetch_model(args.work)
