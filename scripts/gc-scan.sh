#!/usr/bin/env bash
#
# Volume-level garbage collection scanner.
#
# Usage:
#   gc-scan.sh [project_dir] [volume_num]
#
# Output:
#   stdout JSON gc report (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files, invalid JSON)
#   2 = script exception (unexpected runtime error)
#
# Side effects:
#   Writes logs/gc/gc-report-vol-{V:02d}.json
#
# Categories:
#   1. Overdue foreshadowing (planted/advanced past target_resolve_range)
#   2. Stale character contracts (last_verified gap > 20 chapters)
#   3. Missing summaries (chapter exists but no summary)
#   4. Uncovered storylines (active storyline without recent POV coverage)

set -euo pipefail

project_dir="${1:-.}"
volume_override="${2:-}"
cd "$project_dir"

if [ ! -f ".checkpoint.json" ]; then
  echo "gc-scan.sh: .checkpoint.json not found in $project_dir" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "gc-scan.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$volume_override" <<'PY'
import datetime
import json
import os
import sys
from typing import Any, Dict, List, Optional

STALENESS_GAP = 20
STORYLINE_COVERAGE_WINDOW = 10


def _die(msg: str, code: int = 1) -> None:
    sys.stderr.write(msg.rstrip() + "\n")
    raise SystemExit(code)


def _load_json(path: str) -> Optional[Any]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except Exception as e:
        _die(f"gc-scan.sh: invalid JSON at {path}: {e}", 1)


def _scan_foreshadowing(last_ch: int) -> Dict[str, Any]:
    """Check for overdue foreshadowing items."""
    global_path = "foreshadowing/global.json"
    data = _load_json(global_path)

    if data is None:
        return {"status": "skipped", "reason": "file not found"}

    # Extract items list
    items: List[Dict[str, Any]]
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict) and isinstance(data.get("foreshadowing"), list):
        items = data["foreshadowing"]
    else:
        return {"status": "skipped", "reason": "unsupported schema"}

    overdue: List[Dict[str, Any]] = []
    for it in items:
        if not isinstance(it, dict):
            continue
        status = it.get("status", "")
        if status not in ("planted", "advanced"):
            continue
        tr = it.get("target_resolve_range")
        if not isinstance(tr, list) or len(tr) != 2:
            continue
        try:
            upper = int(tr[1])
        except (ValueError, TypeError):
            continue
        if upper < last_ch:
            overdue.append({
                "id": it.get("id", "unknown"),
                "status": status,
                "planted_chapter": it.get("planted_chapter"),
                "target_resolve_range": tr,
            })

    return {"overdue": overdue, "count": len(overdue)}


def _scan_character_staleness(last_ch: int) -> Dict[str, Any]:
    """Check for stale character contracts."""
    char_dir = "characters/active"
    if not os.path.isdir(char_dir):
        return {"status": "skipped", "reason": "directory not found"}

    # Build last-activity map from state/changelog.jsonl (most recent chapter per slug_id)
    changelog_path = "state/changelog.jsonl"
    last_activity: Dict[str, int] = {}
    if os.path.isfile(changelog_path):
        try:
            with open(changelog_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        ch = entry.get("chapter")
                        target = entry.get("target", "")
                        if isinstance(ch, int) and target:
                            slug = target.split("/")[-1].replace(".json", "")
                            last_activity[slug] = max(last_activity.get(slug, 0), ch)
                    except (json.JSONDecodeError, TypeError):
                        continue
        except OSError:
            pass

    stale: List[Dict[str, Any]] = []
    for fname in sorted(os.listdir(char_dir)):
        if not fname.endswith(".json"):
            continue
        path = os.path.join(char_dir, fname)
        data = _load_json(path)
        if not isinstance(data, dict):
            continue

        slug_id = fname.replace(".json", "")
        last_ch_for_char = last_activity.get(slug_id, 0)
        if last_ch_for_char == 0:
            # No changelog entry — skip (can't determine staleness)
            continue

        gap = last_ch - last_ch_for_char
        if gap > STALENESS_GAP:
            name = data.get("name", data.get("character_name", slug_id))
            stale.append({
                "slug_id": slug_id,
                "name": name,
                "last_changelog_chapter": last_ch_for_char,
                "gap": gap,
            })

    return {"stale": stale, "count": len(stale)}


def _scan_summary_coverage(last_ch: int) -> Dict[str, Any]:
    """Check for chapters missing summaries."""
    summary_dir = "summaries"
    chapter_dir = "chapters"

    if not os.path.isdir(summary_dir):
        return {"status": "skipped", "reason": "directory not found"}

    # Collect existing chapter numbers
    chapter_nums: List[int] = []
    if os.path.isdir(chapter_dir):
        for fname in os.listdir(chapter_dir):
            if fname.startswith("chapter-") and fname.endswith(".md"):
                try:
                    ch_str = fname.replace("chapter-", "").replace(".md", "")
                    chapter_nums.append(int(ch_str))
                except ValueError:
                    continue

    # Also consider chapters up to last_completed
    for ch in range(1, last_ch + 1):
        if ch not in chapter_nums:
            # Check if chapter file exists
            ch_path = os.path.join(chapter_dir, f"chapter-{ch:03d}.md")
            if os.path.isfile(ch_path):
                chapter_nums.append(ch)

    chapter_nums = sorted(set(chapter_nums))

    # Check which have summaries
    missing: List[int] = []
    for ch in chapter_nums:
        summary_path = os.path.join(summary_dir, f"chapter-{ch:03d}-summary.md")
        if not os.path.isfile(summary_path):
            missing.append(ch)

    return {"missing": missing, "count": len(missing)}


def _scan_storyline_coverage(last_ch: int) -> Dict[str, Any]:
    """Check active storylines for recent POV coverage."""
    sl_path = "storylines/storylines.json"
    data = _load_json(sl_path)

    if data is None:
        return {"status": "skipped", "reason": "file not found"}

    # Extract storylines
    storylines: List[Dict[str, Any]]
    if isinstance(data, list):
        storylines = data
    elif isinstance(data, dict) and isinstance(data.get("storylines"), list):
        storylines = data["storylines"]
    else:
        return {"status": "skipped", "reason": "unsupported schema"}

    # Filter active storylines
    active_sls: List[Dict[str, Any]] = []
    for sl in storylines:
        if not isinstance(sl, dict):
            continue
        status = sl.get("status", "active")
        if status in ("active", "in_progress"):
            active_sls.append(sl)

    if not active_sls:
        return {"uncovered": [], "count": 0}

    # Read summaries for the recent window to find storyline references
    summary_dir = "summaries"
    window_start = max(1, last_ch - STORYLINE_COVERAGE_WINDOW + 1)
    sl_last_pov: Dict[str, int] = {}

    if os.path.isdir(summary_dir):
        for ch in range(window_start, last_ch + 1):
            summary_path = os.path.join(summary_dir, f"chapter-{ch:03d}-summary.md")
            if not os.path.isfile(summary_path):
                continue
            try:
                with open(summary_path, "r", encoding="utf-8") as f:
                    content = f.read()
            except Exception:
                continue
            # Check for storyline_id mentions in summary
            for sl in active_sls:
                sl_id = sl.get("id", "")
                if sl_id and sl_id in content:
                    prev = sl_last_pov.get(sl_id, 0)
                    if ch > prev:
                        sl_last_pov[sl_id] = ch

    uncovered: List[Dict[str, Any]] = []
    for sl in active_sls:
        sl_id = sl.get("id", "")
        if not sl_id:
            continue
        last_pov = sl_last_pov.get(sl_id)
        if last_pov is None:
            # No coverage in window at all
            uncovered.append({
                "storyline_id": sl_id,
                "last_pov_chapter": None,
                "gap": STORYLINE_COVERAGE_WINDOW,
            })
        else:
            gap = last_ch - last_pov
            if gap >= STORYLINE_COVERAGE_WINDOW:
                uncovered.append({
                    "storyline_id": sl_id,
                    "last_pov_chapter": last_pov,
                    "gap": gap,
                })

    return {"uncovered": uncovered, "count": len(uncovered)}


def main() -> None:
    checkpoint = _load_json(".checkpoint.json")
    if not isinstance(checkpoint, dict):
        _die("gc-scan.sh: .checkpoint.json must be a JSON object")

    volume_override = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""

    if volume_override:
        try:
            volume = int(volume_override)
        except ValueError:
            _die(f"gc-scan.sh: volume_num must be an integer (got: {volume_override})")
    else:
        volume = checkpoint.get("current_volume")
        if not isinstance(volume, int) or volume < 1:
            _die("gc-scan.sh: current_volume must be int >= 1")

    last_ch = checkpoint.get("last_completed_chapter")
    if not isinstance(last_ch, int) or last_ch < 1:
        _die("gc-scan.sh: last_completed_chapter must be int >= 1")

    # Run all 4 scans
    foreshadowing = _scan_foreshadowing(last_ch)
    character = _scan_character_staleness(last_ch)
    summary = _scan_summary_coverage(last_ch)
    storyline = _scan_storyline_coverage(last_ch)

    # Severity classification
    action_required = foreshadowing.get("count", 0)
    warn = character.get("count", 0) + summary.get("count", 0)
    info = storyline.get("count", 0)
    total = action_required + warn + info

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    report = {
        "volume": volume,
        "scanned_at": now,
        "last_completed_chapter": last_ch,
        "foreshadowing": foreshadowing,
        "character_staleness": character,
        "summary_coverage": summary,
        "storyline_coverage": storyline,
        "total_issues": total,
        "severity_summary": {
            "action_required": action_required,
            "warn": warn,
            "info": info,
        },
    }

    # Write report to logs/gc/
    gc_dir = "logs/gc"
    os.makedirs(gc_dir, exist_ok=True)
    report_path = os.path.join(gc_dir, f"gc-report-vol-{volume:02d}.json")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
        f.write("\n")

    sys.stdout.write(json.dumps(report, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"gc-scan.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
