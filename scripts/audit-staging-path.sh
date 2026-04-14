#!/usr/bin/env bash
#
# Enforce staging-only writes for chapter pipeline subagents.
# - Track active subagent via SubagentStart/SubagentStop hooks
# - Deny Write/Edit/MultiEdit outside staging/** for selected agent types
# - Append violations to logs/audit.jsonl (JSONL, append-only)
#
# IMPORTANT: This script is invoked by Claude Code hooks and must be fast.
#
# === Limitation: session-level best-effort guard ===
# PreToolUse events do NOT carry agent_type/agent_id — only SubagentStart/
# SubagentStop provide those fields. We bridge the gap with a marker file
# keyed by session_id. Consequences:
#   1. When a chapter-pipeline subagent is active, ALL Write/Edit/MultiEdit
#      in the same session are subject to staging-only enforcement (including
#      the host agent or other concurrent subagents).
#   2. If multiple subagents run concurrently, the marker reflects only the
#      most recently started one (last-write-wins).
# This is acceptable because the entry Skill orchestrates subagents
# sequentially (ChapterWriter → StyleRefiner → QualityJudge/ContentCritic → Summarizer),
# so concurrent overlap is unlikely in practice. The guard is best-effort;
# the primary write boundary is the staging→commit transaction model in the
# entry Skill.

set -euo pipefail

# N1: jq is required for all JSON operations in this script.
# Unlike inject-context.sh (which has python3→jq fallback), this script
# cannot degrade gracefully — fail loudly so the operator knows auditing
# is disabled.
if ! command -v jq >/dev/null 2>&1; then
  echo "audit-staging-path.sh: jq is required but not found" >&2
  exit 2
fi

hook_tsv="$(
  jq -r '[
      (.hook_event_name // ""),
      (.session_id // ""),
      (.cwd // ""),
      (.permission_mode // ""),
      (.tool_name // ""),
      (.tool_use_id // ""),
      (.transcript_path // ""),
      (.tool_input.file_path // ""),
      (.agent_type // ""),
      (.agent_id // "")
    ] | join("\u001f")' 2>/dev/null || true
)"

if [ -z "${hook_tsv:-}" ]; then
  exit 0
fi

IFS=$'\x1f' read -r hook_event_name session_id cwd permission_mode tool_name tool_use_id transcript_path tool_file_path agent_type agent_id <<<"$hook_tsv"

project_dir="${cwd:-$(pwd)}"
checkpoint_path="${project_dir}/.checkpoint.json"

# Only enforce inside a novel project directory.
if [ ! -f "$checkpoint_path" ]; then
  exit 0
fi

logs_dir="${project_dir}/logs"
marker_file="${logs_dir}/.subagent-active.${session_id}.json"
audit_log="${logs_dir}/audit.jsonl"

case "$hook_event_name" in
  SessionStart)
    # H2: Clean up stale marker files from previous/crashed subagents.
    # This prevents --resume/--continue from inheriting outdated state.
    if [ -d "$logs_dir" ]; then
      rm -f "${logs_dir}"/.subagent-active.*.json 2>/dev/null || true
    fi
    exit 0
    ;;
  SubagentStart)
    mkdir -p "$logs_dir"
    jq -n \
      --arg session_id "$session_id" \
      --arg agent_type "$agent_type" \
      --arg agent_id "$agent_id" \
      --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{session_id:$session_id, agent_type:$agent_type, agent_id:$agent_id, started_at:$started_at}' >"$marker_file"
    exit 0
    ;;
  SubagentStop)
    rm -f "$marker_file" >/dev/null 2>&1 || true
    exit 0
    ;;
esac

# Tool enforcement is done via PreToolUse so we can actually block writes.
if [ "$hook_event_name" != "PreToolUse" ]; then
  exit 0
fi

case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

# Only enforce for selected chapter pipeline subagents.
if [ ! -f "$marker_file" ]; then
  exit 0
fi

active_agent_type="$(jq -r '.agent_type // ""' "$marker_file" 2>/dev/null || true)"
case "$active_agent_type" in
  chapter-writer|summarizer|quality-judge) ;;
  *) exit 0 ;;
esac

if [ -z "${tool_file_path:-}" ]; then
  exit 0
fi

# Normalize to a project-relative path when possible.
rel_path="$tool_file_path"
case "$tool_file_path" in
  "$project_dir"/*)
    rel_path="${tool_file_path#"$project_dir"/}"
    ;;
esac

# Strip leading "./" for relative paths.
while [ "${rel_path#./}" != "$rel_path" ]; do
  rel_path="${rel_path#./}"
done

# N3: Reject path traversal attempts (e.g. "staging/../chapters/file.md").
case "$rel_path" in
  *..*)
    reason="Path traversal detected in '${rel_path}' (agent: ${active_agent_type})"
    mkdir -p "$logs_dir"
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -n \
      --arg timestamp "$timestamp" \
      --arg tool_name "$tool_name" \
      --arg path "$rel_path" \
      --arg reason "$reason" \
      --arg session_id "$session_id" \
      --arg agent_type "$active_agent_type" \
      '{timestamp:$timestamp, tool_name:$tool_name, path:$path, allowed:false, reason:$reason, session_id:$session_id, agent_type:$agent_type}' >>"$audit_log"
    jq -n \
      --arg systemMessage "Blocked: path traversal in '${rel_path}'. See logs/audit.jsonl." \
      --arg reason "$reason" \
      '{systemMessage:$systemMessage, hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$reason}}'
    exit 0
    ;;
esac

allowed="false"
case "$rel_path" in
  staging/*) allowed="true" ;;
esac

if [ "$allowed" = "true" ]; then
  exit 0
fi

mkdir -p "$logs_dir"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
reason="Subagent '${active_agent_type}' writes must be under staging/** (got: ${rel_path})"

# Append audit event (JSONL).
jq -n \
  --arg timestamp "$timestamp" \
  --arg tool_name "$tool_name" \
  --arg path "$rel_path" \
  --arg reason "$reason" \
  --arg session_id "$session_id" \
  --arg agent_type "$active_agent_type" \
  '{timestamp:$timestamp, tool_name:$tool_name, path:$path, allowed:false, reason:$reason, session_id:$session_id, agent_type:$agent_type}' >>"$audit_log"

# Block the tool execution (deny only; do NOT set "continue: false" which
# would terminate the entire session instead of just rejecting this write).
jq -n \
  --arg systemMessage "Blocked write outside staging/** (agent: ${active_agent_type}). See logs/audit.jsonl for details." \
  --arg reason "$reason" \
  '{
    systemMessage: $systemMessage,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'

exit 0
