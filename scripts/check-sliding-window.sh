#!/usr/bin/env bash
# PreToolUse hook: sliding window checkpoint enforcement (two-phase).
#
# Phase 1 — TRIGGER (Write to .checkpoint.json):
#   When the orchestrator writes checkpoint with pipeline_stage="committed"
#   and last_completed_chapter hits a checkpoint (≥10 and %5==0), create a
#   marker and inject full sliding window instructions. Fires at the ideal
#   moment: commit just finished, next chapter hasn't started.
#
# Phase 2 — GATE (Bash mv chapter commit):
#   Safety net. If marker exists but report hasn't been written, DENY the
#   next chapter commit. Prevents the agent from skipping the check entirely.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

hook_event="$(echo "$input" | jq -r '.hook_event_name // ""')"
tool_name="$(echo "$input" | jq -r '.tool_name // ""')"

[ "$hook_event" = "PreToolUse" ] || exit 0

cwd="$(echo "$input" | jq -r '.cwd // ""')"
project_dir="${cwd:-$(pwd)}"

# Only act inside a novel project
[ -f "$project_dir/.checkpoint.json" ] || exit 0

marker="$project_dir/logs/.sliding-window-pending"
report="$project_dir/logs/continuity/latest.json"

# ─── Helper: build instructions for a given chapter/window ───
build_instructions() {
  local ch="$1" ws="$2" files=""
  for i in $(seq "$ws" "$ch"); do
    files="${files}chapters/chapter-$(printf '%03d' "$i").md, "
  done
  files="${files%, }"
  cat <<MSG
你必须立即执行滑窗一致性校验（窗口 ch${ws}–ch${ch}），不得跳过直接写下一章：

1. 读取窗口内所有章节原文（${files}）+ 对应大纲区块（outline.md 中各章段落）+ 对应章节契约（chapter-contracts/*.md）
2. 正文↔契约/大纲对齐检查（逐章）：「事件」是否完整呈现、「冲突与抉择」是否落地、「局势变化」章末状态是否一致、「验收标准」各条是否满足、大纲 Storyline/POV/Location 是否匹配、大纲 Foreshadowing 伏笔动作是否体现
3. 跨章连续性检查：角色位置/状态连续性、时间线矛盾、世界规则合规性、伏笔推进一致性、跨线信息泄漏
4. 可选辅助：NER 实体抽取（scripts/run-ner.sh，脚本优先，LLM fallback）
5. 报告落盘：logs/continuity/continuity-report-vol-*-ch$(printf '%03d' "$ws")-ch$(printf '%03d' "$ch").json + 覆盖 logs/continuity/latest.json
6. 自动修复：对可修复问题直接编辑章节原文；不可修复的列出并提示用户
7. 完成后继续写下一章
MSG
}

# ═══════════════════════════════════════════════════════════════
# Phase 1: TRIGGER — Write to .checkpoint.json with committed
# ═══════════════════════════════════════════════════════════════
if [ "$tool_name" = "Write" ]; then
  file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"

  # Only care about .checkpoint.json
  case "$file_path" in
    */.checkpoint.json|*.checkpoint.json) ;;
    *) exit 0 ;;
  esac

  # Parse the content being written
  content="$(echo "$input" | jq -r '.tool_input.content // ""')"
  stage="$(echo "$content" | jq -r '.pipeline_stage // ""' 2>/dev/null)" || true
  chapter_num="$(echo "$content" | jq -r '.last_completed_chapter // 0' 2>/dev/null)" || true

  [ "$stage" = "committed" ] || exit 0
  [ "$chapter_num" -ge 10 ] 2>/dev/null || exit 0
  [ $(( chapter_num % 5 )) -eq 0 ] || exit 0

  ws=$(( chapter_num - 9 ))
  [ "$ws" -ge 1 ] || ws=1

  # Create marker (line 1 = chapter, rest = instructions)
  mkdir -p "$project_dir/logs"
  instructions="$(build_instructions "$chapter_num" "$ws")"
  printf '%s\n%s\n' "$chapter_num" "$instructions" > "$marker"

  # Inject full instructions — this is the primary enforcement point
  jq -n --arg msg "⚠️ 【滑窗校验点】第 ${chapter_num} 章提交完成，触发滑窗一致性校验。

${instructions}" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# Phase 2: GATE — Bash mv chapter commit blocked if check pending
# ═══════════════════════════════════════════════════════════════
if [ "$tool_name" = "Bash" ]; then
  cmd="$(echo "$input" | jq -r '.tool_input.command // ""')"

  # Only match chapter commit: mv/cp staging/chapters/chapter-NNN.md
  if ! echo "$cmd" | grep -qE '(mv|cp)\b.*staging/chapters/chapter-[0-9]{3}\.md'; then
    exit 0
  fi

  # No marker → allow
  [ -f "$marker" ] || exit 0

  # Check if report was updated after marker
  if [ -f "$report" ] && [ "$report" -nt "$marker" ]; then
    rm -f "$marker"
    exit 0
  fi

  # DENY with full instructions from marker
  instructions="$(sed '1d' "$marker" 2>/dev/null || echo "请执行 SKILL.md Step 8 滑窗校验。")"
  jq -n \
    --arg msg "⛔ 章节 commit 被阻断——滑窗校验未完成。

${instructions}

完成后重新执行本次 commit。" \
    --arg reason "sliding window check pending" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi
