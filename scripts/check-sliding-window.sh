#!/usr/bin/env bash
# PreToolUse hook: sliding window checkpoint enforcement.
#
# TRIGGER: Fires immediately when .checkpoint.json is set to committed
#   at a chapter that is a multiple of 5. For Write/Edit to .checkpoint.json,
#   parses tool_input directly (immediate). For other tools, reads disk
#   (fires on next call after checkpoint update).
#
# GATE: If marker exists and report not written, denies Bash mv chapter
#   commits. Safety net if agent ignores the trigger message.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

hook_event="$(echo "$input" | jq -r '.hook_event_name // ""')"
tool_name="$(echo "$input" | jq -r '.tool_name // ""')"

[ "$hook_event" = "PreToolUse" ] || exit 0

cwd="$(echo "$input" | jq -r '.cwd // ""')"
project_dir="${cwd:-$(pwd)}"

checkpoint="$project_dir/.checkpoint.json"
[ -f "$checkpoint" ] || exit 0

marker="$project_dir/logs/.sliding-window-pending"
report="$project_dir/logs/continuity/latest.json"

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
7. 完成后继续写下一章
MSG
}

# ─── Helper: emit trigger ───
emit_trigger() {
  local ch="$1"
  local ws=$(( ch - 9 ))
  [ "$ws" -ge 1 ] || ws=1

  mkdir -p "$project_dir/logs"
  local instructions
  instructions="$(build_instructions "$ch" "$ws")"
  printf '%s\n%s\n' "$ch" "$instructions" > "$marker"

  jq -n --arg msg "⚠️ 【滑窗校验点】第 ${ch} 章提交完成，触发滑窗一致性校验。

${instructions}" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
}

# ─── Helper: check if chapter is a checkpoint ───
is_checkpoint() {
  local ch="$1"
  [ "$ch" -ge 10 ] 2>/dev/null || return 1
  [ $(( ch % 5 )) -eq 0 ] || return 1
  return 0
}

# ═══════════════════════════════════════════════════════════════
# CASE 1: Marker exists — GATE mode
# ═══════════════════════════════════════════════════════════════
if [ -f "$marker" ]; then
  [ "$tool_name" = "Bash" ] || exit 0

  cmd="$(echo "$input" | jq -r '.tool_input.command // ""')"
  if ! echo "$cmd" | grep -qE '(mv|cp)\b.*staging/chapters/chapter-[0-9]{3}\.md'; then
    exit 0
  fi

  if [ -f "$report" ] && [ "$report" -nt "$marker" ]; then
    rm -f "$marker"
    exit 0
  fi

  instructions="$(sed '1d' "$marker" 2>/dev/null || echo "请执行 SKILL.md Step 8 滑窗校验。")"
  jq -n \
    --arg msg "⛔ 章节 commit 被阻断——滑窗校验未完成。

${instructions}

完成后重新执行本次 commit。" \
    --arg reason "sliding window check pending" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# CASE 2: No marker — detect committed checkpoint
# ═══════════════════════════════════════════════════════════════

is_committed=false
chapter_num=""

# ── Try parsing tool_input directly (immediate trigger) ──
case "$tool_name" in
  Write)
    file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"
    case "$file_path" in
      */.checkpoint.json|*.checkpoint.json)
        content="$(echo "$input" | jq -r '.tool_input.content // ""')"
        stage="$(echo "$content" | jq -r '.pipeline_stage // ""' 2>/dev/null)" || true
        ch="$(echo "$content" | jq -r '.last_completed_chapter // 0' 2>/dev/null)" || true
        if [ "$stage" = "committed" ]; then
          is_committed=true
          chapter_num="$ch"
        fi
        ;;
    esac
    ;;
  Edit)
    file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"
    case "$file_path" in
      */.checkpoint.json|*.checkpoint.json)
        new_string="$(echo "$input" | jq -r '.tool_input.new_string // ""')"
        if echo "$new_string" | grep -q '"committed"'; then
          is_committed=true
          # Try chapter from new_string first
          ch="$(echo "$new_string" | grep -oE '"last_completed_chapter"[[:space:]]*:[[:space:]]*([0-9]+)' | grep -oE '[0-9]+' | head -1)" || true
          if [ -z "$ch" ]; then
            # Chapter was set in a previous edit, read from disk
            ch="$(jq -r '.last_completed_chapter // 0' "$checkpoint" 2>/dev/null)" || true
          fi
          chapter_num="$ch"
        fi
        ;;
    esac
    ;;
esac

# ── Fallback: read from disk (for Bash and other tools) ──
if [ "$is_committed" = false ]; then
  stage="$(jq -r '.pipeline_stage // ""' "$checkpoint" 2>/dev/null)" || true
  ch="$(jq -r '.last_completed_chapter // 0' "$checkpoint" 2>/dev/null)" || true
  if [ "$stage" = "committed" ]; then
    is_committed=true
    chapter_num="$ch"
  fi
fi

# ── Check and trigger ──
[ "$is_committed" = true ] || exit 0
[ -n "$chapter_num" ] || exit 0
chapter_num=$((10#$chapter_num))
is_checkpoint "$chapter_num" || exit 0

emit_trigger "$chapter_num"
