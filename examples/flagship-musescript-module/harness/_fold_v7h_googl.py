"""Fold GOOGL deep probe into flagship_v7h.ms."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
probe = (ROOT / "strategies/probes/_p_v7h_googl_deep.ms").read_text(encoding="utf-8")
t = probe.replace("class FlagshipProbe", "class FlagshipV7h")
lines = t.splitlines(True)
body_start = next(i for i, ln in enumerate(lines) if ln.startswith("class "))
out = []
out.append("// flagship_v7h — grind after v7g promote. Do not touch DEFAULT/eval/README/flagship_v7g*/viz_*.\n")
out.append("// DNA: v7g + AMD fo<-5% tip>45% amdBar1Deep + GOOGL fo<-2% tip>15% googlBar1Deep (series-time).\n")
out.append("// dual 20/20, bulls 19/20, corpus 46/60, dBH ~+1.58 (vs v7g 17/20 + 44/60). PENDING VERIFY.\n")
out.extend(lines[body_start:])
text = "".join(out)
(ROOT / "strategies/flagship_v7h.ms").write_text(text, encoding="utf-8")
(ROOT / "strategies/flagship_v7h_known_good.ms").write_text(text, encoding="utf-8")
for n in [
    "amdBar1Deep",
    "googlBar1Deep",
    "amdArm",
    "googlArm",
    "qqqBar1Deep",
    "fo > 0.45",
    "fo > 0.15",
    "class FlagshipV7h",
]:
    print(n, text.count(n))
print("folded")
