"""Independently enumerate every legal-length contiguous context span."""
import json
from pathlib import Path
import sys

from transformers import AutoTokenizer

from common import save, sha
from score import features


work = Path(sys.argv[1])
tokenizer = AutoTokenizer.from_pretrained(work / "model", local_files_only=True, use_fast=True, trust_remote_code=False)
cases = [("ordinary-budget", "What was reported?", " ".join("token" + str(i) for i in range(700))),
         ("minimum-budget", "q " * 349, "token " * 80)]
outcomes = []
for name, question, context in cases:
    example = {"question": question, "context": context, "regions": [{"start": 0, "end": len(context), "bodySHA256": sha(context.encode())}]}
    windows, status = features(example, tokenizer)
    assert status == "pending" and len(windows) > 1
    full = tokenizer(context, add_special_tokens=False, return_offsets_mapping=True)["offset_mapping"]
    represented = [{tuple(offset) for offset, sequence in zip(window["offsets"], window["sequence"]) if sequence == 1} for window in windows]
    checks = 0
    for start in range(len(full)):
        for length in range(1, min(30, len(full) - start) + 1):
            chunk = set(map(tuple, full[start:start + length]))
            assert any(chunk <= window for window in represented), (name, start, length)
            checks += 1
    outcomes.append({"name": name, "queryTokens": len(tokenizer(question, add_special_tokens=False)["input_ids"]),
                     "contextTokens": len(full), "windows": len(windows), "contiguousSpansVerified": checks})
save(work / "coverage-controls-r1.json", {"cases": outcomes, "passed": sum(row["contiguousSpansVerified"] for row in outcomes),
     "sourceSHA256": sha(Path(__file__).read_bytes()), "scorerSHA256": sha(Path(__file__).with_name("score.py").read_bytes()),
     "scope": "Every contiguous context span of1..30tokens occurs completely inside a represented overlapping window, including minimum32-token context budget. No model/gold fitting."})
print(json.dumps(outcomes))
