"""Mechanical quote provenance, deliberately not semantic entailment."""
import json
import re


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError("duplicateJSONKey")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError("nonfiniteJSON")


def validate(text, sources, complete=True):
    if not complete:
        raise ValueError("incompleteGeneration")
    if len(text.encode()) > 32768:
        raise ValueError("responseByteLimit")
    reply = json.loads(text, object_pairs_hook=pairs, parse_constant=reject_constant)
    if type(reply) is not dict or set(reply) != {"answerable", "answer", "evidence"}:
        raise ValueError("responseShape")
    if type(reply["answerable"]) is not bool or type(reply["answer"]) is not str or type(reply["evidence"]) is not list:
        raise ValueError("responseTypes")
    if len(reply["answer"].encode()) > 4096 or len(reply["evidence"]) > 8:
        raise ValueError("answerOrEvidenceLimit")
    if not reply["answerable"]:
        if reply["answer"] or reply["evidence"]:
            raise ValueError("nonemptyAbstention")
        return {"reply": reply, "anchors": [], "scope": "Mechanically valid empty answer, not proof that the question is unanswerable."}
    if not reply["answer"].strip() or not reply["evidence"]:
        raise ValueError("missingAnswerOrEvidence")
    source_map = {source["id"]: source["savedText"] for source in sources}
    if len(source_map) != len(sources):
        raise ValueError("duplicateInputSource")
    anchors = []
    for item in reply["evidence"]:
        if type(item) is not dict or set(item) != {"sourceID", "quote"} or any(type(item[k]) is not str for k in item):
            raise ValueError("evidenceShape")
        key, quote = item["sourceID"], item["quote"]
        if key not in source_map:
            raise ValueError("unknownSource")
        if not quote.strip() or len(quote.encode()) > 2048:
            raise ValueError("quoteByteLimit")
        body = source_map[key]
        start = body.find(quote)
        if start < 0:
            raise ValueError("nonliteralQuote")
        if body.find(quote, start + 1) >= 0:
            raise ValueError("ambiguousQuote")
        end = start + len(quote)
        byte_start, byte_end = len(body[:start].encode()), len(body[:end].encode())
        if body.encode()[byte_start:byte_end] != quote.encode():
            raise ValueError("nonliteralUTF8Anchor")
        anchors.append({"sourceID": key, "start": start, "end": end, "byteStart": byte_start, "byteEnd": byte_end, "quote": quote})
    return {"reply": reply, "anchors": anchors, "scope": "Exact quote/owner provenance only; no implication that quotes entail answer claims or answer this question."}


def contains_literal(text, value):
    text, value = " ".join(text.split()), " ".join(value.split())
    return re.search(r"(?<!\w)" + re.escape(value) + r"(?!\w)", text) is not None


def completion(validated, gold, owners):
    reply = validated["reply"]
    if not gold["requiredParts"]:
        return not reply["answerable"]
    if not reply["answerable"] or any(contains_literal(reply["answer"], phrase) for phrase in gold["forbiddenAnswerPhrases"]):
        return False
    for aliases in gold["requiredParts"]:
        if not any(contains_literal(reply["answer"], alias) and any(owners[anchor["sourceID"]] in gold["expectedDocumentIDs"] and contains_literal(anchor["quote"], alias) for anchor in validated["anchors"]) for alias in aliases):
            return False
    return True
