"""Fold NVDA deep-red sticky tip DNA into flagship_v7h.ms from winning probe."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
probe = (ROOT / "strategies/probes/_p_v7h_nvda_deep.ms").read_text(encoding="utf-8")
t = probe.replace("class FlagshipProbe", "class FlagshipV7h")
lines = t.splitlines(True)
body_start = 0
for i, ln in enumerate(lines):
    if ln.startswith("class "):
        body_start = i
        break
out = []
out.append("// flagship_v7h - grind after v7g promote. Do not touch DEFAULT/eval/README/flagship_v7g*/viz_*.\n")
out.append("// DNA: v7g + AMD fo<-5% tip>45% amdBar1Deep + GOOGL fo<-2% tip>15% googlBar1Deep + NVDA fo<-4% tip>35% nvdaBar1Deep (series-time).\n")
out.append("// dual 20/20, bulls 20/20?, corpus ?, dBH ~+1.58 — NVDA@2019 unlock candidate.\n")
out.extend(lines[body_start:])
text = "".join(out)
(ROOT / "strategies/flagship_v7h.ms").write_text(text, encoding="utf-8")
(ROOT / "strategies/flagship_v7h_known_good.ms").write_text(text, encoding="utf-8")
print("folded nvda deep into v7h + known_good")
for needle in ["nvdaBar1Deep", "nvdaArm", "fo > 0.35", "fo < -0.04", "class FlagshipV7h", "amdBar1Deep", "googlBar1Deep", "qqqBar1Deep"]:
    print(needle, text.count(needle))
