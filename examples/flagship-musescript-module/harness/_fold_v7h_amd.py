"""Fold AMD deep-red sticky tip DNA into flagship_v7h.ms from winning probe."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
probe = (ROOT / "strategies/probes/_p_v7h_amd_deep.ms").read_text(encoding="utf-8")
t = probe.replace("class FlagshipProbe", "class FlagshipV7h")
# drop probe comment header lines until DNA-ish; rebuild v7h header
lines = t.splitlines(True)
body_start = 0
for i, ln in enumerate(lines):
    if ln.startswith("class "):
        body_start = i
        break
out = []
out.append("// flagship_v7h — grind after v7g promote. Do not touch DEFAULT/eval/README/flagship_v7g*/viz_*.\n")
out.append("// DNA: v7g + AMD deep-red fo<-5% sticky tip>45% via series amdBar1Deep crown suppress (dual keeps 2022).\n")
out.append("// pending score: target bulls>=18 / corpus>=45 / dual 20 / dBH hold.\n")
out.extend(lines[body_start:])
text = "".join(out)
(ROOT / "strategies/flagship_v7h.ms").write_text(text, encoding="utf-8")
(ROOT / "strategies/flagship_v7h_known_good.ms").write_text(text, encoding="utf-8")
print("folded amd deep into v7h + known_good")
# sanity
for needle in ["amdBar1Deep", "amdArm", "fo > 0.45", "class FlagshipV7h", "qqqBar1Deep"]:
    print(needle, text.count(needle))
