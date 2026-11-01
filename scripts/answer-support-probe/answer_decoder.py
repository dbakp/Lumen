"""Source-bound, exhaustive single-span decoding. No semantic-validity claim."""
import math
import numpy as np


def best_span(start_logits, end_logits, offsets, sequence_ids, regions, maximum=30):
    start = np.asarray(start_logits, dtype=np.float64)
    end = np.asarray(end_logits, dtype=np.float64)
    if start.ndim != 1 or end.shape != start.shape or len(offsets) != len(start) or len(sequence_ids) != len(start) or not np.isfinite(start).all() or not np.isfinite(end).all():
        raise ValueError("Invalid/incomplete/nonfinite logits")
    n = len(start)
    owners = np.full(n, -1, dtype=np.int32)
    for i, ((a, b), sequence) in enumerate(zip(offsets, sequence_ids)):
        if sequence != 1 or b <= a:
            continue
        found = [j for j, region in enumerate(regions) if region["start"] <= a < b <= region["end"]]
        if len(found) > 1:
            raise ValueError("Overlapping source regions")
        if found:
            owners[i] = found[0]
    starts = np.arange(n)[:, None]
    ends = starts + np.arange(maximum)[None, :]
    clipped = np.minimum(ends, n - 1)
    legal = (ends < n) & (owners[:, None] >= 0) & (owners[:, None] == owners[clipped])
    scores = start[:, None] + end[clipped]
    scores[~legal] = -np.inf
    if not np.isfinite(scores).any():
        return None
    flat = int(np.argmax(scores))
    begin, width = np.unravel_index(flat, scores.shape)
    finish = begin + width
    a, b = offsets[begin][0], offsets[finish][1]
    owner = int(owners[begin])
    if not regions[owner]["start"] <= a < b <= regions[owner]["end"]:
        raise ValueError("Span crosses source boundary")
    return {"score": float(scores[begin, width]), "start": a, "end": b, "regionIndex": owner, "tokenStart": int(begin), "tokenEnd": int(finish), "tokens": int(width + 1)}


def finish(example, state):
    span = state["best"]
    if span is None:
        return {"id": example["id"], "group": example["group"], "status": state["status"], "answer": "", "windows": state["windows"]}
    null = state["null"]
    if not math.isfinite(null) or not math.isfinite(span["score"]):
        raise ValueError("Nonfinite score aggregation")
    difference = null - span["score"]
    a, b = span["start"], span["end"]
    text = example["context"][a:b]
    region = example["regions"][span["regionIndex"]]
    byte_start = len(example["context"][:a].encode())
    byte_end = len(example["context"][:b].encode())
    if example["context"].encode()[byte_start:byte_end] != text.encode():
        raise ValueError("Original UTF8 span did not round-trip")
    abstain = difference > 0
    return {"id": example["id"], "group": example["group"], "status": "abstained" if abstain else "answered", "answer": "" if abstain else text, "windows": state["windows"], "nullMinusSpan": difference,
            "bestCandidate": {"text": text, "start": a, "end": b, "byteStart": byte_start, "byteEnd": byte_end, "regionID": region["id"], "documentID": region.get("documentID"), "sourceBodySHA256": region["bodySHA256"], "tokens": span["tokens"]},
            "scope": "Literal span or null decision, not calibrated confidence or clinical validation."}


def accumulate(state, start_logits, end_logits, offsets, sequence_ids, regions, cls_index=0):
    start = np.asarray(start_logits, dtype=np.float64)
    end = np.asarray(end_logits, dtype=np.float64)
    candidate = best_span(start, end, offsets, sequence_ids, regions)
    if not 0 <= cls_index < len(start):
        raise ValueError("Missing CLS null position")
    null = float(start[cls_index] + end[cls_index])
    state["null"] = min(state["null"], null)
    state["windows"] += 1
    state["status"] = "scored"
    previous = state["best"]
    if candidate is not None and (previous is None or (candidate["score"], -candidate["start"], -candidate["end"]) > (previous["score"], -previous["start"], -previous["end"])):
        state["best"] = candidate
