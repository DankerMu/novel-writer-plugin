#!/usr/bin/env bash
#
# auto-continue.sh — 自动续写循环（跨会话，每轮清 context）
#
# 每轮启动一个独立的 claude 会话执行 /novel:continue N，
# 完成后检查 .checkpoint.json 决定是否继续下一轮。
# 每轮都是全新 context，不会因累积膨胀导致质量下降。
#
# Usage:
#   ./auto-continue.sh                    # 默认每轮 5 章，最多 20 轮
#   ./auto-continue.sh 5 10              # 每轮 5 章，最多 10 轮
#   ./auto-continue.sh 3 -1              # 每轮 3 章，无限循环直到卷末
#
# Prerequisites:
#   - claude CLI 可用（claude-code / claude）
#   - 当前目录为小说项目根目录（含 .checkpoint.json）
#   - 项目状态为 WRITING 或 CHAPTER_REWRITE
#
# Notes:
#   - 滑窗校验由 hook 在会话内强制执行，无需外部干预
#   - Ctrl+C 可安全中断（当前章写完 commit 后才会 exit）
#   - 每轮日志追加到 logs/auto-continue.log

set -euo pipefail

BATCH_SIZE="${1:-5}"
MAX_ROUNDS="${2:-20}"

# --- Prerequisites ---

if [ ! -f ".checkpoint.json" ]; then
  echo "错误：当前目录不是小说项目（未找到 .checkpoint.json）" >&2
  exit 1
fi

CLAUDE_CMD=""
if command -v claude >/dev/null 2>&1; then
  CLAUDE_CMD="claude"
elif command -v claude-code >/dev/null 2>&1; then
  CLAUDE_CMD="claude-code"
else
  echo "错误：未找到 claude 或 claude-code CLI" >&2
  exit 1
fi

# jq is required for checkpoint parsing
if ! command -v jq >/dev/null 2>&1; then
  echo "错误：jq 未安装" >&2
  exit 1
fi

mkdir -p logs

# --- Helper ---

read_checkpoint() {
  jq -r "${1}" .checkpoint.json 2>/dev/null || echo ""
}

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> logs/auto-continue.log
}

# --- Pre-flight check ---

state="$(read_checkpoint '.orchestrator_state')"
if [ "$state" != "WRITING" ] && [ "$state" != "CHAPTER_REWRITE" ]; then
  echo "当前状态为 ${state}，需要 WRITING 或 CHAPTER_REWRITE。" >&2
  echo "请先执行 /novel:start 完成规划。" >&2
  exit 1
fi

last_ch="$(read_checkpoint '.last_completed_chapter')"
volume="$(read_checkpoint '.current_volume')"
log "=== 自动续写启动 === 卷${volume} 已完成${last_ch}章 | 每轮${BATCH_SIZE}章 | 最多${MAX_ROUNDS}轮"

# --- Main loop ---

round=0
while true; do
  round=$((round + 1))

  # Max rounds check (-1 = unlimited)
  if [ "$MAX_ROUNDS" -ge 0 ] && [ "$round" -gt "$MAX_ROUNDS" ]; then
    log "已达最大轮数 ${MAX_ROUNDS}，停止。"
    break
  fi

  last_ch="$(read_checkpoint '.last_completed_chapter')"
  log "--- 第 ${round} 轮开始 --- 从第 $((last_ch + 1)) 章续写 ${BATCH_SIZE} 章"

  # Run in fresh session (clean context)
  # --print: non-interactive mode
  # --dangerously-skip-permissions: auto-approve tool calls (unattended)
  # Adjust flags as needed for your claude CLI version
  if ! "$CLAUDE_CMD" -p "/novel:continue ${BATCH_SIZE}" \
    --print \
    --dangerously-skip-permissions \
    >> "logs/auto-continue-round-${round}.log" 2>&1; then
    log "⚠️ 第 ${round} 轮 claude 进程异常退出（exit $?）"
  fi

  # Read post-run checkpoint
  new_state="$(read_checkpoint '.orchestrator_state')"
  new_last="$(read_checkpoint '.last_completed_chapter')"
  new_stage="$(read_checkpoint '.pipeline_stage')"

  log "第 ${round} 轮结束: state=${new_state} last_ch=${new_last} stage=${new_stage}"

  # Decide next action
  case "$new_state" in
    WRITING|CHAPTER_REWRITE)
      # Check if any progress was made
      if [ "$new_last" = "$last_ch" ]; then
        log "⚠️ 本轮无进展（last_ch 未变），可能卡在修订或错误。停止。"
        break
      fi
      log "✓ 本轮完成 $((new_last - last_ch)) 章，继续下一轮。"
      ;;
    VOL_REVIEW)
      log "✓ 本卷写作完成（进入 VOL_REVIEW），停止续写。"
      log "请执行 /novel:start 进行卷末回顾和下卷规划。"
      break
      ;;
    ERROR_RETRY)
      log "⛔ 进入 ERROR_RETRY 状态，停止。请手动排查后执行 /novel:start。"
      break
      ;;
    *)
      log "⛔ 未知状态 ${new_state}，停止。"
      break
      ;;
  esac

  # Brief pause between rounds (let filesystem sync)
  sleep 2
done

final_ch="$(read_checkpoint '.last_completed_chapter')"
log "=== 自动续写结束 === 共 ${round} 轮，当前进度：第 ${final_ch} 章"
