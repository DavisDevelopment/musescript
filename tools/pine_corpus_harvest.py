#!/usr/bin/env python3
"""Harvest license-clean organic Pine Script corpora from GitHub.

Parses awesome-list READMEs for github.com links, unions with known dense
MIT collections, SPDX-gates each repo, shallow-clones into corpus/pine-organic/,
and writes corpus/pine-reports/manifest.json.

Never fetches tradingview.com/script bodies (see musescript/pinescript/DESIGN.md).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORGANIC = ROOT / "corpus" / "pine-organic"
REPORTS = ROOT / "corpus" / "pine-reports"

DEFAULT_AWESOME_LISTS = [
    "https://raw.githubusercontent.com/pAulseperformance/awesome-pinescript/master/README.md",
    "https://raw.githubusercontent.com/just-nilux/awesome-tradingview/master/README.md",
]

# Dense collections known to contain actual .pine sources (primary mass).
DEFAULT_SEED_REPOS = [
    "everget/tradingview-pinescript-indicators",
    "mihakralj/pinescript",
    "pinecoders/pine-utils",
    "TWODS-CAPITAL/Trading-View-Indicators",
    "Alorse/pinescript-strategies",
    "800cherries/Tradingview-Indicators",
    "chris-c-thomas/chrd-tradingview-pine-scripts",
    "VolodymyrFilias/feels-indicators",
    "ArunKBhaskar/PineScript",
    "hirawatt/pineScripts",
]

ALLOWED_SPDX = {
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "MPL-2.0",
    "Unlicense",
    "CC0-1.0",
    "0BSD",
}

GITHUB_REPO_RE = re.compile(
    r"https?://(?:www\.)?github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)",
    re.IGNORECASE,
)
VERSION_RE = re.compile(r"//@version\s*=\s*(\d+)", re.IGNORECASE)
LICENSE_HEADER_RE = re.compile(
    r"(?:^|\n)\s*(?:SPDX-License-Identifier:\s*)?"
    r"(MIT|Apache(?:\s+License)?(?:\s+Version)?\s*2\.0|BSD[-\s]?[23](?:-Clause)?"
    r"|ISC|MPL(?:-\s*)?2\.0|Unlicense|CC0(?:-\s*)?1\.0|0BSD)",
    re.IGNORECASE,
)

SKIP_DIR_NAMES = {
    ".git",
    "node_modules",
    ".venv",
    "venv",
    "__pycache__",
    "dist",
    "build",
    "target",
}

PINE_EXTS = {".pine", ".pinescript"}
SNIFF_EXTS = {".txt", ".md", ".ms", ""}  # extensionless included


def fetch_text(url: str, timeout: float = 30.0) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "muse-pine-corpus-harvest/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def extract_repos_from_markdown(md: str) -> set[str]:
    found: set[str] = set()
    for m in GITHUB_REPO_RE.finditer(md):
        owner, repo = m.group(1), m.group(2)
        # Strip common trailing path junk if regex over-captured (it shouldn't).
        repo = repo.rstrip(").,;")
        if owner.lower() in {"topics", "settings", "orgs", "marketplace", "sponsors"}:
            continue
        if repo.lower() in {
            "awesome",
            "awesome-list",
            "pulls",
            "issues",
            "wiki",
            "actions",
            "releases",
            "security",
            "pulse",
            "projects",
        }:
            continue
        # Drop .git suffix
        if repo.endswith(".git"):
            repo = repo[:-4]
        found.add(f"{owner}/{repo}")
    return found


def normalize_repo(spec: str) -> str:
    spec = spec.strip().rstrip("/")
    m = GITHUB_REPO_RE.search(spec)
    if m:
        return f"{m.group(1)}/{m.group(2).removesuffix('.git')}"
    if "/" in spec and not spec.startswith("http"):
        parts = spec.split("/")
        return f"{parts[0]}/{parts[1]}"
    raise ValueError(f"not a github repo spec: {spec}")


def detect_license_from_files(repo_dir: Path) -> str | None:
    candidates = [
        repo_dir / "LICENSE",
        repo_dir / "LICENSE.md",
        repo_dir / "LICENSE.txt",
        repo_dir / "COPYING",
        repo_dir / "license",
        repo_dir / "License",
    ]
    for p in candidates:
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")[:8000]
        except OSError:
            continue
        # SPDX short form first
        spdx = re.search(r"SPDX-License-Identifier:\s*([A-Za-z0-9.+\-]+)", text)
        if spdx:
            return normalize_spdx(spdx.group(1))
        low = text.lower()
        if "mit license" in low or "permission is hereby granted, free of charge" in low:
            return "MIT"
        if "apache license" in low and "2.0" in low:
            return "Apache-2.0"
        if "bsd 3-clause" in low or "redistribution and use in source and binary forms" in low and "neither the name" in low:
            return "BSD-3-Clause"
        if "bsd 2-clause" in low:
            return "BSD-2-Clause"
        if "mozilla public license" in low and "2.0" in low:
            return "MPL-2.0"
        if "creative commons" in low and "cc0" in low:
            return "CC0-1.0"
        if "unlicense" in low:
            return "Unlicense"
        m = LICENSE_HEADER_RE.search(text)
        if m:
            return normalize_spdx(m.group(1))
    # package.json / pyproject sometimes declare license
    pkg = repo_dir / "package.json"
    if pkg.is_file():
        try:
            data = json.loads(pkg.read_text(encoding="utf-8", errors="replace"))
            lic = data.get("license")
            if isinstance(lic, str):
                return normalize_spdx(lic)
        except (OSError, json.JSONDecodeError):
            pass
    return None


def normalize_spdx(raw: str) -> str:
    s = raw.strip()
    aliases = {
        "Apache License 2.0": "Apache-2.0",
        "Apache License Version 2.0": "Apache-2.0",
        "Apache-2": "Apache-2.0",
        "Apache 2.0": "Apache-2.0",
        "BSD-2": "BSD-2-Clause",
        "BSD 2-Clause": "BSD-2-Clause",
        "BSD-3": "BSD-3-Clause",
        "BSD 3-Clause": "BSD-3-Clause",
        "MPL 2.0": "MPL-2.0",
        "MPL-2": "MPL-2.0",
        "CC0": "CC0-1.0",
        "CC0-1": "CC0-1.0",
    }
    if s in aliases:
        return aliases[s]
    # fuzzy
    low = s.lower().replace(" ", "")
    for k, v in {
        "mit": "MIT",
        "apache-2.0": "Apache-2.0",
        "apache2.0": "Apache-2.0",
        "bsd-2-clause": "BSD-2-Clause",
        "bsd-3-clause": "BSD-3-Clause",
        "isc": "ISC",
        "mpl-2.0": "MPL-2.0",
        "unlicense": "Unlicense",
        "cc0-1.0": "CC0-1.0",
        "0bsd": "0BSD",
    }.items():
        if low == k:
            return v
    return s


def clone_repo(owner_repo: str, dest: Path) -> tuple[bool, str]:
    if dest.exists() and (dest / ".git").exists():
        return True, "already_cloned"
    if dest.exists():
        shutil.rmtree(dest, ignore_errors=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/{owner_repo}.git"
    try:
        subprocess.run(
            ["git", "clone", "--depth", "1", "--quiet", url, str(dest)],
            check=True,
            capture_output=True,
            text=True,
            timeout=180,
        )
        return True, "cloned"
    except subprocess.CalledProcessError as e:
        err = (e.stderr or e.stdout or str(e)).strip()[:400]
        return False, f"clone_failed: {err}"
    except subprocess.TimeoutExpired:
        return False, "clone_timeout"


def sniff_version(text: str) -> int | None:
    m = VERSION_RE.search(text[:4000])
    return int(m.group(1)) if m else None


def looks_like_pine(path: Path, text: str) -> bool:
    if path.suffix.lower() in PINE_EXTS:
        return True
    head = "\n".join(text.splitlines()[:25])
    if VERSION_RE.search(head):
        return True
    # strategy/indicator/library declarations without version (rare legacy)
    if re.search(r"(?m)^\s*(strategy|indicator|study|library)\s*\(", head):
        return True
    return False


def find_pine_files(repo_dir: Path) -> list[dict]:
    files: list[dict] = []
    for dirpath, dirnames, filenames in os.walk(repo_dir):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_NAMES and not d.startswith(".")]
        for name in filenames:
            path = Path(dirpath) / name
            if path.suffix.lower() not in PINE_EXTS | SNIFF_EXTS and path.suffix != "":
                # also allow no-extension files
                if path.suffix:
                    continue
            # Skip huge blobs
            try:
                size = path.stat().st_size
            except OSError:
                continue
            if size > 2_000_000 or size == 0:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if not looks_like_pine(path, text):
                continue
            rel = path.relative_to(repo_dir).as_posix()
            files.append(
                {
                    "path": rel,
                    "bytes": size,
                    "version": sniff_version(text),
                }
            )
    files.sort(key=lambda f: f["path"])
    return files


def harvest(
    lists: list[str],
    seeds: list[str],
    max_repos: int | None,
    skip_clone: bool,
) -> dict:
    repos: set[str] = set()
    list_stats: list[dict] = []

    for url in lists:
        entry = {"url": url, "ok": False, "repos": 0, "error": None}
        try:
            md = fetch_text(url)
            found = extract_repos_from_markdown(md)
            entry["ok"] = True
            entry["repos"] = len(found)
            repos |= found
            print(f"  list OK  {url} -> {len(found)} github repos")
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            entry["error"] = str(e)
            print(f"  list FAIL {url}: {e}")
        list_stats.append(entry)

    for s in seeds:
        try:
            repos.add(normalize_repo(s))
        except ValueError as e:
            print(f"  seed skip: {e}")

    ordered = sorted(repos)
    if max_repos is not None:
        ordered = ordered[:max_repos]

    print(f"\nRepos to process: {len(ordered)}")
    ORGANIC.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)

    manifest_repos: list[dict] = []
    skipped: list[dict] = []

    for i, owner_repo in enumerate(ordered, 1):
        owner, name = owner_repo.split("/", 1)
        dest = ORGANIC / f"{owner}__{name}"
        print(f"[{i}/{len(ordered)}] {owner_repo}")

        if not skip_clone:
            ok, status = clone_repo(owner_repo, dest)
            if not ok:
                skipped.append({"repo": owner_repo, "reason": status})
                print(f"  SKIP {status}")
                continue
            print(f"  {status}")
        elif not dest.exists():
            skipped.append({"repo": owner_repo, "reason": "missing_local"})
            print("  SKIP missing_local")
            continue

        lic = detect_license_from_files(dest)
        if lic is None or lic not in ALLOWED_SPDX:
            reason = f"license_gate:{lic or 'unknown'}"
            skipped.append({"repo": owner_repo, "reason": reason, "path": str(dest)})
            print(f"  SKIP {reason}")
            # Leave clone on disk for inspection but exclude from manifest corpus.
            continue

        pine_files = find_pine_files(dest)
        print(f"  license={lic} pine_files={len(pine_files)}")
        if not pine_files:
            skipped.append({"repo": owner_repo, "reason": "no_pine_sources", "license": lic})
            continue

        manifest_repos.append(
            {
                "repo": owner_repo,
                "license": lic,
                "local_dir": f"{owner}__{name}",
                "file_count": len(pine_files),
                "files": pine_files,
            }
        )

    total_files = sum(r["file_count"] for r in manifest_repos)
    versions: dict[str, int] = {}
    for r in manifest_repos:
        for f in r["files"]:
            key = f"v{f['version']}" if f["version"] is not None else "unknown"
            versions[key] = versions.get(key, 0) + 1

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "awesome_lists": list_stats,
        "seed_repos": seeds,
        "allowed_spdx": sorted(ALLOWED_SPDX),
        "repos_considered": len(ordered),
        "repos_accepted": len(manifest_repos),
        "repos_skipped": skipped,
        "total_pine_files": total_files,
        "version_histogram": dict(sorted(versions.items())),
        "repos": manifest_repos,
    }

    out = REPORTS / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\nWrote {out}")
    print(f"Accepted {len(manifest_repos)} repos / {total_files} pine files")
    print(f"Skipped {len(skipped)} repos")
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description="Harvest license-clean Pine corpora from GitHub")
    ap.add_argument(
        "--lists",
        nargs="*",
        default=DEFAULT_AWESOME_LISTS,
        help="Awesome-list README raw URLs",
    )
    ap.add_argument(
        "--seed-repos",
        nargs="*",
        default=DEFAULT_SEED_REPOS,
        help="owner/repo seeds (dense collections)",
    )
    ap.add_argument("--max-repos", type=int, default=None, help="Cap repos processed (debug)")
    ap.add_argument(
        "--skip-clone",
        action="store_true",
        help="Only scan existing corpus/pine-organic clones",
    )
    ap.add_argument(
        "--seeds-only",
        action="store_true",
        help="Ignore awesome lists; only clone --seed-repos",
    )
    args = ap.parse_args()

    lists = [] if args.seeds_only else list(args.lists)
    print("Pine corpus harvest")
    print(f"  organic -> {ORGANIC}")
    print(f"  reports -> {REPORTS}")
    harvest(lists, list(args.seed_repos), args.max_repos, args.skip_clone)
    return 0


if __name__ == "__main__":
    sys.exit(main())
