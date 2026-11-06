"""Read-only audit of retained positive-fat native/SDK evidence."""
import base64
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
prefix = "health-own-source-positive-fat-r1-"
case = json.loads((root / (prefix + "native.json")).read_text())
contract = json.loads((root / (prefix + "contract.json")).read_text())

def data(fact):
    value = base64.b64decode(fact["base64"], validate=True)
    assert len(value) == fact["bytes"] and hashlib.sha256(value).hexdigest() == fact["sha256"]
    return value

for tree in [case["beforeRecoveryFiles"], case["preRebuildFiles"], case["savedFiles"]]:
    for fact in tree.values():
        data(fact)
manifest = case["manifest"]
reports = [json.loads((root / (prefix + suffix)).read_text()) for suffix in ["observed.json", "reopened-own.json"]]
for report in reports:
    assert report["manifest"] == manifest and report["status"] == "observed-complete"
    assert not report["mutatesHealth"] and not report["permissionInferred"]
    assert len(report["observations"]) == 6
    assert {o["metric"] for o in report["observations"]} == {"water", "calories", "protein", "carbs", "fat", "fiber"}
    for observed in report["observations"]:
        row = next(r for r in manifest["rows"] if r["metric"] == observed["metric"])
        assert observed["source"] == "com.dbakp.lumen" and observed["value"] == row["value"] > 0
        assert observed["start"] == observed["end"] == row["date"] and observed["syncVersion"] == 1
        assert observed["syncIdentifier"] == f"com.dbakp.lumen.health.v1.{manifest['owner']}.{row['event']}.{row['metric']}"
assert reports[1]["inspectedAt"] > reports[0]["inspectedAt"]
assert reports[0]["observations"] == reports[1]["observations"]
prior = json.loads((root / (prefix + "prior-banana-preserved.json")).read_text())
original = json.loads((root / "health-own-source-accounting-r1-normal-startup-own.json").read_text())
assert prior["observations"] == original["observations"] and prior["inspectedAt"] > original["inspectedAt"]
all_own = {o["uuid"] for report in [reports[1], prior] for o in report["observations"]}
assert len(all_own) == 10
foreign = json.loads((root / (prefix + "foreign-preserved.json")).read_text())
original_foreign = json.loads((root / "health-own-source-accounting-r1-foreign-reinspected.json").read_text())
assert foreign["status"] == "inspected-complete" and len(foreign["observed"]) == 10
assert foreign["rows"] == original_foreign["rows"] and set(foreign["observed"]) == set(original_foreign["observed"])
assert all_own.isdisjoint(foreign["observed"])

before, after = case["preRebuildFiles"], case["savedFiles"]
assert len(before) == 17
for name, fact in before.items():
    if name != "today.json":
        assert after[name] == fact, name
added = set(after) - set(before)
assert len(added) == 4
copy = next(n for n in added if n.endswith("/today.json"))
intent = next(n for n in added if n.endswith("/device-intent.json"))
assert data(after[copy]) == data(before["today.json"])
assert data(after[intent]) == data(before["health-write-intent.json"])
journal = json.loads(data(after["health-write-intent.json"]))
for row in manifest["rows"]:
    event = next(e for e in journal["events"] if e["id"] == row["event"])
    assert event["action"] == "save" and event["localID"] == row["localID"]
    assert row["metric"] in event["acknowledged"]
    assert next(c for c in event["components"] if c["metric"] == row["metric"])["value"] == row["value"]
receipt = json.loads(data(after[next(n for n in added if n.startswith(".health-cache-history/"))]))
assert receipt["owner"] == manifest["owner"] and receipt["action"] == "rebuild"
assert receipt["prior"]["entries"][""]["digest"] == before["today.json"]["sha256"]
saved = json.loads((root / (prefix + "saved-raw.json")).read_text())
refreshed = json.loads((root / (prefix + "normal-refresh-raw.json")).read_text())
assert data(after["today.json"]) == (root / (prefix + "saved-raw.json")).read_bytes()
for snapshot in [saved, refreshed]:
    assert snapshot["excludesLumenNutrition"] and len(snapshot["readings"]) == 18
    for metric, reading in snapshot["readings"].items():
        expected = contract["expectedRaw"]
        assert reading["healthQuery"]["outcome"] == ("recorded" if metric in expected else "noData")
        if metric in expected:
            assert len(reading["components"]) == 1 and reading["components"][0]["value"] == expected[metric]
        else:
            assert reading["components"] == []
for metric in saved["readings"]:
    assert refreshed["readings"][metric]["healthQuery"]["checkedAt"] > saved["readings"][metric]["healthQuery"]["checkedAt"]
assert case["reopenedAudit"]["startupSuppressed"] is False
assert case["reopenedAudit"]["nativeTotals"] == contract["expectedCombined"]
print("PASS archived six positive exact SDK components, all20 own/external identities, raw-only commit and fresh normal refresh,16 preserved files and retained prior snapshot/intent.")
print("Historical commit/display stage audit: XS capture. Standard-text capture and actual scoped deletion/fresh empty query are audited separately by audit-health-own-source-cleanup-r1.py. No full visual/product acceptance.")
