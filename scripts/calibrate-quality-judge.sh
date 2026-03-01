#!/usr/bin/env bash
#
# QualityJudge calibration against human-labeled dataset (M3).
#
# Usage:
#   calibrate-quality-judge.sh --project <novel_project_dir> --labels <labels.jsonl> [--out <report.json>]
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files, invalid JSON)
#   2 = script exception (unexpected runtime error)
#
# Notes:
# - Aligns by chapter number.
# - Uses judge `overall_final` when available; falls back to `overall`.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  calibrate-quality-judge.sh --project <novel_project_dir> --labels <labels.jsonl> [--out <report.json>]

Options:
  --project <dir>   Novel project directory (must contain evaluations/)
  --labels <file>   JSONL labels file (eval/datasets/**/labels-YYYY-MM-DD.jsonl)
  --out <file>      Optional: write report JSON to file (directories created)
  -h, --help        Show help
EOF
}

project_dir=""
labels_path=""
out_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)
      [ "$#" -ge 2 ] || { echo "calibrate-quality-judge.sh: error: --project requires a value" >&2; exit 1; }
      project_dir="$2"
      shift 2
      ;;
    --labels)
      [ "$#" -ge 2 ] || { echo "calibrate-quality-judge.sh: error: --labels requires a value" >&2; exit 1; }
      labels_path="$2"
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || { echo "calibrate-quality-judge.sh: error: --out requires a value" >&2; exit 1; }
      out_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "calibrate-quality-judge.sh: unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$project_dir" ] || [ -z "$labels_path" ]; then
  echo "calibrate-quality-judge.sh: --project and --labels are required" >&2
  usage
  exit 1
fi

if [ ! -d "$project_dir" ]; then
  echo "calibrate-quality-judge.sh: project dir not found: $project_dir" >&2
  exit 1
fi

if [ ! -f "$labels_path" ]; then
  echo "calibrate-quality-judge.sh: labels file not found: $labels_path" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "calibrate-quality-judge.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 1
fi

"$PYTHON" "$SCRIPT_DIR/lib/calibrate_quality_judge.py" "$project_dir" "$labels_path" "$out_path"

