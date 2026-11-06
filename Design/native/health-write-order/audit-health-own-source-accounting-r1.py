"""Read-only audit of archived native own-source observations; no UI/Health writes."""
import base64
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
prefix = "health-own-source-accounting-r1-"
case = json.loads((root / (prefix + "native.json")).read_text())
manifest = json.loads((root / (prefix + "manifest.json")).read_text())

def decoded(fact):
    data = base64.b64decode(fact["base64"], validate=True)
    assert len(data) == fact["bytes"]
    assert hashlib.sha256(data).hexdigest() == fact["sha256"]
    return data

for tree in [case["localSavedFiles"], case["preRebuildFiles"], case["savedFiles"]]:
    for fact in tree.values():
        decoded(fact)
journal = json.loads(decoded(case["preRebuildFiles"]["health-write-intent.json"]))
saves = [e for e in journal["events"] if e["action"] == "save"]
assert len(saves) == 2
positive = {}
for event in saves:
    assert set(event["acknowledged"]) == {c["metric"] for c in event["components"]}
    for component in event["components"]:
        assert component["value"] > 0
        positive[component["metric"]] = (event, component)
assert set(positive) == {"water", "calories", "protein", "carbs", "fiber"}
original = None
for suffix in ["observed.json", "reopened-own.json", "normal-startup-own.json"]:
    report = json.loads((root / (prefix + suffix)).read_text())
    assert report["manifest"] == manifest
    assert report["status"] == "observed-partial"  # Original six-sample expectation failed.
    assert report["mutatesHealth"] is False and report["permissionInferred"] is False
    assert len(report["observations"]) == 5
    assert {o["metric"] for o in report["observations"]} == set(positive)
    for observed in report["observations"]:
        event, component = positive[observed["metric"]]
        assert observed["source"] == "com.dbakp.lumen"
        assert observed["value"] == component["value"]
        assert observed["start"] == observed["end"] == component["date"]
        assert observed["syncVersion"] == 1
        assert observed["syncIdentifier"] == (
            f"com.dbakp.lumen.health.v1.{journal['owner']}.{event['id']}.{component['metric']}"
        )
    if original is None:
        original = report
    else:
        assert report["inspectedAt"] > original["inspectedAt"]
        assert report["observations"] == original["observations"]

external = json.loads((root / (prefix + "foreign-seeded.json")).read_text())
reopened = json.loads((root / (prefix + "foreign-reinspected.json")).read_text())
assert reopened["status"] == "inspected-complete"
assert external["rows"] == reopened["rows"] and len(reopened["observed"]) == 10
assert set(reopened["observed"]) == {r["uuid"] for r in reopened["rows"]}

before, after = case["preRebuildFiles"], case["savedFiles"]
assert len(before) == 13
for name, fact in before.items():
    if name != "today.json":
        assert after[name] == fact, name
added = set(after) - set(before)
assert len(added) == 4
copy = next(n for n in added if n.startswith(".health-recovery/") and n.endswith("/today.json"))
assert decoded(after[copy]) == decoded(before["today.json"])
intent = next(n for n in added if n.endswith("/device-intent.json"))
assert decoded(after[intent]) == decoded(before["health-write-intent.json"])
copy_manifest = json.loads(decoded(after[copy.rsplit("/", 1)[0] + "/manifest.json"]))
assert copy_manifest["domains"] == ["today"] and copy_manifest["intent"] is True
receipt = json.loads(decoded(after[next(n for n in added if n.startswith(".health-cache-history/"))]))
assert receipt["owner"] == journal["owner"] and receipt["action"] == "rebuild"
assert receipt["prior"]["entries"][""]["inode"] == before["today.json"]["inode"]
assert receipt["prior"]["entries"][""]["digest"] == before["today.json"]["sha256"]
raw_bytes = decoded(after["today.json"])
assert raw_bytes == (root / (prefix + "saved-raw.json")).read_bytes()
raw = json.loads(raw_bytes)
expected = {"water": 400, "calories": 350, "protein": 20, "carbs": 40, "fat": 12}
assert raw["excludesLumenNutrition"] is True and len(raw["readings"]) == 18
for metric, reading in raw["readings"].items():
    assert reading["healthQuery"]["outcome"] == ("recorded" if metric in expected else "noData")
    if metric in expected:
        assert len(reading["components"]) == 1
        component = reading["components"][0]
        assert component["value"] == expected[metric]
        assert component["origin"] == "healthKit" and component["aggregation"] == "total"
    else:
        assert reading["components"] == []
print("PASS archived five positive own identities, stable relaunch UUIDs, ten foreign identities, raw-only save and twelve preserved files.")
assert case["normalStartupAudit"]["launchArguments"] == []
assert case["normalStartupAudit"]["unchangedRecordBytes"] == ["water.json", "meals.json", "health-write-intent.json"]
print("PARTIAL original case: six-sample expectation disproved; original455calorie display uncaptured. One normal startup preserves all five identities. Subsequent positive-fat display and cleanup are audited separately; see audit-health-own-source-cleanup-r1.py.")
