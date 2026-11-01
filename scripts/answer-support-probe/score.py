"""Fixed, offline QA experiment. Gold answers are never loaded by this runner."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import platform
import time

import numpy as np
import torch
import transformers
from transformers import AutoModelForQuestionAnswering, AutoTokenizer

from answer_decoder import accumulate, finish
from common import PROTOCOL_SHA, PUBLICATION, checked, policy, save, sha


def features(example, tokenizer):
    context, regions = example["context"], example["regions"]
    previous = 0
    for region in regions:
        a, b = region["start"], region["end"]
        if not isinstance(a, int) or not isinstance(b, int) or not previous <= a < b <= len(context):
            raise ValueError("Invalid/overlapping source region")
        if sha(context[a:b].encode()) != region["bodySHA256"]:
            raise ValueError("Changed original source body")
        previous = b
    if not regions:
        return [], "noSource"
    query_ids = tokenizer(example["question"], add_special_tokens=False)["input_ids"]
    budget = 384 - 3 - len(query_ids)
    if budget < 32:
        return [], "inputLimit"
    overlap = min(128, budget - 1)
    full = tokenizer(context, add_special_tokens=False, return_offsets_mapping=True)
    encoded = tokenizer(example["question"], context, truncation="only_second", max_length=384,
                        stride=overlap, return_overflowing_tokens=True, return_offsets_mapping=True)
    rows = []
    step = budget - overlap
    expected_count = 1 + max(0, math.ceil((len(full["input_ids"]) - budget) / step))
    if len(encoded["input_ids"]) != expected_count:
        raise ValueError("Missing context windows")
    covered = 0
    for index, ids in enumerate(encoded["input_ids"]):
        sequence = encoded.sequence_ids(index)
        offsets = encoded["offset_mapping"][index]
        context_positions = [i for i, owner in enumerate(sequence) if owner == 1]
        qids = [v for v, owner in zip(ids, sequence) if owner == 0]
        lo, hi = index * step, min(index * step + budget, len(full["input_ids"]))
        if qids != query_ids or [ids[i] for i in context_positions] != full["input_ids"][lo:hi] or [offsets[i] for i in context_positions] != full["offset_mapping"][lo:hi]:
            raise ValueError("Truncated query or changed/missing context tokens/offsets")
        if lo > covered or len(ids) > 384 or ids[0] != tokenizer.cls_token_id:
            raise ValueError("Incomplete coverage or invalid CLS")
        covered = hi
        rows.append({"input": {k: encoded[k][index] for k in tokenizer.model_input_names},
                     "offsets": offsets, "sequence": sequence})
    if covered != len(full["input_ids"]):
        raise ValueError("Uncovered final context tokens")
    return rows, "pending"


def window_controls(tokenizer):
    context = " ".join("token" + str(i) for i in range(700)) + " <4,0 µg/L not detected."
    example = {"question": "What was reported?", "context": context,
               "regions": [{"start": 0, "end": len(context), "bodySHA256": sha(context.encode())}]}
    rows, status = features(example, tokenizer)
    assert status == "pending" and len(rows) > 1
    # Every context token belongs to a represented window; overlap also retains
    # each adjacent pair across every initial window boundary.
    full = tokenizer(context, add_special_tokens=False, return_offsets_mapping=True)
    windows = [{tuple(offset) for offset, owner in zip(row["offsets"], row["sequence"]) if owner == 1} for row in rows]
    assert set(map(tuple, full["offset_mapping"])) == set.union(*windows)
    for a, b in zip(full["offset_mapping"], full["offset_mapping"][1:]):
        assert any(tuple(a) in window and tuple(b) in window for window in windows)
    oversized = dict(example, question="question " * 400)
    assert features(oversized, tokenizer) == ([], "inputLimit")
    assert features(dict(example, regions=[]), tokenizer) == ([], "noSource")
    changed = dict(example, regions=[dict(example["regions"][0], bodySHA256="0" * 64)])
    try:
        features(changed, tokenizer)
    except ValueError:
        pass
    else:
        raise AssertionError("Changed body accepted")
    overlap = dict(example, regions=[example["regions"][0], example["regions"][0]])
    try:
        features(overlap, tokenizer)
    except ValueError:
        pass
    else:
        raise AssertionError("Overlapping regions accepted")
    return {"passed": 5, "checks": ["all overlapping context tokens and adjacent boundary pairs represented",
            "complete oversized question retained as explicit inputLimit", "empty sources have explicit noSource",
            "changed source body rejected", "overlapping source regions rejected"], "longContextWindows": len(rows)}


def run(work, name):
    frozen = policy()
    source_paths = [Path(__file__), Path(__file__).with_name("answer_decoder.py"), Path(__file__).with_name("common.py")]
    producer = {str(p.name): sha(p.read_bytes()) for p in source_paths}
    receipt = json.loads((work / "model/receipt.json").read_bytes())
    if receipt["revision"] != frozen["model"]["revision"] or receipt["protocolSHA256"] != PROTOCOL_SHA:
        raise ValueError("Changed model receipt")
    for row in receipt["files"]:
        checked(work / "model" / row["file"], row["sha256"])
    if next(row for row in receipt["files"] if row["file"] == "model.safetensors")["sha256"] != frozen["model"]["weightsSHA256"]:
        raise ValueError("Changed pinned model weights")
    prepared = json.loads((work / (name + "-prepared.json")).read_bytes())
    if prepared["protocolSHA256"] != PROTOCOL_SHA:
        raise ValueError("Changed prepared policy")
    raw = checked(work / (name + "-inputs.jsonl"), prepared["inputsSHA256"])
    examples = [json.loads(line) for line in raw.splitlines()]
    if len(examples) != prepared["questions"] or len({q["id"] for q in examples}) != len(examples):
        raise ValueError("Missing/duplicate quality input")
    destination = work / (name + "-predictions-r1.jsonl")
    if destination.exists() or (work / (name + "-run-r1.json")).exists():
        raise ValueError("Output already exists; do not overwrite research results")
    torch.set_num_threads(4)
    torch.set_num_interop_threads(1)
    torch.manual_seed(0)
    tokenizer = AutoTokenizer.from_pretrained(work / "model", local_files_only=True, use_fast=True, trust_remote_code=False)
    if not tokenizer.is_fast or tokenizer.num_special_tokens_to_add(pair=True) != 3:
        raise ValueError("Unexpected tokenizer")
    controls = window_controls(tokenizer)
    counts = [len(features(example, tokenizer)[0]) for example in examples]
    feature_count = sum(counts)
    fixed = {0, feature_count // 2, feature_count - 1}
    print("Prepared", name, len(examples), "questions", feature_count, "features", flush=True)
    model = AutoModelForQuestionAnswering.from_pretrained(work / "model", local_files_only=True,
                trust_remote_code=False, use_safetensors=True, attn_implementation="eager").float().eval()
    states = [{"best": None, "null": math.inf, "windows": 0, "status": "pending"} for _ in examples]
    inference_seconds, feature_index = 0.0, 0
    batch, spots = [], []

    def infer():
        nonlocal inference_seconds
        tensors = tokenizer.pad([item[2]["input"] for item in batch], padding=True, return_tensors="pt")
        start = time.perf_counter()
        with torch.inference_mode():
            output = model(**tensors)
        inference_seconds += time.perf_counter() - start
        for j, (case_index, global_index, row) in enumerate(batch):
            n = len(row["input"]["input_ids"])
            a = output.start_logits[j, :n].double().numpy()
            b = output.end_logits[j, :n].double().numpy()
            accumulate(states[case_index], a, b, row["offsets"], row["sequence"], examples[case_index]["regions"])
            if global_index in fixed:
                spots.append((global_index, row["input"], a.copy(), b.copy()))
        batch.clear()

    for case_index, example in enumerate(examples):
        rows, status = features(example, tokenizer)
        if len(rows) != counts[case_index]:
            raise ValueError("Changed tokenization between passes")
        states[case_index]["status"] = status
        for row in rows:
            batch.append((case_index, feature_index, row)); feature_index += 1
            if len(batch) == 16:
                infer()
        if case_index % 500 == 0:
            print(name, case_index, "questions", feature_index, "features", flush=True)
    if batch:
        infer()
    numerical = []
    for index, inputs, expected_start, expected_end in spots:
        tensors = tokenizer.pad([inputs], padding=True, return_tensors="pt")
        with torch.inference_mode():
            singleton = model(**tensors)
        difference = max(float(np.max(np.abs(singleton.start_logits[0].double().numpy() - expected_start))),
                         float(np.max(np.abs(singleton.end_logits[0].double().numpy() - expected_end))))
        if not math.isfinite(difference) or difference > 1e-4:
            raise ValueError("Singleton/batch numerical mismatch")
        numerical.append({"featureIndex": index, "maximumAbsoluteLogitDifference": difference, "passed": True})
    if {row["featureIndex"] for row in numerical} != fixed or feature_index != feature_count:
        raise ValueError("Incomplete fixed numerical controls/features")
    results = [finish(example, state) for example, state in zip(examples, states)]
    if sum(row["windows"] for row in results) != feature_count:
        raise ValueError("Incomplete inference coverage")
    if producer != {str(p.name): sha(p.read_bytes()) for p in source_paths}:
        raise ValueError("Producer changed during scoring")
    with destination.open("x") as stream:
        for row in results:
            stream.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    save(work / (name + "-run-r1.json"), {"protocolSHA256": PROTOCOL_SHA, "protocolPublicationCommit": PUBLICATION,
        "inputsSHA256": prepared["inputsSHA256"], "predictionsSHA256": sha(destination.read_bytes()),
        "modelReceiptSHA256": sha((work / "model/receipt.json").read_bytes()), "producerSHA256AtStart": producer,
        "questions": len(results), "features": feature_count, "statusCounts": dict(Counter(row["status"] for row in results)),
        "inferenceOnlySeconds": inference_seconds, "inferenceTimeScope": "CPU FP32 model forward calls only; excludes loading, tokenization, padding, decoding and control replays. Not native/iPhone latency.",
        "contextCoverage": "Every original context token/offset matches its full-context slice; complete original question in each feature; every overlapping window represented.",
        "windowControls": controls, "numericalControls": numerical, "threads": torch.get_num_threads(),
        "versions": {"python": platform.python_version(), "torch": torch.__version__, "transformers": transformers.__version__, "numpy": np.__version__},
        "platform": platform.platform(), "goldLoadedByInference": False, "scope": "Development/replication component research only. No production reader/model change."})
    print("Finished", name, len(results), dict(Counter(row["status"] for row in results)), "inference seconds", inference_seconds, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("work", type=Path)
    parser.add_argument("name", choices=["public", "synthetic"])
    args = parser.parse_args()
    run(args.work, args.name)
