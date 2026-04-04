# Scripts Interface Contracts

All scripts use project-local venv (`.venv/`) for Python isolation. Auto-resolve `${SCRIPT_DIR}/../.venv/bin/python3`, fallback to system `python3`.

## Exit Code Convention

All scripts follow the same exit code convention:
- `0` = success (valid JSON emitted to stdout)
- `1` = validation failure (bad args, missing files, invalid JSON/schema)
- `2` = script exception (unexpected runtime error)

## Hook Scripts

### audit-staging-path.sh

Enforces staging-only writes for chapter pipeline subagents.

- **Trigger**: SessionStart, SubagentStart/Stop, PreToolUse (Write/Edit/MultiEdit)
- **stdin**: Claude Code hook JSON (`hook_event_name`, `session_id`, `tool_name`, `tool_input.file_path`, `agent_type`, etc.)
- **stdout**: Hook response JSON with `permissionDecision: "allow" | "deny"` + optional `systemMessage`
- **Side effects**: Writes violation records to `logs/audit.jsonl`; manages marker files in `logs/.subagent-active.*.json`
- **Deps**: `jq`

### inject-context.sh

Injects project status into conversation at session start.

- **Trigger**: SessionStart
- **stdin**: Not used (reads `.checkpoint.json` from cwd)
- **stdout**: Plain text status block (checkpoint JSON + latest chapter summary)
- **Deps**: `python3` or `jq`

### check-sliding-window.sh

Two-phase sliding window checkpoint enforcement (PostToolUse trigger + PreToolUse gate).

- **Trigger**: PostToolUse (Write|Edit) + PreToolUse (Write|Edit|Bash)
- **stdin**: Claude Code hook JSON (`hook_event_name`, `tool_name`, `tool_input`)
- **stdout**:
  - **PostToolUse (trigger)**: `additionalContext` with sliding window instructions when checkpoint chapter ≥ 10 and % 5 == 0 is committed — fires AFTER checkpoint is written, all files already committed
  - **PreToolUse (gate)**: `permissionDecision: "deny"` for Write/Edit to `staging/**` or Bash mv/cp chapter when marker exists and report not written; silent exit once `logs/continuity/latest.json` is newer than marker
  - Silent exit for non-checkpoint chapters or already-checked chapters
- **Side effects**: Manages `logs/.sliding-window-pending` (marker), `logs/.sliding-window-last-checked` (dedup)
- **Deps**: `jq`

## Pipeline Scripts

### lint-meta-leak.sh

Deterministic meta-information leak detector.

- **Usage**: `lint-meta-leak.sh <chapter.md>`
- **stdout** (exit 0):
  ```json
  {
    "total_hits": 5,
    "errors": 3,
    "warnings": 2,
    "hits_per_kchars": 1.8,
    "chars": 2800,
    "hits": [
      {"category": "meta_code", "severity": "error", "description": "伏笔代号 (F-XXX)", "count": 1, "matches": [{"text": "F-007", "line": 15, "snippet": "..."}]}
    ]
  }
  ```
- **Categories**: meta_code (F/W/SL/OBJ/LS codes), tech_field (snake_case), json_block, file_path, markdown_artifact, layer_ref, agent_name, score_pattern, system_tag, volume_ref, chapter_ref, meta_narration
- **Severity**: `error` = never in prose (hard gate), `warning` = likely leak, needs context (卷号/章号/元叙述)
- **Deps**: `python3` (stdlib only)

### lint-blacklist.sh

Deterministic AI-blacklist linter.

- **Usage**: `lint-blacklist.sh <chapter.md> <ai-blacklist.json>`
- **stdout** (exit 0):
  ```json
  {
    "total_hits": 5,
    "hits_per_kchars": 1.8,
    "char_count": 2800,
    "hits": [
      {"word": "缓缓", "category": "adverb_abuse", "count": 2, "narration_only": false}
    ],
    "narration_only_stats": {
      "narration_connector_hits": 1,
      "narration_connector_per_kchars": 0.4
    },
    "em_dash_count": 0
  }
  ```
- **Deps**: `python3` (stdlib only)

### run-ner.sh

Chinese NER entity extractor (candidates + evidence snippets).

- **Usage**: `run-ner.sh <chapter.md>`
- **stdout** (exit 0): JSON conforming to `continuity-checks.md` NER schema:
  ```json
  {
    "schema_version": 1,
    "chapter_path": "chapters/chapter-048.md",
    "entities": {
      "characters": [{"text": "...", "slug_id": null, "confidence": "high", "mentions": [...]}],
      "locations": [...],
      "time_markers": [...]
    }
  }
  ```
- **Deps**: `python3` (stdlib only)

### query-foreshadow.sh

Returns relevant foreshadowing items for a target chapter.

- **Usage**: `query-foreshadow.sh <chapter_num>`
- **Prerequisite**: Must run from novel project root (cwd contains `.checkpoint.json`)
- **stdout** (exit 0):
  ```json
  {
    "items": [
      {
        "id": "F-001",
        "description": "...",
        "scope": "short",
        "status": "planted",
        "planted_chapter": 3,
        "target_resolve_range": [8, 15],
        "action": "advance"
      }
    ]
  }
  ```
- **Deps**: `python3` (stdlib only)

### extract-terminology.sh

Authority terminology extractor from L1/L2 specs.

- **Usage**: `extract-terminology.sh [project_dir]`
- **stdout**: Writes `world/terminology.json`
- **Sources**: `world/rules.json` (L1) + `characters/active/*.json` (L2)
- **Deps**: `python3` (stdlib only)

### lint-terminology.sh

Terminology drift detector for novel chapters.

- **Usage**: `lint-terminology.sh <chapter.md> [terminology.json]`
- **stdout** (exit 0): JSON report with variant detection, edit-distance checks, and intra-chapter consistency
- **Severity**: All hits are `warning` (no hard gate)
- **Deps**: `python3` (stdlib only)

## Eval Scripts

### calibrate-quality-judge.sh

Computes Pearson correlation between QualityJudge scores and human labels.

- **Usage**: `calibrate-quality-judge.sh <labels.jsonl> <evals_dir>`
- **stdout**: Calibration report JSON (correlation per dimension + overall)
- **Deps**: `python3` + `scripts/lib/calibrate_quality_judge.py`

### run-regression.sh

Runs regression test suite against labeled dataset.

- **Usage**: `run-regression.sh <config.json>`
- **stdout**: Regression results JSON
- **Deps**: `python3` + `scripts/lib/run_regression.py`

### compare-regression-runs.sh

Compares two regression run outputs for score drift.

- **Usage**: `compare-regression-runs.sh <run_a.json> <run_b.json>`
- **stdout**: Comparison report JSON (delta per dimension, regressions flagged)
- **Deps**: `python3` + `scripts/lib/compare_regression_runs.py`
