#!/usr/bin/env bash
# PreToolUse hook: detect sliding window checkpoint and inject validation instruction.
#
# Fires on Write (to chapters/chapter-NNN.md) or Bash (mv/cp to chapters/).
# If the chapter number hits a sliding window checkpoint (≥10 and %5==0),
# injects a systemMessage forcing the orchestrator to execute the consistency
# check (SKILL.md Step 8) by spawning an agent to read original chapter text.
# Does NOT block the tool — permissionDecision is always "allow".

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

hook_event="$(echo "$input" | jq -r '.hook_event_name // ""')"
tool_name="$(echo "$input" | jq -r '.tool_name // ""')"

[ "$hook_event" = "PreToolUse" ] || exit 0

chapter_num=""

case "$tool_name" in
  Write)
    file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"
    # Skip staging writes
    case "$file_path" in */staging/*) exit 0 ;; esac
    case "$file_path" in
      */chapters/chapter-[0-9][0-9][0-9].md)
        bn="${file_path##*/}"
        chapter_num="${bn#chapter-}"
        chapter_num="${chapter_num%.md}"
        chapter_num=$((10#$chapter_num))
        ;;
      *) exit 0 ;;
    esac
    ;;
  Bash)
    cmd="$(echo "$input" | jq -r '.tool_input.command // ""')"
    # Match: mv/cp from staging/chapters/ to chapters/ (commit pattern)
    # e.g. "mv staging/chapters/chapter-010.md chapters/chapter-010.md"
    if ! echo "$cmd" | grep -qE '(mv|cp)\b.*staging/chapters/chapter-[0-9]{3}\.md'; then
      exit 0
    fi
    # Extract chapter number from the destination (non-staging path)
    chapter_num="$(echo "$cmd" | grep -oE '[^/]chapters/chapter-([0-9]{3})\.md' | head -1 | grep -oE '[0-9]{3}')" || true
    [ -n "$chapter_num" ] || exit 0
    chapter_num=$((10#$chapter_num))
    ;;
  *) exit 0 ;;
esac

# Sliding window checkpoint: every 5 chapters, from chapter 10 onward
[ "$chapter_num" -ge 10 ] || exit 0
[ $(( chapter_num % 5 )) -eq 0 ] || exit 0

ws=$(( chapter_num - 9 ))
[ "$ws" -ge 1 ] || ws=1

# Build chapter file list
files=""
for i in $(seq "$ws" "$chapter_num"); do
  files="${files}chapters/chapter-$(printf '%03d' "$i").md, "
done
files="${files%, }"

msg="⚠️ 【滑窗校验点】第 ${chapter_num} 章已提交，触发滑窗一致性校验（窗口 ch${ws}–ch${chapter_num}）。

完成本章 commit 流程后，必须在写下一章之前执行以下操作（详见 SKILL.md Step 8）：

1. 读取窗口内所有章节原文（${files}）+ 对应大纲区块（outline.md 中各章 ### 段落）+ 对应章节契约（chapter-contracts/*.md）
2. 正文↔契约/大纲对齐检查（逐章）：「事件」是否完整呈现、「冲突与抉择」是否落地、「局势变化」章末状态是否一致、「验收标准」各条是否满足、大纲 Storyline/POV/Location 是否匹配、大纲 Foreshadowing 伏笔动作是否体现
3. 跨章连续性检查：角色位置/状态连续性、时间线矛盾、世界规则合规性、伏笔推进一致性、跨线信息泄漏
4. 可选辅助：NER 实体抽取（scripts/run-ner.sh，脚本优先，LLM fallback）
5. 报告落盘：logs/continuity/continuity-report-vol-*-ch${ws}-ch${chapter_num}.json + 覆盖 logs/continuity/latest.json
6. 自动修复：对可修复问题（事实性矛盾、连续性断裂、正文偏离契约/大纲）直接编辑受影响章节原文；不可自动修复的问题（剧情逻辑矛盾等）列出并提示用户
7. 阻断：修复完成后方可继续下一章"

jq -n --arg msg "$msg" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
