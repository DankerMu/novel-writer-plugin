#!/usr/bin/env bash
# PreToolUse hook: detect sliding window checkpoint and inject validation instruction.
#
# Fires when the orchestrator commits a chapter to chapters/chapter-NNN.md.
# If the chapter number hits a sliding window checkpoint (≥10 and %5==0),
# injects a systemMessage forcing the orchestrator to execute the consistency
# check (SKILL.md Step 8) by spawning an agent to read original chapter text.
# Does NOT block the write — permissionDecision is always "allow".

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

hook_event="$(echo "$input" | jq -r '.hook_event_name // ""')"
tool_name="$(echo "$input" | jq -r '.tool_name // ""')"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // ""')"

[ "$hook_event" = "PreToolUse" ] || exit 0
[ "$tool_name" = "Write" ] || exit 0

# Only match chapters/chapter-NNN.md (NOT staging/chapters/)
case "$file_path" in
  */staging/*) exit 0 ;;
esac

chapter_num=""
case "$file_path" in
  */chapters/chapter-[0-9][0-9][0-9].md)
    bn="${file_path##*/}"
    chapter_num="${bn#chapter-}"
    chapter_num="${chapter_num%.md}"
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

完成本章 commit 流程后，必须在写下一章之前执行以下操作：

1. 读取窗口内所有章节原文：${files}，以及对应的大纲区块（outline.md）和章节契约（chapter-contracts/）
2. 正文↔契约/大纲对齐检查（逐章）：核心事件是否完整呈现、冲突与抉择是否落地、局势变化是否一致、验收标准是否满足、POV/Location/伏笔动作是否匹配
3. 跨章连续性检查：角色位置/状态连续性、时间线矛盾、世界规则合规、伏笔推进一致性、跨线信息泄漏
4. 报告落盘到 logs/continuity/
5. 对可修复问题（事实性矛盾、连续性断裂、正文偏离契约/大纲）直接编辑章节原文修复
6. 不可自动修复的问题列出并提示用户
7. 修复完成后方可继续下一章"

jq -n --arg msg "$msg" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
