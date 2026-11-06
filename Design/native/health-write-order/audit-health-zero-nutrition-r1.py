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
if "commitAudit" in native:
    for tree in [native["preRebuildFiles"], native["savedFiles"], native["previousBeforeRebuild"], native["previousAfterRebuild"], native["afterNavigationFiles"], native["previousAfterNavigation"]]:
        for fact in tree.values():
            data = base64.b64decode(fact["base64"], validate=True)
            assert len(data) == fact["bytes"] and hashlib.sha256(data).hexdigest() == fact["sha256"]
    prior, saved = native["preRebuildFiles"], native["savedFiles"]
    assert len(prior) == 24 and len(saved) == 28
    for name, fact in prior.items():
        if name != "today.json":
            assert saved[name] == fact, name
    assert native["previousBeforeRebuild"] == native["previousAfterRebuild"] == native["previousAfterNavigation"]
    assert len(native["previousBeforeRebuild"]) == 9
    assert native["afterNavigationFiles"] == saved
    raw = (root / "health-zero-nutrition-r1-saved-raw.json").read_bytes()
    assert raw == base64.b64decode(saved["today.json"]["base64"])
    day = json.loads(raw)
    assert day["excludesLumenNutrition"] and len(day["readings"]) == 18
    for key, reading in day["readings"].items():
        recorded = key in contract["expectedRaw"]
        assert reading["healthQuery"]["outcome"] == ("recorded" if recorded else "noData")
        if recorded:
            assert len(reading["components"]) == 1 and reading["components"][0]["value"] == 0
        else:
            assert reading["components"] == []
    added = set(saved) - set(prior)
    assert len(added) == 4
    copy = next(n for n in added if n.endswith("/today.json"))
    intent = next(n for n in added if n.endswith("/device-intent.json"))
    assert saved[copy]["base64"] == prior["today.json"]["base64"]
    assert saved[intent]["base64"] == prior["health-write-intent.json"]["base64"]
    receipt = json.loads(base64.b64decode(saved[next(n for n in added if n.startswith(".health-cache-history/"))]["base64"]))
    assert receipt["action"] == "rebuild" and receipt["prior"]["entries"][""]["digest"] == prior["today.json"]["sha256"]
    assert receipt["rawDigest"] == saved["today.json"]["sha256"]
    assert read("after-native-save.json")["rows"] == seed["rows"]
    for suffix, status in [("cleaned.json", "cleaned"), ("empty.json", "inspected-partial")]:
        report = read(suffix)
        assert report["run"] == contract["run"] and report["rows"] == seed["rows"]
        assert report["status"] == status and report["observed"] == []
    assert native["nativeQuery"]["recorded"] == 5 and native["nativeQuery"]["noData"] == 13
    assert native["removalControl"]["freshNativeQuery"] == {"recorded": 0, "noData": 18, "failed": 0}
    assert native["removalControl"]["notNow"] and native["removalControl"]["back"]
    assert native["removalControl"]["idleAtLeastSeconds"] >= 4 and native["liveSamples"] == 0
    assert set(native["startupDiagnostic"]["changes"]) == {"sleep.json", "habits.json", "profile.json"}
    print("PASS scoped manualSource162 native5recorded-zero/13noData commit,23other-current/9prior identities, retained priorraw/intent, exactSDKcleanup and fresh18noData;28current/9prior exact through Not now/Back/idle.")
    print("Initial whole-tree startup preservation expectation remains failed; no full18detail pixels, Source163 runtime, appearance or broader product acceptance inferred.")
else:
    print("PARTIAL: actual Lumen zero-vs-missing query/commit/native navigation and exact scoped cleanup remain pending. Five samples remain in use in the dedicated main simulator.")
