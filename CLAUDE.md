# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code plugin for Chinese web novel (网文) multi-agent collaborative writing. 6 specialized agents orchestrated through a state-machine workflow with spec-driven quality gates and anti-AI output strategies.

## Commands



CI runs on push via `.github/workflows/docs-ci.yml` (markdownlint + lychee + manifest validation).

## Python Environment

All `scripts/*.sh` use a project-local venv (`.venv/`) for Python isolation. Setup:



Scripts auto-resolve `${SCRIPT_DIR}/../.venv/bin/python3`, falling back to system `python3` if venv is absent. Currently stdlib-only (no third-party deps).

## Architecture

### 4-Layer Spec Hierarchy (Spec-Driven Writing)

| Layer | File Pattern | Purpose | Mutability |
|-------|-------------|---------|------------|
| L1 World Rules | `world/rules.json` | Physics, magic, society hard constraints | Immutable |
| L2 Character Contracts | `characters/active/*.json` | Ability bounds, behavior patterns | Protocol-gated |
| L3 Chapter Contracts | `volumes/vol-{V:02d}/chapter-contracts/` | Pre/post conditions, acceptance criteria | Negotiable w/ audit |
| LS Storyline Specs | `storylines/storylines.json` | Multi-POV constraints, prevents cross-line leaks | Volume-scoped |

Agents validate outputs against these layers. QualityJudge performs dual-track verification: contract compliance (hard gate) + 9-dimension scoring (soft eval, including tonal_variance for register micro-injection density). ContentCritic evaluates reader engagement (Track 3) + content substance (Track 4: information density, plot progression, dialogue efficiency) + POV knowledge boundary & cross-storyline leak detection (Track 5: detects proper nouns/info leaking into narration that the POV character shouldn't know yet, and cross-storyline entity leaks in non-convergence chapters) + cross-chapter logic review (Track 6: reads recent 3 chapters full text to detect hard contradictions and plot holes; narrative techniques like time skips/POV switches are not flagged).

### State Machine



State persists in `.checkpoint.json` with fields: `orchestrator_state`, `current_volume`, `last_completed_chapter`, `pipeline_stage`, `inflight_chapter`, `eval_backend` ("codex" or "opus", default "codex" — `/novel:start` 初始化时自动写入).

### Single-Chapter Pipeline

`API Writer(draft, fallback CW) → StyleRefiner(de-AI polish) → [QualityJudge + ContentCritic parallel] → Gate Decision (merge) → Summarizer (pass/polish only)`

API Writer (`scripts/api-writer.py`) calls external model API (default: gemini-3.1-pro-preview) with pure creative system prompt (`prompts/api-writer-system.md`), bypassing Claude Code's engineering-focused system prompt. Falls back to ChapterWriter agent on API failure. CW agent remains available for revision/polish passes (targeted edits benefit from Claude Code's tool integration).

Gate thresholds: ≥4.0 pass, 3.5–3.9 polish, 3.0–3.4 revise, 2.0–2.9 review, <2.0 rewrite. ContentCritic Track 4 substance violation (any dimension < 3.0) forces revise. Track 6 logic_review severity=high forces revise. QJ tonal_variance < 3.0 forces revise.

**Revision loop optimization** (M9.2): revise triggers a tiered sub-pipeline based on `revision_scope`:
- `trivial` (≤1 failed_dimension, no failed_tracks, overall ≥ 3.5, excludes structural dims plot_logic/storyline_coherence/tonal_variance and golden-chapter engagement override): `CW(targeted) → SR(lite) → force_passed` (~15-20K tokens, skip QJ/CC recheck)
- `targeted` (no high_violation, no substance_severe, overall ≥ 3.0, not trivial): `CW(targeted) → SR(lite) → [QJ(recheck) ∥ CC(recheck)]` (~35-45K tokens)
- `full` (has high_violation or substance_severe or overall < 3.0): `CW → SR → [QJ+CC]` re-run (~90K tokens)

Targeted mode passes `failed_dimensions` to CW for scoped edits, uses `lite_mode`/`recheck_mode` flags for downstream agents. QJ/CC have no cross-dependency in recheck mode, enabling parallel dispatch after SR. Summarizer runs only after gate pass, not during revision loops. Trivial: 1 round, force_passed (no recheck needed). Targeted: 1 round, then direct-fix Task agent (SR only, no re-eval) + force_passed. Full: max 2 rounds, then force_passed or pause_for_user.

**Eval backend** (M10, v3.0.0): Summarizer/QJ/CC/sliding-window can run via Codex or Opus agents. New projects default to `eval_backend: "codex"` in checkpoint. Config is global per project, no runtime fallback between backends.

Codex path: `codex-eval.py --agent` (assemble task content from manifest) → `codeagent-wrapper --backend codex` (Codex execution) → `codex-eval.py --validate` (staging output validation). Codex prompts live in `prompts/codex-{agent}.md`, adapted from agent specs without YAML frontmatter or Claude Code tool refs. Writing pipeline (API Writer/CW/SR) is unaffected.

**codeagent-wrapper constraints**: Do not kill long-running processes (wastes API cost). Timeouts: Summarizer/QJ/CC 3600s, sliding-window 7200s (via `CODEX_TIMEOUT` env). SESSION_ID from wrapper logged for audit/resume.

Calibration: `scripts/run-codex-calibration.sh` runs batch Codex eval on M3 dataset. `scripts/lib/calibrate_codex.py` computes 4-way comparison (Codex QJ vs Human, CC vs Human, Codex vs Opus, Summarizer ops). Threshold decision: r≥0.85 + |bias|<0.3 → keep; r≥0.85 + |bias|≥0.3 → adjust; r<0.85 → review. See `docs/runbooks/codex-calibration.md`.

### 6 Agents

| Agent | Model | Color | Role | Write Access |
|-------|-------|-------|------|--------------|
| WorldBuilder | Opus | blue | L1 rules, storylines init, characters (L2 contracts), style extraction | Yes |
| PlotArchitect | Opus | orange | Volume outlines, L3 contracts, foreshadowing | Yes |
| ChapterWriter | Opus | green | 2500–3500 char chapters with register micro-injection (no blacklist visibility) | Yes |
| StyleRefiner | Sonnet | green | Mechanical de-AI polish: blacklist scan, AI pattern removal, format cleanup | Yes |
| Summarizer | Opus | cyan | 300-char summaries, state ops, canon hints | Yes |
| QualityJudge | Opus | purple | Track 1 contract compliance + Track 2 quality scoring (9 dimensions) | staging/evaluations only |
| ContentCritic | Opus | red | Track 3 reader engagement + Track 4 content substance + Track 5 POV boundary + Track 6 cross-chapter logic | staging/evaluations only |

Agent definitions live in `agents/*.md`. Each uses YAML frontmatter for model, tools, and trigger config. ChapterWriter and StyleRefiner run sequentially (same color, never concurrent). Normal pipeline: QualityJudge and ContentCritic run in parallel after StyleRefiner; Summarizer runs after gate pass (not before evaluation). Targeted revision: QJ/CC run in parallel after SR(lite) (no cross-dependency in recheck mode). When `eval_backend="codex"`, Summarizer/QJ/CC use Codex prompts (`prompts/codex-*.md`) via codeagent-wrapper instead of Claude Code Task agents.

### 3 Entry Skills

- **`/novel:start`** — Cold start orchestrator (full state machine from INIT through trial chapters)
- **`/novel:continue [N]`** — Chapter pipeline with interrupt recovery; default 1 chapter, max 5
- **`/novel:dashboard`** — Read-only dashboard (progress, scores, foreshadowing, costs, style drift)

Shared methodology in `skills/novel-writing/SKILL.md` (passive reference, not user-invocable).

## Key Conventions

### File Naming

- Chapters: `chapters/chapter-{C:03d}.md` (zero-padded)
- Volumes: `volumes/vol-{V:02d}/`
- Evaluations: `evaluations/chapter-{C:03d}-eval.json`
- Summaries: `summaries/chapter-{C:03d}-summary.md`

### Safety Constraints

- **Staging path enforcement**: `hooks.json` PreToolUse hook restricts all Write/Edit during pipeline to `staging/` directory
- **Manifest mode**: Entry Skills pass file paths to Agents; Agents use Read tool on-demand (no inline content injection)
- **AI blacklist**: ~120 banned Chinese phrases in `templates/ai-blacklist.json` (13 categories); target <3 hits per 千字 (maps to style_naturalness score ≥ 4)

### Anti-AI Output (4 Layers)

1. Style anchoring via `style-profile.json` (including `voice_persona` object — narrator_role / protagonist_voice_tone / dialogue_tag_preferences / rhetoric_preferences_voice / rhythm_accelerators, plus `voice_lock` flag for fallback control) + register micro-injection guidance in ChapterWriter. 4 presets shipped in `templates/voice-personas/` (snarky-storyteller / austere-narrator / empathetic-observer / epic-chronicler)
2. Constraint injection: blacklist + character speech patterns + anti-intuitive details (CW does NOT see blacklist — isolation by design)
3. Post-processing: StyleRefiner mechanical de-AI polish (blacklist scan, AI pattern removal, dash elimination, connector cleanup)
4. Detection metrics: blacklist density + adjacent-sentence repetition + simile density + AI sentence pattern count + dialogue distinctiveness + tonal_variance (10 style_naturalness sub-indicators + tonal_variance dimension in QJ)

### Context Management

- **Manifest mode**: Orchestrator passes file paths; agents read on-demand (not full text injection)
- **Context assembly**: Deterministic rules extracted to `skills/continue/references/context-assembly.md` (Step 2.0-2.7)
- **Context budgets**: ~19–24K tokens for ChapterWriter, ~8-10K for StyleRefiner, ~10–12K for Summarizer, ~14-16K for QualityJudge, ~18-22K for ContentCritic (Track 6 reads recent 3 chapters full text)
- **Track 3 tiering**: `track3_mode` (full/lite) — golden/end-of-volume/critical chapters get full Track 3; normal chapters get lite (overall_engagement + reader_feedback only). Track 3 now in ContentCritic, not QualityJudge
- **Checkpoint recovery**: `/novel:continue` resumes from `pipeline_stage` + `inflight_chapter`

## Evaluation Infrastructure (M3)

- Human-labeled 30-chapter dataset in `eval/datasets/` (JSONL)
- Labeling guide: `eval/labeling-guide.md`
- JSON schemas: `eval/schema/`
- Smoke test fixtures: `eval/fixtures/`
- Calibration measures Pearson correlation between QualityJudge and human scores
- Codex calibration: `scripts/run-codex-calibration.sh` + `eval/calibration/` reports

## Runbooks

Standardized failure-handling guides in `docs/runbooks/`:

- `quality-gate-handling.md` — Gate decision 各档位处理流程（pass/polish/revise/pause）
- `sliding-window-fix.md` — 滑窗一致性校验发现矛盾时的定位与修复
- `checkpoint-recovery.md` — Checkpoint 损坏或中断恢复路径
- `foreshadow-lifecycle.md` — 伏笔全生命周期（planted→advanced→resolved）
- `cross-volume-handoff.md` — 跨卷衔接数据流与检查清单
- `codex-calibration.md` — Codex 评估管线校准流程（6 步：准备→批量评估→阅读报告→阈值决策→Summarizer 验证→切换）
- `codex-eval-troubleshooting.md` — Codex 评估管线故障排查（超时/校验失败/backend 切换/并行冲突）

## Quality Aggregation

- `QUALITY.md` — Per-volume scoring trends, low-score alerts, cleanup queue (generated by `scripts/aggregate-quality.sh`)

## Change Management

- Design reviews tracked in `docs/dr-workflow/` (v1–v6 + final)
- Active change proposals in `openspec/changes/`
- Codex utilities in `.codex/skills/openspec-*` for DR workflow automation
