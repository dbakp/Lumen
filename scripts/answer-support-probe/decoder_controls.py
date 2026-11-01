"""Independent source-bound decoder and Unicode/null/ownership controls."""
import itertools
import json
import math
from pathlib import Path
import sys
import numpy as np
from answer_decoder import best_span, finish, accumulate
from common import sha, save


def brute(starts, ends, offsets, sequence, regions):
    choices = []
    for a in range(len(starts)):
        for b in range(a, min(len(starts), a + 30)):
            if sequence[a] != 1 or sequence[b] != 1:
                continue
            left, right = offsets[a][0], offsets[b][1]
            owner = [n for n, r in enumerate(regions) if r["start"] <= offsets[a][0] < offsets[a][1] <= r["end"] and r["start"] <= offsets[b][0] < offsets[b][1] <= r["end"] and r["start"] <= left < right <= r["end"]]
            if owner:
                choices.append((float(starts[a]) + float(ends[b]), -a, -b, left, right, owner[0]))
    if not choices:
        return None
    score, a, b, left, right, owner = max(choices)
    return {"score": score, "start": left, "end": right, "regionIndex": owner, "tokenStart": -a, "tokenEnd": -b, "tokens": -b + a + 1}


def main(output):
    passed = []
    offsets = [(0, 0), (0, 6), (0, 6), (7, 10), (11, 19), (20, 21), (22, 30), (0, 0), (0, 0)]
    sequence = [None, 0, 1, 1, 1, 1, 1, None, None]
    regions = [{"id": "negative", "start": 7, "end": 19}, {"id": "positive", "start": 22, "end": 30}]
    starts = [-3, 100, 100, 4, 1, 999, 4, 99, 99]
    ends = [-3, 100, 100, 0, 5, 999, 2, 99, 99]
    result = best_span(starts, ends, offsets, sequence, regions)
    assert result["start"] == 7 and result["end"] == 19 and result["regionIndex"] == 0
    passed.append("question/header/padding/separator logits cannot erase literal negation")
    starts[3], ends[6] = 1000, 1000
    result = best_span(starts, ends, offsets, sequence, regions)
    assert result == brute(starts, ends, offsets, sequence, regions)
    assert not (result["tokenStart"] == 3 and result["tokenEnd"] == 6)
    passed.append("a highest-score cross-source answer is rejected")
    assert best_span([1, 2], [3, 4], [(0, 0), (0, 1)], [None, 0], []) is None
    passed.append("no legal source tokens yields no span")
    for value in [float('nan'), float('inf')]:
        try: best_span([value], [0], [(0, 1)], [1], [{"start": 0, "end": 1}])
        except ValueError: pass
        else: raise AssertionError("nonfinite model output accepted")
    passed.append("all nonfinite logits rejected")
    rng = np.random.default_rng(3301)
    for n in [1, 2, 7, 30, 31, 64]:
        for _ in range(12):
            offsets = [(2 * i, 2 * i + 1) for i in range(n)]
            regions = [{"id": "a", "start": 0, "end": max(1, n)}, {"id": "b", "start": max(1, n), "end": 2 * n + 1}]
            sequence = [1 if i % 7 else None for i in range(n)]
            a, b = rng.normal(size=n), rng.normal(size=n)
            actual = best_span(a, b, offsets, sequence, regions)
            assert actual == brute(a, b, offsets, sequence, regions)
    passed.append("72 independent exhaustive oracles cover length30, ties and source constraints")
    context = "Évaluation é: <4,0 µg/L"
    a = context.index('<'); b = len(context)
    example = {"id": "unicode", "group": "control", "context": context, "regions": [{"id": "literal", "start": 0, "end": len(context), "bodySHA256": sha(context.encode())}]}
    best = {"score": 4., "start": a, "end": b, "regionIndex": 0, "tokens": 3}
    for null, expected in [(5., ""), (4., "<4,0 µg/L"), (3., "<4,0 µg/L")]:
        result = finish(example, {"best": best, "null": null, "windows": 1, "status": "scored"})
        assert result['answer'] == expected
        c = result["bestCandidate"]
        assert context.encode()[c["byteStart"]:c["byteEnd"]].decode() == "<4,0 µg/L"
    passed.append("null/tie rule and original combining-Unicode/operator/unit byte offsets")
    feature_data = [([2., 3.], [2., 1.]), ([1., 2.], [1., 4.])]
    states = []
    for order in itertools.permutations(feature_data):
        state = {"best": None, "null": math.inf, "windows": 0, "status": "pending"}
        for a, b in order: accumulate(state, a, b, [(0, 0), (0, 1)], [None, 1], [{"id": "source", "start": 0, "end": 1}])
        states.append(state)
    assert states[0] == states[1] and states[0]['null'] == 2. and states[0]['best']['score'] == 6.
    passed.append("all-window minimum null and best-span aggregation independent of feature order")
    save(output, {"passed": len(passed), "checks": passed, "bruteForceInstances": 72, "sourceSHA256": sha(Path(__file__).read_bytes()), "decoderSHA256": sha(Path(__file__).with_name('answer_decoder.py').read_bytes()), "scope": "Algorithm/ownership/byte preservation controls, not answerability accuracy or clinical validation."})
    print(json.dumps({"passed": len(passed), "bruteForceInstances": 72}))


if __name__ == '__main__': main(Path(sys.argv[1]))
