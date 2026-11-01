"""Post-output reviewed expectations and exact rendering/token/anchor replay."""
import json
from pathlib import Path
import sys

from transformers import AutoTokenizer

from common import EVIDENCE, ROOT, checked, file_digest, policy, save, sha


work = Path(sys.argv[1]); frozen = policy()
report = json.loads((EVIDENCE / "synthetic-results.json").read_bytes())
tokenizer = AutoTokenizer.from_pretrained(work / "model", local_files_only=True, trust_remote_code=False, use_fast=True)
prompt = checked(EVIDENCE / "prompt.txt", frozen["prompt"]["sha256"]).decode()
config = json.loads((work / "model/config.json").read_bytes())
generation = json.loads((work / "model/generation_config.json").read_bytes())
eos = generation["eos_token_id"]; allowed_eos = [eos] if isinstance(eos, int) else eos
case_checks = anchors = tokens = 0
nonempty_negatives = {"u-vitamin", "u-calcium", "u-cholesterol"}
strict_native = {"p-hemoglobin", "p-allergy"}
strict_stress = {"s-noor", "s-negative"}
for case in report["cases"]:
    example, output = case["input"], case["rawOutput"]
    group, query = example["id"].split("/", 1)
    expected_complete = query.startswith("p-") and query != "p-walk" if group != "stress" else query in {"s-reviewed", "s-original", "s-noor", "s-negative"}
    if not case["gold"]["requiredParts"]:
        expected_complete = query not in nonempty_negatives and group != "stress"
    expected_strict = query in strict_native if group != "stress" else query in strict_stress
    if not case["gold"]["requiredParts"]:
        expected_strict = expected_complete
    assert case["mechanical"] is not None and case["mechanicalError"] is None
    assert case["literalClauseComplete"] == expected_complete, example["id"]
    assert case["strictBatch33AliasDiagnostic"] == expected_strict, example["id"]
    case_checks += 3
    # Pretty evidence sorts JSON object keys; the actual pre-score input uses
    # id,title,savedText. Restore the frozen renderer's order for byte replay.
    sources = [{"id": s["id"], "title": s["title"], "savedText": s["savedText"]} for s in example["sources"]]
    payload = json.dumps({"question": example["question"], "sources": sources}, ensure_ascii=False, separators=(",", ":"))
    text = tokenizer.apply_chat_template([{"role": "system", "content": prompt}, {"role": "user", "content": payload}],
        tokenize=False, add_generation_prompt=True, enable_thinking=False)
    assert sha(payload.encode()) == output["inputPayloadSHA256"] and sha(text.encode()) == output["promptSHA256"]
    assert len(tokenizer(text, add_special_tokens=False)["input_ids"]) == output["promptTokens"]
    assert output["generationComplete"] and output["status"] == "generated"
    assert output["generatedTokenIDs"][-1] in allowed_eos
    assert tokenizer.decode(output["generatedTokenIDs"][:-1], skip_special_tokens=False) == output["rawText"]
    assert output["finiteLogitSteps"] == len(output["generatedTokenIDs"])
    assert all(0 <= token < config["vocab_size"] for token in output["generatedTokenIDs"])
    tokens += len(output["generatedTokenIDs"])
    source_map = {source["id"]: source["savedText"] for source in example["sources"]}
    for anchor in case["mechanical"]["anchors"]:
        body, value = source_map[anchor["sourceID"]], anchor["quote"]
        assert body[anchor["start"]:anchor["end"]] == value
        assert body.encode()[anchor["byteStart"]:anchor["byteEnd"]] == value.encode()
        occurrences = [i for i in range(len(body) - len(value) + 1) if body.startswith(value, i)]
        assert occurrences == [anchor["start"]]
        anchors += 1
run = json.loads((work / "run-complete.json").read_bytes())
assert tokens == run["generatedTokens"] == 4315
save(work / "independent-checks.json", {"postOutputReviewedCaseComparisons": case_checks, "promptPayloadTokenReplayCases": len(report["cases"]),
    "literalUniqueAnchorChecks": anchors, "finiteGeneratedTokenChecks": tokens,
    "sourceSHA256": file_digest(Path(__file__)), "resultSHA256": file_digest(EVIDENCE / "synthetic-results.json"),
    "scope": "Reviewed expected-outcome matrix is an independent post-output check of calculation, not frozen gold, blind evaluation or a model-policy change. Every actual prompt/payload/token count and EOS-trimmed raw output replays with the pinned tokenizer; anchors independently enumerated."})
print(json.dumps({"caseComparisons": case_checks, "promptReplays": len(report["cases"]), "anchors": anchors, "tokens": tokens}))
