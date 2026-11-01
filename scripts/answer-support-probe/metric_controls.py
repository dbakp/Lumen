"""Literal health constraints remain distinct from public benchmark scoring."""
import json
from pathlib import Path
import sys

from common import save, sha
from evaluate import literal_complete, normalize_public, public_score


checks = [
    (literal_complete("<4,0 µg/L", ["<4,0 µg/L"]), "literal operator/comma/micro/unit preserved"),
    (not literal_complete("4.0 ug/L", ["<4,0 µg/L"]), "operator/decimal/unit rewrite rejected"),
    (not literal_complete("detected", ["not detected"]), "lost negation rejected"),
    (not literal_complete("2026-11-04", ["14:32 on 2026-11-04"]), "partial date/time rejected"),
    (not literal_complete("500 mg", []), "missing fact has no accepted answer"),
    (literal_complete("  12.1\ng/dL. ", ["12.1 g/dL"]), "whitespace and following sentence period accepted"),
    (not literal_complete("Hemoglobin 12.1 g/dL", ["12.1 g/dL"]), "unlisted prefix remains strict miss"),
    (not literal_complete("12.1 G/DL", ["12.1 g/dL"]), "case stays literal"),
    (normalize_public("The—an apple, a pear!") == "— apple pear", "public Unicode word boundaries/articles"),
    (normalize_public("x—an—y") == "x— —y", "public article removal preserves token boundaries"),
    (public_score("a red blue", ["blue red green"]) == (0, .8), "public multiset token F1"),
    (public_score("", [""]) == (1, 1.), "public empty answer agreement"),
    (public_score("blue", ["red", "blue"]) == (1, 1.), "public multiple gold maximum"),
]
for passed, name in checks:
    if not passed:
        raise AssertionError(name)
save(Path(sys.argv[1]), {"passed": len(checks), "checks": [name for _, name in checks],
    "metricSourceSHA256": sha(Path(__file__).with_name("evaluate.py").read_bytes()),
    "controlSourceSHA256": sha(Path(__file__).read_bytes()),
    "scope": "Independent hand-expected metric controls; full official per-case comparison is separate."})
print(json.dumps({"passed": len(checks)}))
