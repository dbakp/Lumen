"""Read-only audit of archived actual UI removal and SDK readbacks."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent


def read(name):
    return json.loads((root / name).read_text())


prefix = "health-own-source-cleanup-r1-"
local = read(prefix + "local.json")["records"]
assert local["water.json"] == local["meals.json"] == []
journal = local["health-write-intent.json"]
expected = {
    "FD301ADD-C3B2-4B0C-AAFF-B812DECB1DC8": {"water"},
    "731A7D55-B6C6-4569-8BA0-AA436EA7E5EC": {"calories", "protein", "carbs", "fiber"},
    "2252CA25-E122-43C9-806E-8F1BFCDEC9B3": {"calories", "protein", "carbs", "fat", "fiber"},
}
assert journal["owner"] == "01695DB8-4021-41A4-ABBF-63E03DB52DDD"
for local_id, metrics in expected.items():
    event = next(e for e in journal["events"] if e["localID"] == local_id)
    assert event["action"] == "delete" and event["identity"] == "sync"
    assert set(event["acknowledged"]) == metrics
    assert {c["metric"] for c in event["components"]} == metrics

for suffix, manifest_name, original_name in [
    ("positive-fat-empty.json", "health-own-source-positive-fat-r1-manifest.json", "health-own-source-positive-fat-r1-reopened-own.json"),
    ("banana-empty.json", "health-own-source-accounting-r1-manifest.json", "health-own-source-accounting-r1-normal-startup-own.json"),
]:
    report = read(prefix + suffix)
    assert report["manifest"] == read(manifest_name)
    assert report["status"] == "observed-empty" and report["observations"] == []
    assert report["mutatesHealth"] is False and report["permissionInferred"] is False
    assert report["inspectedAt"] > read(original_name)["inspectedAt"]

foreign = read(prefix + "foreign-preserved.json")
original = read("health-own-source-positive-fat-r1-foreign-preserved.json")
assert foreign["status"] == "inspected-complete"
assert foreign["source"] == "com.dbakp.lumen.fixture.health-source"
assert foreign["rows"] == original["rows"]
assert set(foreign["observed"]) == set(original["observed"])
assert len(set(foreign["observed"])) == 10
for suffix, status in [("foreign-removed.json", "cleaned"), ("foreign-empty.json", "inspected-partial")]:
    report = read(prefix + suffix)
    assert report["run"] == foreign["run"] and report["source"] == foreign["source"]
    assert report["rows"] == foreign["rows"] and report["observed"] == []
    assert report["status"] == status

print("PASS actual UI removal: local water/meals empty, all ten deletion acknowledgements, both exact own manifests empty, ten external identities preserved, external cleanup and independent empty reinspection.")
outcome_path = root / (prefix + "outcome.json")
if outcome_path.exists():
    outcome = read(outcome_path.name)
    assert outcome["freshNativeQuery"] == {"recorded": 0, "noData": 18, "failed": 0}
    assert outcome["filesAfter"] == read(prefix + "before-query.json")["files"]
    assert outcome["preservedFiles"] == 21
    print("PASS fresh native query:18noData/0recorded/0failed; all21fileidentities preserved through archived checkpoint.")
    navigation = outcome["navigation"]
    print("Final navigation:", {k: navigation[k] for k in ["notNow", "back", "idleAfterBackAtLeastSeconds", "originalLongWaitBaselinePreserved"] if k in navigation})
    if navigation.get("notNow") is True:
        baseline = read(navigation["beforeActionBaseline"])
        assert navigation["back"] and navigation["idleAfterBackAtLeastSeconds"] >= 4
        assert navigation["filesAfter"] == baseline["currentFiles"]
        assert len(navigation["filesAfter"]) == 21
        assert navigation["originalLongWaitBaselinePreserved"] is False
        assert baseline["comparisonWithOriginalQueryBaseline"] is False
        assert set(baseline["changes"]) == {"workouts.json", "sleep.json", "today.json", "healthSync.json", "habits.json", "profile.json"}
        newer_raw = (root / "health-own-source-cleanup-r1-newer-raw.json").read_bytes()
        import hashlib
        assert hashlib.sha256(newer_raw).hexdigest() == navigation["filesAfter"]["today.json"]["sha256"]
        newer = json.loads(newer_raw)
        assert len(newer["readings"]) == 18
        assert all(r["healthQuery"]["outcome"] == "noData" and r["components"] == [] for r in newer["readings"].values())
        print("PASS actual Notnow/Back/idle preserves immediate21filebaseline including neweremptycache. Original long-wait21identityexpectation FAILED and retained; cause not attributed.")
else:
    print("Final native navigation/file preservation outcome not yet archived.")
