#!/usr/bin/env python3
"""Parses a CorpusEvoRun log and renders a self-contained HTML dashboard.
Re-run this (same output path) to refresh the dashboard while a run is in progress --
Artifact publishing to the same file_path redeploys to the same URL."""
import re
import sys
import json
import time
import os

LOG_PATH = sys.argv[1] if len(sys.argv) > 1 else "build/graal/fibfourier_run2.log"
OUT_PATH = sys.argv[2] if len(sys.argv) > 2 else "scratch/evo_dashboard.html"

GEN_RE = re.compile(
    r"^gen\s*(\d+)\s*\|\s*popSize=(\d+)\s*uniq=(\d+)\s*new=(\d+)\s*fallback=(\d+)\s*triaged=(\d+)\s*valid=(\d+)\s*niches=(\d+)\s*\|\s*"
    r"best=([\-0-9.]+)\s*mean=([\-0-9.]+)\s*champion=\"([^\"]*)\"\s*\|\s*(\d+)ms"
)

def parse(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = GEN_RE.match(line.strip())
            if m:
                rows.append({
                    "gen": int(m.group(1)),
                    "popSize": int(m.group(2)),
                    "uniq": int(m.group(3)),
                    "fallback": int(m.group(5)),
                    "triaged": int(m.group(6)),
                    "valid": int(m.group(7)),
                    "niches": int(m.group(8)),
                    "best": float(m.group(9)),
                    "mean": float(m.group(10)),
                    "champion": m.group(11),
                    "ms": int(m.group(12)),
                })
    return rows

def status_of(path):
    if not os.path.exists(path):
        return "not started"
    with open(path, "r", errors="replace") as f:
        content = f.read()
    if "CORPUS_EVO_OK" in content:
        return "complete"
    return "running"

rows = parse(LOG_PATH)
status = status_of(LOG_PATH)
last = rows[-1] if rows else None
total_gens = None
m = re.search(r"--gens (\d+)", " ".join(sys.argv))
data_json = json.dumps(rows)
now = time.strftime("%Y-%m-%d %H:%M:%S")

html = """<title>MuseGene Evolution — Live Dashboard</title>
<style>
.viz-root {{
  color-scheme: light;
  --surface-1: #fcfcfb; --surface-2: #f2f1ed; --text-primary: #0b0b0b; --text-secondary: #52514e; --text-muted: #7a796f;
  --series-1: #2a78d6; --series-2: #eb6834; --series-3: #1baf7a; --border: #e2e0d8;
}}
@media (prefers-color-scheme: dark) {{
  :root:where(:not([data-theme="light"])) .viz-root {{
    color-scheme: dark;
    --surface-1: #1a1a19; --surface-2: #232320; --text-primary: #ffffff; --text-secondary: #c3c2b7; --text-muted: #8a887c;
    --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70; --border: #35342e;
  }}
}}
:root[data-theme="dark"] .viz-root {{
  color-scheme: dark;
  --surface-1: #1a1a19; --surface-2: #232320; --text-primary: #ffffff; --text-secondary: #c3c2b7; --text-muted: #8a887c;
  --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70; --border: #35342e;
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
.viz-root {{ background: var(--surface-1); color: var(--text-primary); padding: 24px; min-height: 100vh; }}
h1 {{ font-size: 20px; margin: 0 0 4px; }}
.subtitle {{ color: var(--text-secondary); font-size: 13px; margin-bottom: 20px; }}
.status-row {{ display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 24px; }}
.tile {{ background: var(--surface-2); border: 1px solid var(--border); border-radius: 10px; padding: 12px 16px; min-width: 140px; }}
.tile .label {{ font-size: 11px; color: var(--text-muted); text-transform: uppercase; letter-spacing: .04em; }}
.tile .value {{ font-size: 22px; font-weight: 600; margin-top: 2px; }}
.tile .value.running {{ color: var(--series-2); }}
.tile .value.complete {{ color: var(--series-3); }}
.chart-card {{ background: var(--surface-2); border: 1px solid var(--border); border-radius: 12px; padding: 16px 20px; margin-bottom: 20px; overflow-x: auto; }}
.chart-title {{ font-size: 13px; font-weight: 600; margin-bottom: 4px; }}
.legend {{ display: flex; gap: 16px; font-size: 12px; color: var(--text-secondary); margin-bottom: 8px; }}
.legend span {{ display: inline-flex; align-items: center; gap: 6px; }}
.swatch {{ width: 10px; height: 10px; border-radius: 2px; display: inline-block; }}
svg {{ display: block; overflow: visible; }}
.gridline {{ stroke: var(--border); stroke-width: 1; }}
.axislabel {{ fill: var(--text-muted); font-size: 10px; }}
.tooltip {{ position: absolute; background: var(--surface-1); border: 1px solid var(--border); border-radius: 8px; padding: 8px 10px; font-size: 12px; pointer-events: none; opacity: 0; transition: opacity .1s; box-shadow: 0 4px 12px rgba(0,0,0,.15); z-index: 10; }}
.crosshair {{ stroke: var(--text-muted); stroke-width: 1; stroke-dasharray: 3 3; opacity: 0; }}
footer {{ color: var(--text-muted); font-size: 11px; margin-top: 8px; }}
</style>
<div class="viz-root">
  <h1>MuseGene Evolution — Live Dashboard</h1>
  <div class="subtitle">FibRetracement + FourierProjection seeded run · pop=80 · gens=30 · cost=20bps · updated {now}</div>
  <div class="status-row" id="statusRow"></div>
  <div class="chart-card">
    <div class="chart-title">Fitness over generations</div>
    <div class="legend">
      <span><span class="swatch" style="background:var(--series-1)"></span>Best</span>
      <span><span class="swatch" style="background:var(--series-2)"></span>Mean (valid genomes)</span>
    </div>
    <div id="fitnessChart"></div>
  </div>
  <div class="chart-card">
    <div class="chart-title">Behavioral niches occupied (MAP-Elites, of 48)</div>
    <div class="legend"><span><span class="swatch" style="background:var(--series-3)"></span>Niches</span></div>
    <div id="nichesChart"></div>
  </div>
  <footer id="footerNote"></footer>
</div>
<script>
const DATA = {data_json};
const STATUS = {status_json};

function tile(label, value, cls) {{
  return `<div class="tile"><div class="label">${{label}}</div><div class="value ${{cls||''}}">${{value}}</div></div>`;
}}

const last = DATA.length ? DATA[DATA.length - 1] : null;
document.getElementById('statusRow').innerHTML = [
  tile('Status', STATUS, STATUS === 'complete' ? 'complete' : (STATUS === 'running' ? 'running' : '')),
  tile('Generation', last ? last.gen : '—'),
  tile('Best fitness', last ? last.best.toFixed(4) : '—'),
  tile('Niches (of 48)', last ? last.niches : '—'),
  tile('Champion', last ? last.champion : '—'),
].join('');

function lineChart(containerId, series, opts) {{
  const W = 760, H = 220, padL = 44, padR = 12, padT = 12, padB = 24;
  const el = document.getElementById(containerId);
  if (!DATA.length) {{ el.innerHTML = '<div style="color:var(--text-muted);font-size:13px;padding:20px 0;">No generations recorded yet.</div>'; return; }}
  const xs = DATA.map(d => d.gen);
  const allVals = series.flatMap(s => DATA.map(d => d[s.key]));
  let yMin = Math.min(...allVals), yMax = Math.max(...allVals);
  if (yMin === yMax) {{ yMin -= 1; yMax += 1; }}
  const pad = (yMax - yMin) * 0.08;
  yMin -= pad; yMax += pad;
  const xMin = Math.min(...xs), xMax = Math.max(...xs);
  const xScale = x => padL + (xMax === xMin ? 0 : (x - xMin) / (xMax - xMin)) * (W - padL - padR);
  const yScale = y => H - padB - ((y - yMin) / (yMax - yMin)) * (H - padT - padB);

  let svg = `<svg viewBox="0 0 ${{W}} ${{H}}" width="100%" style="max-width:${{W}}px">`;
  const gridN = 4;
  for (let i = 0; i <= gridN; i++) {{
    const y = padT + (i / gridN) * (H - padT - padB);
    const val = yMax - (i / gridN) * (yMax - yMin);
    svg += `<line class="gridline" x1="${{padL}}" y1="${{y}}" x2="${{W - padR}}" y2="${{y}}"/>`;
    svg += `<text class="axislabel" x="${{padL - 6}}" y="${{y + 3}}" text-anchor="end">${{val.toFixed(2)}}</text>`;
  }}
  const xTicks = Math.min(6, xs.length);
  for (let i = 0; i < xTicks; i++) {{
    const gi = Math.round(i * (xs.length - 1) / Math.max(1, xTicks - 1));
    const x = xScale(xs[gi]);
    svg += `<text class="axislabel" x="${{x}}" y="${{H - 6}}" text-anchor="middle">${{xs[gi]}}</text>`;
  }}
  for (const s of series) {{
    const pts = DATA.map(d => `${{xScale(d.gen)}},${{yScale(d[s.key])}}`).join(' ');
    svg += `<polyline points="${{pts}}" fill="none" stroke="${{s.color}}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`;
  }}
  svg += `<line class="crosshair" id="${{containerId}}_cross" x1="0" y1="${{padT}}" x2="0" y2="${{H - padB}}"/>`;
  svg += `</svg>`;
  el.innerHTML = svg;

  const svgEl = el.querySelector('svg');
  const cross = el.querySelector('#' + containerId + '_cross');
  let tip = document.querySelector('.tooltip[data-for="' + containerId + '"]');
  if (!tip) {{
    tip = document.createElement('div');
    tip.className = 'tooltip';
    tip.setAttribute('data-for', containerId);
    document.body.appendChild(tip);
  }}
  svgEl.addEventListener('mousemove', (e) => {{
    const rect = svgEl.getBoundingClientRect();
    const relX = (e.clientX - rect.left) / rect.width * W;
    let closest = 0, bestD = Infinity;
    DATA.forEach((d, i) => {{ const dx = Math.abs(xScale(d.gen) - relX); if (dx < bestD) {{ bestD = dx; closest = i; }} }});
    const d = DATA[closest];
    cross.setAttribute('x1', xScale(d.gen)); cross.setAttribute('x2', xScale(d.gen));
    cross.style.opacity = 1;
    tip.style.opacity = 1;
    tip.style.left = (e.clientX + 12) + 'px';
    tip.style.top = (e.clientY + 12) + 'px';
    tip.innerHTML = `<b>gen ${{d.gen}}</b><br>` + series.map(s => `${{s.label}}: ${{d[s.key].toFixed(4)}}`).join('<br>') + `<br>champion: ${{d.champion}}`;
  }});
  svgEl.addEventListener('mouseleave', () => {{ cross.style.opacity = 0; tip.style.opacity = 0; }});
}}

lineChart('fitnessChart', [
  {{ key: 'best', label: 'Best', color: 'var(--series-1)' }},
  {{ key: 'mean', label: 'Mean', color: 'var(--series-2)' }},
]);
lineChart('nichesChart', [
  {{ key: 'niches', label: 'Niches', color: 'var(--series-3)' }},
]);

document.getElementById('footerNote').textContent =
  DATA.length ? `${{DATA.length}} generations recorded so far.` : '';
</script>
"""

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write(html.format(now=now, data_json=data_json, status_json=json.dumps(status)))

print(f"wrote {OUT_PATH}: {len(rows)} generations, status={status}")
