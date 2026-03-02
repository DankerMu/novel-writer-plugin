# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code plugin for Chinese web novel (网文) multi-agent collaborative writing. 9 specialized agents orchestrated through a state-machine workflow with spec-driven quality gates and anti-AI output strategies.

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

Agents validate outputs against these layers. QualityJudge performs dual-track verification: contract compliance (hard gate) + 8-dimension scoring (soft eval).

### State Machine



State persists in `.checkpoint.json` with fields: `orchestrator_state`, `current_volume`, `last_completed_chapter`, `pipeline_stage`, `inflight_chapter`.

### Single-Chapter Pipeline



Gate thresholds: ≥4.0 pass, 3.5–3.9 polish, 3.0–3.4 revise, 2.0–2.9 review, <2.0 rewrite.

### 9 Agents

| Agent | Model | Role | Write Access |
|-------|-------|------|--------------|
| WorldBuilder | Opus | L1 rules, storylines init | Yes |
| CharacterWeaver | Opus | Characters, L2 contracts, relationship graph | Yes |
| PlotArchitect | Opus | Volume outlines, L3 contracts, foreshadowing | Yes |
| ChapterWriter | Sonnet | 2500–3500 char chapters with style exemplars | Yes |
| Summarizer | Sonnet | 300-char summaries, state ops, leak detection | Yes |
| StyleAnalyzer | Sonnet | Style fingerprint extraction (4 modes) | Yes |
| StyleRefiner | Opus | AI phrase removal, style matching, ≤15% edits | Yes |
| QualityJudge | Sonnet | Dual-track scoring, read-only | No |
| AudienceEval | Sonnet | First-person reader engagement, gate participation | No |

Agent definitions live in `agents/*.md`. Each uses YAML frontmatter for model, tools, and trigger config.

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
- **AI blacklist**: ~40 banned Chinese phrases in `templates/ai-blacklist.json`; target <3 hits per 千字 (maps to style_naturalness score ≥ 4)

### Anti-AI Output (4 Layers)

1. Style anchoring via `style-profile.json` extracted from user samples
2. Constraint injection: blacklist + character speech patterns + anti-intuitive details
3. Post-processing: StyleRefiner phrase replacement + style exemplar matching
4. Detection metrics: blacklist density + adjacent-sentence repetition < 2

### Context Management

- **Manifest mode**: Orchestrator passes file paths; agents read on-demand (not full text injection)
- **Context budgets**: ~19–24K tokens for ChapterWriter, ~10–12K for Summarizer
- **Checkpoint recovery**: `/novel:continue` resumes from `pipeline_stage` + `inflight_chapter`

## Evaluation Infrastructure (M3)

- Human-labeled 30-chapter dataset in `eval/datasets/` (JSONL)
- Labeling guide: `eval/labeling-guide.md`
- JSON schemas: `eval/schema/`
- Smoke test fixtures: `eval/fixtures/`
- Calibration measures Pearson correlation between QualityJudge and human scores

## Change Management

- Design reviews tracked in `docs/dr-workflow/` (v1–v6 + final)
- Active change proposals in `openspec/changes/`
- Codex utilities in `.codex/skills/openspec-*` for DR workflow automation
