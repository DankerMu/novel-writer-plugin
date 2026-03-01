#!/usr/bin/env bash
# SessionStart hook: inject project status into context
# Only runs inside a novel project directory (detects .checkpoint.json).
#
# IMPORTANT: Any reference to plugin-internal files MUST use ${CLAUDE_PLUGIN_ROOT}
# because the plugin may be copied into a cache directory at runtime.

set -euo pipefail

# N2: We use a relative path here (not stdin-parsed cwd) because
# SessionStart hooks run with cwd set to the project directory by Claude Code.
# This is simpler than parsing stdin JSON and works for all standard scenarios.
# audit-staging-path.sh uses stdin-parsed cwd because it handles multiple
# hook events (SubagentStart/Stop/PreToolUse) where cwd verification matters.
CHECKPOINT=".checkpoint.json"

if [ ! -f "$CHECKPOINT" ]; then
  exit 0
fi

echo "=== 小说项目状态（自动注入） ==="
cat "$CHECKPOINT"

_VENV_PY="$(cd "$(dirname "$0")" && pwd)/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then _PY="$_VENV_PY"; else _PY="python3"; fi

LAST_CH="$(
  "$_PY" -c "import json; print(json.load(open('$CHECKPOINT', 'r', encoding='utf-8'))['last_completed_chapter'])" 2>/dev/null \
    || jq -r '.last_completed_chapter' "$CHECKPOINT" 2>/dev/null \
    || true
)"

if [ -n "${LAST_CH:-}" ] && [ "${LAST_CH:-0}" != "0" ]; then
  SUMMARY="summaries/chapter-$(printf '%03d' "$LAST_CH")-summary.md"
  if [ -f "$SUMMARY" ]; then
    echo "--- 最近章节摘要 (第 ${LAST_CH} 章) ---"
    head -c 2000 "$SUMMARY"
  fi
fi

echo "=== 状态注入完毕 ==="

