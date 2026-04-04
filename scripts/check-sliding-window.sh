#!/usr/bin/env bash
# Sliding window checkpoint enforcement (PostToolUse trigger + PreToolUse gate).
#
# PostToolUse (Write|Edit): Fires AFTER .checkpoint.json is updated to
#   "committed" at a checkpoint chapter (≥10 and %5==0). Creates marker
#   and injects instructions via additionalContext. Checkpoint is already
#   written — all chapter files are committed.
#
# PreToolUse (Write|Edit|Bash): If marker exists and report not written,
#   denies Write/Edit to staging/** and Bash mv/cp chapter commits.
#   Safety net if agent ignores PostToolUse instructions.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

hook_event="$(echo "$input" | jq -r '.hook_event_name // ""')"
tool_name="$(echo "$input" | jq -r '.tool_name // ""')"

cwd="$(echo "$input" | jq -r '.cwd // ""')"
project_dir="${cwd:-$(pwd)}"

checkpoint="$project_dir/.checkpoint.json"
[ -f "$checkpoint" ] || exit 0

marker="$project_dir/logs/.sliding-window-pending"
report="$project_dir/logs/continuity/latest.json"
last_checked="$project_dir/logs/.sliding-window-last-checked"

# ─── Helper: build instructions ───
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
7. 自动修复后复核修复结果，确认无遗漏
8. 向用户汇报校验结果摘要（问题数量、已修复/未修复、是否有阻断性问题）
MSG
}

# ─── Helper: check if chapter is a checkpoint ───
is_checkpoint() {
  local ch="$1"
  [ "$ch" -ge 10 ] 2>/dev/null || return 1
  [ $(( ch % 5 )) -eq 0 ] || return 1
  return 0
}

# ═══════════════════════════════════════════════════════════════
# PostToolUse: Trigger after checkpoint commit
# ═══════════════════════════════════════════════════════════════
if [ "$hook_event" = "PostToolUse" ]; then
  # Only care about Write/Edit to .checkpoint.json
  file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"
  case "$file_path" in
    */.checkpoint.json|*.checkpoint.json) ;;
    *) exit 0 ;;
  esac

  # Already have a pending check — don't re-trigger
  [ -f "$marker" ] && exit 0

  # Read from disk (PostToolUse = file already written)
  stage="$(jq -r '.pipeline_stage // ""' "$checkpoint" 2>/dev/null)" || true
  ch="$(jq -r '.last_completed_chapter // 0' "$checkpoint" 2>/dev/null)" || true

  [ "$stage" = "committed" ] || exit 0
  [ -n "$ch" ] || exit 0
  ch=$((10#$ch))
  is_checkpoint "$ch" || exit 0

  # Skip if already checked this chapter
  if [ -f "$last_checked" ]; then
    prev="$(cat "$last_checked" 2>/dev/null)" || true
    [ "$prev" = "$ch" ] && exit 0
  fi

  # Create marker and inject instructions
  mkdir -p "$project_dir/logs"
  ws=$(( ch - 9 ))
  [ "$ws" -ge 1 ] || ws=1
  instructions="$(build_instructions "$ch" "$ws")"
  printf '%s\n%s\n' "$ch" "$instructions" > "$marker"

  jq -n --arg ctx "⚠️ 【滑窗校验点】第 ${ch} 章提交完成，触发滑窗一致性校验。

${instructions}" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# PreToolUse: Gate — deny staging writes if marker exists
# ═══════════════════════════════════════════════════════════════
[ "$hook_event" = "PreToolUse" ] || exit 0

if [ -f "$marker" ]; then
  # Report written after marker → check complete, clear gate
  if [ -f "$report" ] && [ "$report" -nt "$marker" ]; then
    ch_done="$(head -1 "$marker" 2>/dev/null)" || true
    [ -n "$ch_done" ] && echo "$ch_done" > "$last_checked"
    rm -f "$marker"
    exit 0
  fi

  # ── Deny helper ──
  deny_sliding_window() {
    local instructions
    instructions="$(sed '1d' "$marker" 2>/dev/null || echo "请执行滑窗校验，完成后重试。")"
    jq -n \
      --arg msg "⛔ 滑窗校验未完成，操作被阻断。

${instructions}

完成校验并写入 logs/continuity/latest.json 后重试。" \
      --arg reason "sliding window check pending" \
      '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  }

  case "$tool_name" in
    Bash)
      cmd="$(echo "$input" | jq -r '.tool_input.command // ""')"
      echo "$cmd" | grep -qE '(mv|cp)\b.*staging/chapters/chapter-[0-9]{3}\.md' \
        && { deny_sliding_window; exit 0; }
      ;;
    Write|Edit)
      file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"
      case "$file_path" in
        */staging/*) deny_sliding_window; exit 0 ;;
      esac
      ;;
  esac
fi

exit 0
