"""One separately predeclared query-only instruction; never a text rewriter."""
import hashlib
import json
from pathlib import Path


def instruction_queries(query_bytes):
    root = Path(__file__).resolve().parents[2] / "Design/native/retrieval-quality"
    protocol_bytes = (root / "instruction-protocol.json").read_bytes()
    protocol = json.loads(protocol_bytes)
    if protocol["name"] != "medembed-bge-query-instruction-dev" or protocol["queryPrefix"] != "Represent this sentence for searching relevant passages: ":
        raise ValueError("Unknown instruction experiment")
    for name, key in [("retrieval-protocol.json", "originalProtocolSHA256"), ("dev-decision.json", "priorRawQueryDecisionSHA256")]:
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != protocol[key]:
            raise ValueError("Original frozen protocol or prior decision changed")
    rows = [json.loads(line) for line in query_bytes.decode().splitlines()]
    transformed = [{"id": row["id"], "text": protocol["queryPrefix"] + row["text"]} for row in rows]
    encoded = "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in transformed).encode()
    return encoded, {"name": protocol["name"], "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(), "corpusVectorsSHA256": protocol["corpusVectorsSHA256"], "queryPrefix": protocol["queryPrefix"]}
