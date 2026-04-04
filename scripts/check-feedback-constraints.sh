#!/usr/bin/env bash
#
# QJ feedback loop — detects consecutive low-scoring dimensions and
# generates constraints for the next chapter.
#
# Usage:
#   check-feedback-constraints.sh [project_dir]
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files, invalid JSON)
#   2 = script exception (unexpected runtime error)
#
# Side effects:
#   Writes volumes/vol-{V:02d}/feedback-constraints.json

set -euo pipefail

project_dir="${1:-.}"
cd "$project_dir"

if [ ! -f ".checkpoint.json" ]; then
  echo "check-feedback-constraints.sh: .checkpoint.json not found in $project_dir" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "check-feedback-constraints.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - <<'PY'
import json
import os
import sys
from typing import Any, Dict, List, Optional

WINDOW_SIZE = 3
LOW_THRESHOLD = 3.5
CONSTRAINT_DURATION = 5  # expires after N chapters from creation

DIMENSIONS = [
    "plot_logic", "character", "immersion", "foreshadowing",
    "pacing", "style_naturalness", "emotional_impact", "storyline_coherence",
]

CONSTRAINT_TEMPLATES: Dict[str, str] = {
    "plot_logic": "下一章需确保情节推进有明确因果链，避免跳跃式推进",
    "character": "下一章需至少一处角色个性化行为/反应（非通用描述）",
    "immersion": "下一章需强化感官细节，至少两处具体的视/听/触觉描写",
    "foreshadowing": "下一章需推进或回应至少一条现有伏笔",
    "pacing": "下一章需包含至少一个明显的节奏转换点",
    "style_naturalness": "下一章需降低修饰词密度，增加动作化描写替代形容词",
    "emotional_impact": "下一章需设计至少一个情感冲击点（角色内心变化或关系转折）",
    "storyline_coherence": "下一章需明确回应前章悬念或推进故事线进度",
}


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
        _die(f"check-feedback-constraints.sh: invalid JSON at {path}: {e}", 1)


def main() -> None:
    checkpoint = _load_json(".checkpoint.json")
    if not isinstance(checkpoint, dict):
        _die("check-feedback-constraints.sh: .checkpoint.json must be a JSON object")

    volume = checkpoint.get("current_volume")
    if not isinstance(volume, int) or volume < 1:
        _die("check-feedback-constraints.sh: current_volume must be int >= 1")

    last_ch = checkpoint.get("last_completed_chapter")
    if not isinstance(last_ch, int) or last_ch < 1:
        _die("check-feedback-constraints.sh: last_completed_chapter must be int >= 1")

    # Collect evaluation files for current volume's recent chapters
    eval_dir = "evaluations"
    evals: List[Dict[str, Any]] = []

    if os.path.isdir(eval_dir):
        for fname in sorted(os.listdir(eval_dir)):
            if not fname.startswith("chapter-") or not fname.endswith("-eval.json"):
                continue
            # Extract chapter number
            try:
                ch_str = fname.replace("chapter-", "").replace("-eval.json", "")
                ch_num = int(ch_str)
            except ValueError:
                continue
            if ch_num > last_ch:
                continue
            data = _load_json(os.path.join(eval_dir, fname))
            if isinstance(data, dict):
                evals.append({"chapter": ch_num, "data": data})

    # Take the most recent N chapters
    evals.sort(key=lambda e: e["chapter"])
    recent = evals[-WINDOW_SIZE:]

    if not recent:
        # No evaluation data — output empty result
        result = {"new_constraints": [], "expired": [], "active": []}
        sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
        return

    # Calculate per-dimension averages over recent chapters
    dim_scores: Dict[str, List[float]] = {d: [] for d in DIMENSIONS}
    for entry in recent:
        scores = entry["data"].get("eval_used", {}).get("scores", {})
        for dim in DIMENSIONS:
            dim_data = scores.get(dim)
            if isinstance(dim_data, dict):
                score = dim_data.get("score")
                if isinstance(score, (int, float)):
                    dim_scores[dim].append(float(score))

    dim_averages: Dict[str, Optional[float]] = {}
    for dim in DIMENSIONS:
        vals = dim_scores[dim]
        if vals:
            dim_averages[dim] = round(sum(vals) / len(vals), 2)
        else:
            dim_averages[dim] = None

    # Load existing feedback-constraints.json
    vol_dir = f"volumes/vol-{volume:02d}"
    os.makedirs(vol_dir, exist_ok=True)
    fc_path = os.path.join(vol_dir, "feedback-constraints.json")
    existing = _load_json(fc_path)

    if not isinstance(existing, dict):
        existing = {
            "volume": volume,
            "last_checked_chapter": 0,
            "constraints": [],
        }

    constraints: List[Dict[str, Any]] = existing.get("constraints", [])

    # Expire old constraints
    expired: List[Dict[str, Any]] = []
    active: List[Dict[str, Any]] = []
    for c in constraints:
        exp = c.get("expires_after_chapter", 0)
        if isinstance(exp, int) and exp <= last_ch:
            expired.append(c)
        else:
            active.append(c)

    # Detect low-scoring dimensions and generate new constraints
    active_dims = {c["dimension"] for c in active if "dimension" in c}
    new_constraints: List[Dict[str, Any]] = []

    for dim in DIMENSIONS:
        avg = dim_averages[dim]
        if avg is None:
            continue
        if avg >= LOW_THRESHOLD:
            continue
        if dim in active_dims:
            # Already has an active constraint for this dimension
            continue

        # Build trigger description
        ch_range = [e["chapter"] for e in recent]
        trigger = f"ch-{min(ch_range):03d} ~ ch-{max(ch_range):03d} avg {avg}"

        constraint = {
            "dimension": dim,
            "trigger": trigger,
            "constraint": CONSTRAINT_TEMPLATES[dim],
            "created_at_chapter": last_ch,
            "expires_after_chapter": last_ch + CONSTRAINT_DURATION,
        }
        new_constraints.append(constraint)
        active.append(constraint)

    # Write back
    output_data = {
        "volume": volume,
        "last_checked_chapter": last_ch,
        "constraints": active,
    }
    with open(fc_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # stdout report
    result = {
        "new_constraints": new_constraints,
        "expired": expired,
        "active": active,
    }
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"check-feedback-constraints.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
