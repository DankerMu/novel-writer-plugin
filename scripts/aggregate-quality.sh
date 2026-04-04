#!/usr/bin/env bash
#
# Quality score aggregator — generates QUALITY.md from evaluation data.
#
# Usage:
#   aggregate-quality.sh [project_dir]
#
# Output:
#   Writes {project_dir}/QUALITY.md
#
# Exit codes:
#   0 = success (QUALITY.md written)
#   1 = validation failure (bad args, missing dir)
#   2 = script exception (unexpected runtime error)
#
# Scans evaluations/chapter-*-eval.json, aggregates 8-dimension scores,
# gate decisions, trends, and low-score alerts into a Markdown report.

set -euo pipefail

project_dir="${1:-.}"

if [ ! -d "$project_dir" ]; then
  echo "aggregate-quality.sh: directory not found: $project_dir" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "aggregate-quality.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$project_dir" <<'PY'
import glob
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

DIMENSIONS = [
    "plot_logic",
    "character",
    "immersion",
    "foreshadowing",
    "pacing",
    "style_naturalness",
    "emotional_impact",
    "storyline_coherence",
]

DEFAULT_CHAPTERS_PER_VOLUME = 30
LOW_SCORE_THRESHOLD = 3.5
CONSECUTIVE_LOW_MIN = 3


def load_checkpoint(project_dir: str) -> Optional[Dict[str, Any]]:
    path = os.path.join(project_dir, ".checkpoint.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        sys.stderr.write(f"WARNING: failed to read .checkpoint.json: {e}\n")
        return None


def parse_chapter_num(filename: str) -> Optional[int]:
    """Extract chapter number from filename like chapter-015-eval.json."""
    import re
    m = re.search(r"chapter-(\d{3})-eval\.json$", filename)
    if m:
        return int(m.group(1))
    return None


def chapter_to_volume(ch: int, chapters_per_vol: int = DEFAULT_CHAPTERS_PER_VOLUME) -> int:
    return (ch - 1) // chapters_per_vol + 1


def load_evals(project_dir: str) -> List[Dict[str, Any]]:
    pattern = os.path.join(project_dir, "evaluations", "chapter-*-eval.json")
    files = sorted(glob.glob(pattern))
    results = []
    for fp in files:
        ch_num = parse_chapter_num(os.path.basename(fp))
        if ch_num is None:
            sys.stderr.write(f"WARNING: cannot parse chapter number from {fp}, skipping\n")
            continue
        try:
            with open(fp, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            sys.stderr.write(f"WARNING: failed to parse {fp}: {e}, skipping\n")
            continue

        # Validate required fields
        eval_used = data.get("eval_used")
        metadata = data.get("metadata")
        if not eval_used or not metadata:
            sys.stderr.write(f"WARNING: missing eval_used/metadata in {fp}, skipping\n")
            continue

        scores = eval_used.get("scores", {})
        overall = eval_used.get("overall")
        gate = metadata.get("gate", {})

        if overall is None:
            sys.stderr.write(f"WARNING: missing eval_used.overall in {fp}, skipping\n")
            continue

        dim_scores = {}
        for dim in DIMENSIONS:
            entry = scores.get(dim)
            if entry and isinstance(entry, dict) and "score" in entry:
                dim_scores[dim] = entry["score"]

        results.append({
            "chapter": ch_num,
            "overall": overall,
            "dimensions": dim_scores,
            "gate_decision": gate.get("decision", "unknown"),
            "force_passed": gate.get("force_passed", False),
        })

    return results


def compute_trend(scores: List[float]) -> str:
    """Compare first half avg vs second half avg."""
    if len(scores) < 2:
        return "→"
    mid = len(scores) // 2
    first_half = scores[:mid]
    second_half = scores[mid:]
    avg_first = sum(first_half) / len(first_half)
    avg_second = sum(second_half) / len(second_half)
    diff = avg_second - avg_first
    if diff > 0.15:
        return "↑"
    elif diff < -0.15:
        return "↓"
    return "→"


def find_consecutive_low(chapters: List[Dict[str, Any]], dim: str) -> List[Tuple[int, int, float]]:
    """Find runs of >=CONSECUTIVE_LOW_MIN consecutive chapters where dim < threshold."""
    alerts = []
    run_chapters = []
    run_scores = []

    for entry in chapters:
        score = entry["dimensions"].get(dim)
        if score is not None and score < LOW_SCORE_THRESHOLD:
            run_chapters.append(entry["chapter"])
            run_scores.append(score)
        else:
            if len(run_scores) >= CONSECUTIVE_LOW_MIN:
                avg = sum(run_scores) / len(run_scores)
                alerts.append((run_chapters[0], run_chapters[-1], avg))
            run_chapters = []
            run_scores = []

    if len(run_scores) >= CONSECUTIVE_LOW_MIN:
        avg = sum(run_scores) / len(run_scores)
        alerts.append((run_chapters[0], run_chapters[-1], avg))

    return alerts


def format_chapter(ch: int) -> str:
    return f"ch-{ch:03d}"


def generate_report(project_dir: str) -> str:
    evals = load_evals(project_dir)
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    if not evals:
        return (
            "# 质量趋势报告\n\n"
            f"> 自动生成于 {timestamp}，由 `scripts/aggregate-quality.sh` 聚合\n\n"
            "暂无评分数据\n"
        )

    evals.sort(key=lambda e: e["chapter"])

    # --- Overall stats ---
    total = len(evals)
    avg_overall = sum(e["overall"] for e in evals) / total
    pass_count = sum(1 for e in evals if e["gate_decision"] == "pass" or e["force_passed"])
    force_passed_count = sum(1 for e in evals if e["force_passed"])
    pass_rate = pass_count / total

    # --- Group by volume ---
    checkpoint = load_checkpoint(project_dir)
    cpv = DEFAULT_CHAPTERS_PER_VOLUME
    # Could read from checkpoint if available

    volumes: Dict[int, List[Dict[str, Any]]] = {}
    for e in evals:
        vol = chapter_to_volume(e["chapter"], cpv)
        volumes.setdefault(vol, []).append(e)

    # --- Build report ---
    lines = []
    lines.append("# 质量趋势报告\n")
    lines.append(f"> 自动生成于 {timestamp}，由 `scripts/aggregate-quality.sh` 聚合\n")

    # Summary
    lines.append("## 总览\n")
    lines.append(f"- 总章数: {total}")
    lines.append(f"- 平均总分: {avg_overall:.2f}/5.0")
    lines.append(f"- 门控通过率: {pass_rate:.0%}（pass + force_passed）")
    lines.append(f"- Force passed: {force_passed_count} 章\n")

    # Collect all cleanup items
    cleanup_items = []

    for vol_num in sorted(volumes.keys()):
        vol_chapters = volumes[vol_num]
        vol_chapters.sort(key=lambda e: e["chapter"])
        ch_start = vol_chapters[0]["chapter"]
        ch_end = vol_chapters[-1]["chapter"]

        lines.append(f"## 卷 {vol_num} ({format_chapter(ch_start)}-{format_chapter(ch_end)})\n")

        # 8-dimension table
        lines.append("### 8 维评分均值\n")
        lines.append("| 维度 | 均值 | 趋势 | 最低章 |")
        lines.append("|------|------|------|--------|")

        for dim in DIMENSIONS:
            dim_scores = [(e["chapter"], e["dimensions"].get(dim)) for e in vol_chapters]
            valid = [(ch, s) for ch, s in dim_scores if s is not None]
            if not valid:
                lines.append(f"| {dim} | N/A | — | — |")
                continue
            scores_only = [s for _, s in valid]
            avg = sum(scores_only) / len(scores_only)
            trend = compute_trend(scores_only)
            min_ch, min_score = min(valid, key=lambda x: x[1])
            lines.append(
                f"| {dim} | {avg:.1f} | {trend} | {format_chapter(min_ch)} ({min_score:.1f}) |"
            )

        lines.append("")

        # Low-score alerts
        alerts_for_vol = []
        for dim in DIMENSIONS:
            runs = find_consecutive_low(vol_chapters, dim)
            for start_ch, end_ch, avg_score in runs:
                alerts_for_vol.append((dim, start_ch, end_ch, avg_score))

        if alerts_for_vol:
            lines.append("### 低分预警\n")
            lines.append("> 连续 ≥3 章某维度 < 3.5 时预警\n")
            for dim, start_ch, end_ch, avg_score in alerts_for_vol:
                lines.append(
                    f"- ⚠️ {dim}: {format_chapter(start_ch)} ~ {format_chapter(end_ch)} "
                    f"均值 {avg_score:.1f}（建议关注）"
                )
                cleanup_items.append(
                    f"- [ ] {dim} 连续低分（{format_chapter(start_ch)} ~ {format_chapter(end_ch)}）"
                )
            lines.append("")

        # Gate decision distribution
        lines.append("### Gate Decision 分布\n")
        lines.append("| 决策 | 次数 |")
        lines.append("|------|------|")

        decision_counts: Dict[str, int] = {}
        force_count_vol = 0
        for e in vol_chapters:
            d = e["gate_decision"]
            decision_counts[d] = decision_counts.get(d, 0) + 1
            if e["force_passed"]:
                force_count_vol += 1

        # Normalize gate decisions for display
        display_order = ["pass", "polish", "revise", "pause_for_user", "pause_for_user_force_rewrite"]
        for d in display_order:
            if d in decision_counts:
                lines.append(f"| {d} | {decision_counts[d]} |")
        # Any unexpected decisions
        for d in sorted(decision_counts.keys()):
            if d not in display_order:
                lines.append(f"| {d} | {decision_counts[d]} |")
        if force_count_vol > 0:
            lines.append(f"| force_passed | {force_count_vol} |")

        lines.append("")

        # Find lowest overall chapter in volume
        lowest = min(vol_chapters, key=lambda e: e["overall"])
        if lowest["overall"] < LOW_SCORE_THRESHOLD:
            cleanup_items.append(
                f"- [ ] {format_chapter(lowest['chapter'])} 总分 {lowest['overall']:.1f}（全卷最低）"
            )

    # Cleanup queue
    if cleanup_items:
        lines.append("## 清扫队列\n")
        for item in cleanup_items:
            lines.append(item)
        lines.append("")

    return "\n".join(lines)


def main() -> None:
    project_dir = sys.argv[1]

    if not os.path.isdir(project_dir):
        sys.stderr.write(f"aggregate-quality.sh: directory not found: {project_dir}\n")
        raise SystemExit(1)

    report = generate_report(project_dir)

    output_path = os.path.join(project_dir, "QUALITY.md")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(report)

    sys.stderr.write(f"aggregate-quality.sh: wrote {output_path}\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"aggregate-quality.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
