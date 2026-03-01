#!/usr/bin/env bash
#
# Regression runner for M2 outputs (M3).
#
# Usage:
#   run-regression.sh --project <novel_project_dir> [--labels <labels.jsonl>] [--runs-dir <dir>] [--no-archive]
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
# - Reads existing project outputs (evaluations/logs/etc) and summarizes regression-friendly metrics.
# - Archives outputs under eval/runs/<timestamp>/ by default (recommended to be gitignored).

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  run-regression.sh --project <novel_project_dir> [--labels <labels.jsonl>] [--runs-dir <dir>] [--no-archive]

Options:
  --project <dir>     Novel project directory (must contain evaluations/)
  --labels <file>     Optional: labeled dataset JSONL (for traceability; future metrics can use it)
  --runs-dir <dir>    Output base dir for archived runs (default: eval/runs)
  --no-archive        Do not write run artifacts; only print JSON to stdout
  --no-continuity     Skip reading logs/continuity/latest.json even if present
  --no-foreshadowing  Skip reading foreshadowing/global.json even if present
  --no-style          Skip reading style-drift.json even if present
  -h, --help          Show help
EOF
}

project_dir=""
labels_path=""
runs_dir="eval/runs"
archive=1
include_continuity=1
include_foreshadowing=1
include_style=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)
      [ "$#" -ge 2 ] || { echo "run-regression.sh: error: --project requires a value" >&2; exit 1; }
      project_dir="$2"
      shift 2
      ;;
    --labels)
      [ "$#" -ge 2 ] || { echo "run-regression.sh: error: --labels requires a value" >&2; exit 1; }
      labels_path="$2"
      shift 2
      ;;
    --runs-dir)
      [ "$#" -ge 2 ] || { echo "run-regression.sh: error: --runs-dir requires a value" >&2; exit 1; }
      runs_dir="$2"
      shift 2
      ;;
    --no-archive)
      archive=0
      shift 1
      ;;
    --no-continuity)
      include_continuity=0
      shift 1
      ;;
    --no-foreshadowing)
      include_foreshadowing=0
      shift 1
      ;;
    --no-style)
      include_style=0
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "run-regression.sh: unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$project_dir" ]; then
  echo "run-regression.sh: --project is required" >&2
  usage
  exit 1
fi

if [ ! -d "$project_dir" ]; then
  echo "run-regression.sh: project dir not found: $project_dir" >&2
  exit 1
fi

if [ -n "$labels_path" ] && [ ! -f "$labels_path" ]; then
  echo "run-regression.sh: labels file not found: $labels_path" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "run-regression.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 1
fi

"$PYTHON" "$SCRIPT_DIR/lib/run_regression.py" \
  "$project_dir" \
  "$labels_path" \
  "$runs_dir" \
  "$archive" \
  "$include_continuity" \
  "$include_foreshadowing" \
  "$include_style"

