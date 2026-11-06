"""Audit actual zero-valued SDK fixtures; does not substitute for Lumen UI checks."""
import base64
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent


def read(suffix):
    return json.loads((root / ("health-zero-nutrition-r1-" + suffix)).read_text())


contract = read("contract.json")
seed, inspected, after_legacy = [read(s) for s in ["seeded.json", "reinspected.json", "after-legacy-inspection.json"]]
assert seed["status"] == "seeded"
assert inspected["status"] == after_legacy["status"] == "inspected-complete"
assert seed["rows"] == inspected["rows"] == after_legacy["rows"]
assert len(seed["rows"]) == contract["expectedSamples"] == 5
assert len(set(seed["observed"])) == 5
assert set(seed["observed"]) == set(inspected["observed"]) == set(after_legacy["observed"])
assert set(seed["observed"]) == {r["uuid"] for r in seed["rows"]}
assert {r["identifier"] for r in seed["rows"]} == {
    "HKQuantityTypeIdentifierDietaryWater", "HKQuantityTypeIdentifierDietaryEnergyConsumed",
    "HKQuantityTypeIdentifierDietaryProtein", "HKQuantityTypeIdentifierDietaryCarbohydrates",
    "HKQuantityTypeIdentifierDietaryFatTotal",
}
for report in [seed, inspected, after_legacy]:
    assert report["run"] == contract["run"]
    assert report["dataset"] == "zeroNutrition" and report["version"] == 4
    assert report["source"] == "com.dbakp.lumen.fixture.health-source"
    for row in report["rows"]:
        assert row["value"] == 0 and row["start"] == row["end"]
        assert row["start"] + 978307200 > contract["createdAt"] - 125
for suffix, version, count in [("v1-empty.json", 1, 10), ("v2-empty.json", 2, 22)]:
    report = read(suffix)
    assert report["version"] == version and len(report["rows"]) == count
    assert report["observed"] == [] and report["status"] == "inspected-partial"
before = read("before.json")["files"]
assert len(before) == 24
for fact in before.values():
    data = base64.b64decode(fact["base64"], validate=True)
    assert len(data) == fact["bytes"] and hashlib.sha256(data).hexdigest() == fact["sha256"]
native = read("native.json")
assert native["preservedLumenFiles"] == 24 and native["sourceAudit"]["filesMatched"] == 259
assert native["legacyLedgerCompatibility"]["zeroSamplesPreserved"] == 5
assert native["originalScreenshot"]["sha256"] == hashlib.sha256((root / native["originalScreenshot"]["file"]).read_bytes()).hexdigest()
print("PASS five actual zero-valued SDK samples with stable exact identities; old V1/V2 ledgers remain empty; archived24file facts valid and Source162 inputs exact.")
print("PARTIAL: actual Lumen zero-vs-missing query/commit/native navigation and exact scoped cleanup remain pending. Five samples remain in use in the dedicated main simulator.")
