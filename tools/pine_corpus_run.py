#!/usr/bin/env python3
"""Batch-run pine2muse over the organic Pine corpus and triage failures.

Reads corpus/pine-reports/manifest.json (from pine_corpus_harvest.py), runs:
  node build/js/pine2muse.js --source F --audit --gate -o out.ms

Classifies each file as PARSE_FAIL | UNSUPPORTED | CLEAN_EMIT, optionally
smoke-runs CLEAN_EMIT (and best-effort UNSUPPORTED) via gene-runner, then
writes corpus/pine-reports/latest.json + SUMMARY.md.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORGANIC = ROOT / "corpus" / "pine-organic"
REPORTS = ROOT / "corpus" / "pine-reports"
MANIFEST = REPORTS / "manifest.json"
PINE2MUSE = ROOT / "build" / "js" / "pine2muse.js"
GENE_RUNNER = ROOT / "build" / "js" / "gene-runner.js"

UNMAPPED_RE = re.compile(r"unmapped builtin `([^`]+)`")
OTHER_PREFIX_RE = re.compile(r"^([^:(]+)")
VERSION_LINE_RE = re.compile(r"pine version: v(\d+)")
BULLET_RE = re.compile(r"^\s*•\s+(.+)$", re.MULTILINE)


def load_manifest(path: Path) -> dict:
    if not path.is_file():
        raise SystemExit(f"missing manifest: {path} (run tools/pine_corpus_harvest.py first)")
    return json.loads(path.read_text(encoding="utf-8"))


def iter_corpus_files(manifest: dict) -> list[dict]:
    rows: list[dict] = []
    for repo in manifest.get("repos", []):
        local = ORGANIC / repo["local_dir"]
        for f in repo.get("files", []):
            rows.append(
                {
                    "repo": repo["repo"],
                    "license": repo["license"],
                    "rel": f["path"],
                    "abs": local / f["path"],
                    "version_sniff": f.get("version"),
                }
            )
    return rows


def run_pine2muse(src: Path, out_ms: Path, timeout: float = 30.0) -> dict:
    if not PINE2MUSE.is_file():
        return {
            "class": "TOOL_MISSING",
            "exit": -1,
            "stdout": "",
            "stderr": f"missing {PINE2MUSE}; run: haxe pine2muse.hxml",
            "notes": [],
            "pine_version": None,
        }
    proc = subprocess.run(
        [
            "node",
            str(PINE2MUSE),
            "--source",
            str(src),
            "--audit",
            "--gate",
            "-o",
            str(out_ms),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        cwd=str(ROOT),
    )
    stderr = proc.stderr or ""
    notes = [m.group(1).strip() for m in BULLET_RE.finditer(stderr)]
    vm = VERSION_LINE_RE.search(stderr)
    pine_version = int(vm.group(1)) if vm else None

    if proc.returncode == 1 or "parse error:" in stderr:
        klass = "PARSE_FAIL"
    elif proc.returncode == 2:
        klass = "UNSUPPORTED"
    elif proc.returncode == 0:
        klass = "CLEAN_EMIT"
    else:
        klass = "TOOL_ERROR"

    return {
        "class": klass,
        "exit": proc.returncode,
        "stdout": (proc.stdout or "")[:2000],
        "stderr": stderr[:8000],
        "notes": notes,
        "pine_version": pine_version,
    }


def sense_making(ms_path: Path, timeout: float = 45.0) -> dict:
    """Compile+execute lowered MuseScript on synthetic tape via gene-runner."""
    if not GENE_RUNNER.is_file():
        return {"ok": False, "skipped": True, "error": f"missing {GENE_RUNNER}"}
    if not ms_path.is_file():
        return {"ok": False, "skipped": False, "error": "no .ms emitted"}
    try:
        proc = subprocess.run(
            ["node", str(GENE_RUNNER), "--source", str(ms_path)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            cwd=str(ROOT),
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "skipped": False, "error": "timeout"}
    raw = (proc.stdout or "").strip() or (proc.stderr or "").strip()
    try:
        data = json.loads(raw.splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        return {"ok": False, "skipped": False, "error": raw[:500] or f"exit={proc.returncode}"}
    ok = bool(data.get("ok"))
    return {
        "ok": ok,
        "skipped": False,
        "error": data.get("error") if not ok else None,
        "trades": data.get("trades"),
        "bars": data.get("bars"),
        "backend": data.get("backend"),
    }


def note_buckets(notes: list[str]) -> tuple[list[str], list[str]]:
    unknown: list[str] = []
    other: list[str] = []
    for n in notes:
        m = UNMAPPED_RE.search(n)
        if m:
            unknown.append(m.group(1))
            continue
        # Normalize "ta.atr → atr: ..." and similar to a stable prefix
        if "→" in n:
            other.append(n.split("→", 1)[0].strip() + " (approx)")
        elif "order id/args" in n:
            other.append("strategy order id/args dropped")
        elif "else-if" in n:
            other.append("else-if chain")
        elif "not yet lowered" in n:
            other.append(n.split("(")[0].strip())
        else:
            pm = OTHER_PREFIX_RE.match(n)
            other.append((pm.group(1).strip() if pm else n)[:80])
    return unknown, other


def write_summary(report: dict, path: Path) -> None:
    c = report["counts"]
    total = report["total_files"] or 1
    green = c.get("CLEAN_EMIT", 0)
    sense_ok = report.get("sense_making", {}).get("ok", 0)
    sense_tried = report.get("sense_making", {}).get("tried", 0)

    lines = [
        "# Pine corpus triage",
        "",
        f"Generated: `{report['generated_at']}`",
        "",
        "## Green rate",
        "",
        f"- Files: **{report['total_files']}** across **{report['repos']}** repos",
        f"- `CLEAN_EMIT` (parse-clean + zero unsupported): **{green}** "
        f"({100.0 * green / total:.1f}%)",
        f"- `UNSUPPORTED`: **{c.get('UNSUPPORTED', 0)}**",
        f"- `PARSE_FAIL`: **{c.get('PARSE_FAIL', 0)}**",
        f"- Sense-making smoke (gene-runner ok): **{sense_ok}/{sense_tried}**",
        "",
        "## Version histogram",
        "",
    ]
    for k, v in sorted(report.get("version_histogram", {}).items()):
        lines.append(f"- {k}: {v}")

    lines += ["", "## Top unknown builtins", ""]
    for name, n in report.get("top_unknown_builtins", [])[:15]:
        lines.append(f"- `{name}` × {n}")
    if not report.get("top_unknown_builtins"):
        lines.append("- (none)")

    lines += ["", "## Top unsupported / other notes", ""]
    for name, n in report.get("top_other_notes", [])[:15]:
        lines.append(f"- {name} × {n}")
    if not report.get("top_other_notes"):
        lines.append("- (none)")

    lines += ["", "## Top parse-error prefixes", ""]
    for name, n in report.get("top_parse_errors", [])[:15]:
        lines.append(f"- {name} × {n}")
    if not report.get("top_parse_errors"):
        lines.append("- (none)")

    lines += [
        "",
        "## SEO / GTM angles (non-retail)",
        "",
        "Retail Pine import is the wedge; these pull people who distrust TradingView folklore:",
        "",
        "1. **RepaintAudit as the product** — paste Pine; show where it was lying "
        "(lookahead / `request.security`). Before/after equity on the same tape.",
        "2. **Falsifiable parity pages** — publish this green-rate + `PineCorpusParity` "
        "bit-exact tables. Receipts over vibes.",
        "3. **DSP / signal-processing bridge** — FIR/IIR without `max_bars_back`; "
        "partner tone with rigorous indicator collections.",
        "4. **Portfolio / universe escape hatch** — single-symbol TV tester → Muse "
        "`runPanel` multi-name.",
        "5. **Evolve-after-import** — import → audit → NSGA-II/NMA walk-forward.",
        "6. **Adjacent DSLs** — ThinkScript / NinjaScript / EasyLanguage later; "
        "same honesty story.",
        "7. **Cross-domain rigor recruit** — chess/poker/robotics/CP: state machines + "
        "adversarial eval + never-silent approx (unsupported notes as a feature).",
        "8. **Open methodology, closed edge** — open transliterator + these reports; "
        "keep Murmuration / live edge private.",
        "",
        "Primary magnet: **public green corpus + honest gap list + one dramatic "
        "RepaintAudit demo**.",
        "",
        "## Next fix target",
        "",
    ]
    nxt = report.get("next_fix_target")
    if nxt:
        lines.append(f"**{nxt['bucket']}** (`{nxt['kind']}`) — {nxt['count']} hits. {nxt['hint']}")
    else:
        lines.append("Corpus is fully green under `--gate`, or no dominant bucket yet.")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def pick_next_fix(report: dict) -> dict | None:
    """Largest actionable failure bucket for the iterative fix loop.

    Prefer PARSE_FAIL when it dominates file counts — unknown-builtin notes only
    appear on files that already parsed, so a raw note-count can outrank the
    real corpus blocker.
    """
    counts = report.get("counts") or {}
    parse_files = int(counts.get("PARSE_FAIL", 0))
    parse = report.get("top_parse_errors") or []
    unknown = report.get("top_unknown_builtins") or []
    other = report.get("top_other_notes") or []

    if parse_files > 0 and parse:
        name, n = parse[0]
        return {
            "kind": "PARSE_FAIL",
            "bucket": name,
            "count": n,
            "files": parse_files,
            "hint": "Fix in PineParser.hx / PineLexer.hx.",
        }

    candidates: list[dict] = []
    if unknown:
        name, n = unknown[0]
        candidates.append(
            {
                "kind": "UnknownBuiltin",
                "bucket": name,
                "count": n,
                "hint": "Add to BuiltinMap.hx (often Metadata for color.*/chart noise).",
            }
        )
    if other:
        name, n = other[0]
        candidates.append(
            {
                "kind": "UnsupportedOther",
                "bucket": name,
                "count": n,
                "hint": "Lower or honestly map in PineLower.hx / BuiltinMap.hx.",
            }
        )
    if not candidates:
        return None
    return max(candidates, key=lambda c: c["count"])


def run_batch(
    limit: int | None,
    sense_unsupported: bool,
    timeout: float,
) -> dict:
    manifest = load_manifest(MANIFEST)
    rows = iter_corpus_files(manifest)
    if limit is not None:
        rows = rows[:limit]

    REPORTS.mkdir(parents=True, exist_ok=True)
    out_dir = Path(tempfile.mkdtemp(prefix="pine_corpus_ms_"))

    counts: Counter[str] = Counter()
    unknown_c: Counter[str] = Counter()
    other_c: Counter[str] = Counter()
    parse_c: Counter[str] = Counter()
    version_c: Counter[str] = Counter()
    sense_tried = sense_ok = 0
    results: list[dict] = []

    total = len(rows)
    print(f"Triage {total} pine files → {PINE2MUSE.name}")

    for i, row in enumerate(rows, 1):
        src = row["abs"]
        if not src.is_file():
            counts["MISSING_FILE"] += 1
            continue
        ms_out = out_dir / f"{i}.ms"
        try:
            r = run_pine2muse(src, ms_out, timeout=timeout)
        except subprocess.TimeoutExpired:
            r = {
                "class": "TIMEOUT",
                "exit": -1,
                "stdout": "",
                "stderr": "timeout",
                "notes": [],
                "pine_version": row.get("version_sniff"),
            }

        klass = r["class"]
        counts[klass] += 1
        ver = r.get("pine_version") or row.get("version_sniff")
        version_c[f"v{ver}" if ver is not None else "unknown"] += 1

        unk, oth = note_buckets(r.get("notes") or [])
        for u in unk:
            unknown_c[u] += 1
        for o in oth:
            other_c[o] += 1

        if klass == "PARSE_FAIL":
            for line in (r.get("stderr") or "").splitlines():
                if line.startswith("parse error:"):
                    msg = line.split("parse error:", 1)[1].strip()
                    # Drop line number for aggregation
                    msg = re.sub(r"\s*@ line \d+\s*$", "", msg)
                    parse_c[msg[:100]] += 1
                    break

        sense = None
        should_sense = klass == "CLEAN_EMIT" or (sense_unsupported and klass == "UNSUPPORTED")
        if should_sense and ms_out.is_file():
            sense_tried += 1
            sense = sense_making(ms_out, timeout=timeout)
            if sense.get("ok"):
                sense_ok += 1

        entry = {
            "repo": row["repo"],
            "file": row["rel"],
            "class": klass,
            "exit": r.get("exit"),
            "pine_version": ver,
            "notes": r.get("notes") or [],
            "sense": sense,
        }
        results.append(entry)

        if i % 25 == 0 or i == total:
            print(f"  [{i}/{total}] CLEAN={counts['CLEAN_EMIT']} UNSUP={counts['UNSUPPORTED']} PARSE={counts['PARSE_FAIL']}")

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_files": total,
        "repos": len({r["repo"] for r in rows}),
        "counts": dict(counts),
        "green_rate": (counts["CLEAN_EMIT"] / total) if total else 0.0,
        "version_histogram": dict(sorted(version_c.items())),
        "top_unknown_builtins": unknown_c.most_common(40),
        "top_other_notes": other_c.most_common(40),
        "top_parse_errors": parse_c.most_common(40),
        "sense_making": {"tried": sense_tried, "ok": sense_ok},
        "results": results,
    }
    report["next_fix_target"] = pick_next_fix(report)

    latest = REPORTS / "latest.json"
    latest.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_summary(report, REPORTS / "SUMMARY.md")
    print(f"\nWrote {latest}")
    print(f"Wrote {REPORTS / 'SUMMARY.md'}")
    print(
        f"GREEN {counts['CLEAN_EMIT']}/{total} "
        f"({100.0 * report['green_rate']:.1f}%) | "
        f"sense {sense_ok}/{sense_tried}"
    )
    if report["next_fix_target"]:
        nxt = report["next_fix_target"]
        print(f"Next fix: [{nxt['kind']}] {nxt['bucket']} × {nxt['count']}")
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description="Batch pine2muse triage over organic corpus")
    ap.add_argument("--limit", type=int, default=None, help="Max files (debug)")
    ap.add_argument(
        "--sense-unsupported",
        action="store_true",
        help="Also smoke-run gene-runner on UNSUPPORTED emits",
    )
    ap.add_argument("--timeout", type=float, default=30.0, help="Per-file timeout seconds")
    args = ap.parse_args()
    run_batch(args.limit, args.sense_unsupported, args.timeout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
