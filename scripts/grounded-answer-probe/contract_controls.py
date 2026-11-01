"""Hand-authored acceptance/rejection and semantic-limit controls."""
import json
from pathlib import Path
import sys

from common import save, sha
from contract import completion, contains_literal, validate


source = [{"id": "s1", "savedText": "Reviewed: <4,0 µg/L. Original: <5,0 µg/L. No fever. Woke three times."}]


def response(answer="<4,0 µg/L", quote="Reviewed: <4,0 µg/L", source_id="s1"):
    return json.dumps({"answerable": True, "answer": answer, "evidence": [{"sourceID": source_id, "quote": quote}]}, ensure_ascii=False)


checks = []


def rejects(name, text, sources=source, complete=True):
    try:
        validate(text, sources, complete)
    except (ValueError, RecursionError):
        checks.append(name)
    else:
        raise AssertionError(name)


value = validate(response(), source)
assert value["anchors"][0]["byteEnd"] > value["anchors"][0]["end"]
checks.append("original operator/comma/micro unit with UTF8 anchor")
rejects("duplicate top-level keys", '{"answerable":true,"answerable":false,"answer":"","evidence":[]}')
rejects("duplicate nested keys", '{"answerable":true,"answer":"x","evidence":[{"sourceID":"s1","sourceID":"s1","quote":"x"}]}')
rejects("extra keys", '{"answerable":false,"answer":"","evidence":[],"confidence":1}')
rejects("integer is not boolean", '{"answerable":0,"answer":"","evidence":[]}')
rejects("NaN rejected", '{"answerable":false,"answer":NaN,"evidence":[]}')
rejects("JSON fences rejected", '```json\n{"answerable":false,"answer":"","evidence":[]}\n```')
rejects("incomplete generation rejected even with valid JSON", response(), complete=False)
rejects("nonempty abstention rejected", '{"answerable":false,"answer":"unknown","evidence":[]}')
rejects("empty positive evidence rejected", '{"answerable":true,"answer":"x","evidence":[]}')
rejects("changed operator quote rejected", response(quote="Reviewed: 4,0 µg/L"))
rejects("changed unit quote rejected", response(quote="Reviewed: <4,0 ug/L"))
rejects("wrong source rejected", response(source_id="s2"))
rejects("repeated ambiguous quote rejected", response(quote="value"), [{"id": "s1", "savedText": "value value"}])
rejects("response byte bound", " " * 32769)
rejects("answer byte bound", response(answer="x" * 4097))
rejects("quote byte bound", response(quote="x" * 2049), [{"id": "s1", "savedText": "x" * 2049}])
rejects("evidence count bound", json.dumps({"answerable": True, "answer": "x", "evidence": [{"sourceID": "s1", "quote": "No fever"}] * 9}))
assert not contains_literal("unpaid", "paid") and not contains_literal("preTH-Q8post", "TH-Q8")
checks.append("literal word/identifier boundaries")
gold = {"requiredParts": [["<4,0 µg/L"], ["three times"]], "expectedDocumentIDs": ["owner1"], "forbiddenAnswerPhrases": []}
assert not completion(value, gold, {"s1": "owner1"})
checks.append("partial compound answer rejected")
assert not completion(value, dict(gold, requiredParts=[["<4,0 µg/L"]]), {"s1": "owner2"})
checks.append("correct literal with wrong original owner rejected")
no_fever = validate(response(answer="no fever", quote="No fever"), source)
assert not completion(no_fever, {"requiredParts": [["fever"]], "expectedDocumentIDs": ["owner1"], "forbiddenAnswerPhrases": ["no fever"]}, {"s1": "owner1"})
checks.append("forbidden negation conflicts rejected")
# This intentionally passes mechanical anchoring: the gate must never claim
# semantic entailment merely because a real quote accompanies an invented claim.
misleading = validate(response(answer="The reviewed result is 900 mg/L"), source)
assert misleading["reply"]["answer"] == "The reviewed result is 900 mg/L"
checks.append("mechanical anchor can accompany a false claim: explicit semantic limit")
save(Path(sys.argv[1]), {"passed": len(checks), "checks": checks,
    "contractSHA256": sha(Path(__file__).with_name("contract.py").read_bytes()), "sourceSHA256": sha(Path(__file__).read_bytes()),
    "scope": "Mechanical/coverage controls and a deliberate false-claim counterexample; not semantic/clinical validation."})
print(json.dumps({"passed": len(checks)}))
