#!/usr/bin/env bash
#
# run-codex-calibration.sh — Batch Codex evaluation + calibration
#
# Usage:
#   run-codex-calibration.sh --project <novel_project_dir> --labels <labels.jsonl> [--out <report.json>] [--chapters 1,2,3]
#
# Runs codex-eval.py + codeagent-wrapper for QJ+CC on each chapter,
# then computes Pearson r against human labels.
#
# Prerequisites:
#   - codeagent-wrapper installed and available in PATH
#   - Project has chapters/ with chapter-{C:03d}.md files
#   - Project has existing manifests or checkpoint for context assembly
#
# Exit codes:
#   0 = success
#   1 = validation failure
#   2 = runtime error

set -euo pipefail

CODEX_TIMEOUT="${CODEX_TIMEOUT:-3600}"  # seconds (timeout command uses seconds)

usage() {
  cat >&2 <<'EOF'
Usage:
  run-codex-calibration.sh --project <novel_project_dir> --labels <labels.jsonl> [--out <report.json>] [--chapters 1,2,3]

Options:
  --project <dir>      Novel project directory (must contain chapters/)
  --labels <file>      JSONL labels file (eval/datasets/**/labels-YYYY-MM-DD.jsonl)
  --out <file>         Optional: write report JSON to file (directories created)
  --chapters <list>    Optional: comma-separated chapter numbers (default: from labels)
  -h, --help           Show help
EOF
}

project_dir=""
labels_path=""
out_path=""
chapters_arg=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)
      [ "$#" -ge 2 ] || { echo "run-codex-calibration.sh: error: --project requires a value" >&2; exit 1; }
      project_dir="$2"
      shift 2
      ;;
    --labels)
      [ "$#" -ge 2 ] || { echo "run-codex-calibration.sh: error: --labels requires a value" >&2; exit 1; }
      labels_path="$2"
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || { echo "run-codex-calibration.sh: error: --out requires a value" >&2; exit 1; }
      out_path="$2"
      shift 2
      ;;
    --chapters)
      [ "$#" -ge 2 ] || { echo "run-codex-calibration.sh: error: --chapters requires a value" >&2; exit 1; }
      chapters_arg="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "run-codex-calibration.sh: unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$project_dir" ] || [ -z "$labels_path" ]; then
  echo "run-codex-calibration.sh: --project and --labels are required" >&2
  usage
  exit 1
fi

if [ ! -d "$project_dir" ]; then
  echo "run-codex-calibration.sh: project dir not found: $project_dir" >&2
  exit 1
fi

if [ ! -f "$labels_path" ]; then
  echo "run-codex-calibration.sh: labels file not found: $labels_path" >&2
  exit 1
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

_VENV_PY="${PLUGIN_ROOT}/.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "run-codex-calibration.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 1
fi

if ! command -v codeagent-wrapper >/dev/null 2>&1; then
  echo "run-codex-calibration.sh: codeagent-wrapper not found in PATH" >&2
  exit 1
fi

# --- Determine chapter list ---

if [ -n "$chapters_arg" ]; then
  # Parse comma-separated list
  IFS=',' read -ra chapters <<< "$chapters_arg"
else
  # Extract chapter numbers from labels JSONL (no mapfile — macOS Bash 3.2 compat)
  chapters=()
  while IFS= read -r ch; do
    chapters+=("$ch")
  done < <(
    "$PYTHON" -c "
import json, sys
seen = set()
for line in open(sys.argv[1], 'r', encoding='utf-8'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    obj = json.loads(line)
    ch = obj.get('chapter')
    if isinstance(ch, int) and ch not in seen:
        seen.add(ch)
        print(ch)
" "$labels_path"
  )
fi

if [ ${#chapters[@]} -eq 0 ]; then
  echo "run-codex-calibration.sh: no chapters found" >&2
  exit 1
fi

echo "run-codex-calibration.sh: processing ${#chapters[@]} chapters: ${chapters[*]}"

# --- Per-chapter evaluation loop ---

failed_chapters=()
processed=0
skipped=0

for ch_raw in "${chapters[@]}"; do
  ch=$(printf "%d" "$ch_raw" 2>/dev/null) || { echo "  [WARN] invalid chapter number: $ch_raw" >&2; continue; }
  ch_pad=$(printf "%03d" "$ch")

  echo "--- chapter $ch ---"

  # (a) Check for existing raw eval (idempotent skip)
  qj_raw="$project_dir/staging/evaluations/chapter-${ch_pad}-eval-raw.json"
  cc_raw="$project_dir/staging/evaluations/chapter-${ch_pad}-content-eval-raw.json"
  if [ -f "$qj_raw" ] && [ -f "$cc_raw" ]; then
    echo "  [SKIP] raw evals already exist"
    skipped=$((skipped + 1))
    continue
  fi

  # (b) Check manifest exists
  manifest="$project_dir/staging/manifests/chapter-${ch_pad}-manifest.json"
  if [ ! -f "$manifest" ]; then
    echo "  [WARN] manifest not found: $manifest" >&2
    failed_chapters+=("$ch")
    continue
  fi

  # (c-d) Assemble task content for QJ and CC
  echo "  assembling QJ task content..."
  if ! "$PYTHON" "$PLUGIN_ROOT/scripts/codex-eval.py" "$manifest" --agent quality-judge --project "$project_dir"; then
    echo "  [WARN] QJ assembly failed for chapter $ch" >&2
    failed_chapters+=("$ch")
    continue
  fi

  echo "  assembling CC task content..."
  if ! "$PYTHON" "$PLUGIN_ROOT/scripts/codex-eval.py" "$manifest" --agent content-critic --project "$project_dir"; then
    echo "  [WARN] CC assembly failed for chapter $ch" >&2
    failed_chapters+=("$ch")
    continue
  fi

  # (e-f) Run Codex QJ + CC in parallel (background + wait)
  qj_prompt="$project_dir/staging/prompts/chapter-${ch_pad}-quality-judge.md"
  cc_prompt="$project_dir/staging/prompts/chapter-${ch_pad}-content-critic.md"
  qj_ok=true
  cc_ok=true

  if [ ! -f "$qj_raw" ]; then
    echo "  running Codex QJ (background)..."
    timeout "$CODEX_TIMEOUT" codeagent-wrapper --backend codex - "$project_dir" < "$qj_prompt" &
    qj_pid=$!
  else
    qj_pid=""
  fi

  if [ ! -f "$cc_raw" ]; then
    echo "  running Codex CC (background)..."
    timeout "$CODEX_TIMEOUT" codeagent-wrapper --backend codex - "$project_dir" < "$cc_prompt" &
    cc_pid=$!
  else
    cc_pid=""
  fi

  # Wait for both
  if [ -n "${qj_pid:-}" ]; then
    if ! wait "$qj_pid"; then
      echo "  [WARN] Codex QJ failed for chapter $ch" >&2
      qj_ok=false
    fi
  fi
  if [ -n "${cc_pid:-}" ]; then
    if ! wait "$cc_pid"; then
      echo "  [WARN] Codex CC failed for chapter $ch" >&2
      cc_ok=false
    fi
  fi

  if [ "$qj_ok" = false ] || [ "$cc_ok" = false ]; then
    failed_chapters+=("$ch")
    continue
  fi

  # (g) Validate QJ output
  echo "  validating QJ output..."
  if ! "$PYTHON" "$PLUGIN_ROOT/scripts/codex-eval.py" --validate --schema quality-judge --project "$project_dir" --chapter "$ch"; then
    echo "  [WARN] QJ validation failed for chapter $ch" >&2
    failed_chapters+=("$ch")
    continue
  fi

  # (h) Validate CC output
  echo "  validating CC output..."
  if ! "$PYTHON" "$PLUGIN_ROOT/scripts/codex-eval.py" --validate --schema content-critic --project "$project_dir" --chapter "$ch"; then
    echo "  [WARN] CC validation failed for chapter $ch" >&2
    failed_chapters+=("$ch")
    continue
  fi

  processed=$((processed + 1))
  echo "  [OK] chapter $ch done"
done

echo ""
echo "=== Batch summary ==="
echo "  processed: $processed"
echo "  skipped (already done): $skipped"
echo "  failed: ${#failed_chapters[@]}"
if [ ${#failed_chapters[@]} -gt 0 ]; then
  echo "  failed chapters: ${failed_chapters[*]}"
fi

# --- Run calibration analysis ---

echo ""
echo "=== Running calibration analysis ==="

"$PYTHON" "$PLUGIN_ROOT/scripts/lib/calibrate_codex.py" "$project_dir" "$labels_path" "$out_path"

echo ""
echo "run-codex-calibration.sh: done"
