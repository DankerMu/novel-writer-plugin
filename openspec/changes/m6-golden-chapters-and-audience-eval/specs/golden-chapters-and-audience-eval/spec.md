# Spec: 黄金三章正式化 + 受众视角评价

## ADDED Requirements

### M6.1 黄金三章正式化

#### Requirement: Quick Start SHALL include a mini volume planning step before trial chapters

After Step E (style extraction) and before Step F (chapter writing), the orchestrator SHALL invoke PlotArchitect to generate a 3-chapter outline, L3 contracts, foreshadowing plan, and storyline schedule for chapters 001-003.

**Scenario: Mini volume planning generates L3 contracts**
- GIVEN a new project has completed Steps A-E with genre, protagonist, world rules, characters, and style profile
- WHEN the orchestrator enters Step F0
- THEN PlotArchitect SHALL produce:
  - `volumes/vol-01/outline.md` (chapters 1-3 only)
  - `volumes/vol-01/chapter-contracts/chapter-001.json` through `chapter-003.json` (with `excitement_type`)
  - `volumes/vol-01/foreshadowing.json` (initial)
  - `volumes/vol-01/storyline-schedule.json` (initial)

**Scenario: Mini planning uses available context only**
- GIVEN this is the first volume (no previous volume review)
- WHEN PlotArchitect runs in mini mode
- THEN it SHALL use only `brief.md`, `world/rules.json`, `characters/active/*.json`, `style-profile.json`, and `platform_guide` (if present) as input

**Scenario: Mini planning applies platform-specific parameters**
- GIVEN `platform_guide` is present with `## 黄金三章参数` section
- WHEN PlotArchitect generates the 3-chapter outline
- THEN it SHALL respect the platform parameters:
  - Chapter word count (e.g., 番茄 2000-2300 / 起点 3000-4000 / 晋江 3000-4000)
  - Hook density (e.g., 番茄 每 300 字 / 起点 每 1000 字 / 晋江 每 1500 字)
  - Protagonist introduction timing (e.g., 番茄 200 字内含冲突 / 起点 1000 字内 / 晋江 第 1 章内)
  - CP interaction requirement (e.g., 晋江 前 3 章内必须)

**Scenario: No platform guide falls back to defaults**
- GIVEN no `platform_guide` is available
- WHEN PlotArchitect generates the 3-chapter outline
- THEN it SHALL use default parameters: 2500-3500 字/章, 每 800 字 1 个钩子, 主角 300 字内登场

#### Requirement: L3 contracts for golden chapters SHALL include genre-specific acceptance criteria

PlotArchitect SHALL include genre-aware acceptance criteria in the L3 contracts for chapters 001-003. These criteria are mandatory for QualityJudge compliance checking.

**Scenario: Xuanhuan chapter 001 contract**
- GIVEN genre is 玄幻/仙侠
- WHEN PlotArchitect generates `chapter-001.json`
- THEN `acceptance_criteria` SHALL include `golden_finger_hinted: true`
- AND if platform is 番茄: SHALL also include `protagonist_in_200_chars: true`

**Scenario: Xuanhuan chapter 003 contract**
- GIVEN genre is 玄幻/仙侠
- WHEN PlotArchitect generates `chapter-003.json`
- THEN `acceptance_criteria` SHALL include `first_power_up_or_face_slap: true`

**Scenario: Romance chapter 001 contract**
- GIVEN genre is 言情/甜宠
- WHEN PlotArchitect generates `chapter-001.json`
- THEN `acceptance_criteria` SHALL include `both_leads_appeared: true` AND `first_interaction: true`
- AND if platform is 晋江: SHALL also include `emotional_tone_hinted: true`

**Scenario: Mystery chapter 001 contract**
- GIVEN genre is 悬疑/推理
- WHEN PlotArchitect generates `chapter-001.json`
- THEN `acceptance_criteria` SHALL include `core_mystery_presented: true` AND `tension_established: true`

**Scenario: Historical chapter 001 contract**
- GIVEN genre is 历史
- WHEN PlotArchitect generates `chapter-001.json`
- THEN `acceptance_criteria` SHALL include `era_anchored: true` AND `protagonist_identity_clear: true`

**Scenario: Sci-fi chapter 001 contract**
- GIVEN genre is 科幻
- WHEN PlotArchitect generates `chapter-001.json`
- THEN `acceptance_criteria` SHALL include `world_unique_element_shown: true`

**Scenario: Urban chapter 001 contract**
- GIVEN genre is 都市
- WHEN PlotArchitect generates `chapter-001.json`
- THEN `acceptance_criteria` SHALL include `protagonist_dilemma_established: true`

#### Requirement: Quick Start trial chapters SHALL use the full pipeline

Step F SHALL execute the same pipeline as `/novel:continue` for each of the 3 trial chapters, including:
- Full ChapterWriter manifest with L3 contract, excitement_type, platform_guide, hard_rules_list, storyline context
- Summarizer with state_ops, crossref, canon_hints
- StyleRefiner
- QualityJudge with dual-track verification (L1/L2/L3/LS compliance + 8-dimension scoring)
- Quality gate decision (pass/polish/revise/review/rewrite)

**Scenario: Trial chapter goes through full quality gate**
- GIVEN chapter 001 is written during Quick Start Step F
- WHEN QualityJudge evaluates it
- THEN it SHALL perform full L3 contract compliance check (including genre-specific acceptance_criteria) and 8-dimension scoring with platform-weighted overall_final

**Scenario: Trial chapter 001 uses Double-Judge**
- GIVEN chapter 001 is the first chapter of the novel (volume start = key chapter)
- WHEN QualityJudge evaluates it
- THEN it SHALL use Double-Judge (Sonnet primary + Opus secondary, final = min)

**Scenario: Trial chapter fails quality gate**
- GIVEN chapter 002 scores 3.2 (revise threshold)
- WHEN the quality gate triggers
- THEN the same revision loop SHALL apply (ChapterWriter Opus revision, max 2 rounds)

#### Requirement: Platform-specific golden chapter hard gates

QualityJudge SHALL apply platform-specific hard gates during the compliance check for chapters 001-003. Failure of any hard gate SHALL force the evaluation to `revise` regardless of the overall score.

**Scenario: Fanqie hard gate — protagonist timing**
- GIVEN platform is 番茄 AND chapter is 001
- WHEN QualityJudge performs compliance check
- THEN it SHALL verify protagonist appears within first 200 characters with an active conflict
- AND if not met: force verdict to `revise` with reason "番茄硬门：主角需在 200 字内登场并面临冲突"

**Scenario: Fanqie hard gate — chapter-end hook**
- GIVEN platform is 番茄 AND chapter is any of 001-003
- WHEN QualityJudge performs compliance check
- THEN it SHALL verify each chapter ends with a clear suspense hook

**Scenario: Fanqie hard gate — first payoff**
- GIVEN platform is 番茄 AND chapters 001-003 are all evaluated
- WHEN QualityJudge evaluates chapter 003
- THEN it SHALL verify at least one reversal/face-slap/power-up event occurred across chapters 001-003

**Scenario: Qidian hard gate — worldview skeleton**
- GIVEN platform is 起点 AND chapters 001-003 are all evaluated
- WHEN QualityJudge evaluates chapter 003
- THEN it SHALL verify the world's foundational framework is established across chapters 001-003
- AND immersion score SHALL NOT be below 3.5

**Scenario: Jinjiang hard gate — character and CP**
- GIVEN platform is 晋江
- WHEN QualityJudge evaluates chapters 001-003
- THEN it SHALL verify:
  - Protagonist characterization shown through behavior (not narration) within first 2 chapters
  - At least one CP lead appeared within first 3 chapters
  - Emotional tone established within first 2 chapters
  - style_naturalness score SHALL NOT be below 3.5

**Scenario: No platform — no hard gates**
- GIVEN no platform_guide is present
- WHEN QualityJudge evaluates chapters 001-003
- THEN no platform-specific hard gates SHALL be applied (standard quality gate only)

#### Requirement: Volume planning SHALL inherit trial chapter outputs

When the user confirms trial results (Step G) and enters VOL_PLANNING, PlotArchitect SHALL receive the 3 existing chapter summaries and contracts as context, and SHALL extend the outline from chapter 4 onward rather than regenerating chapters 1-3.

**Scenario: PlotArchitect extends from chapter 4**
- GIVEN chapters 001-003 are committed with summaries and contracts
- WHEN the user enters VOL_PLANNING after Quick Start
- THEN PlotArchitect SHALL:
  - Read existing `volumes/vol-01/outline.md` (chapters 1-3)
  - Read `summaries/chapter-001-summary.md` through `chapter-003-summary.md`
  - Append chapters 4-N to `outline.md`
  - Generate `chapter-contracts/chapter-004.json` through `chapter-N.json`
  - Update `foreshadowing.json` and `storyline-schedule.json` to cover full volume

**Scenario: PlotArchitect may annotate adjustments to early chapters**
- GIVEN PlotArchitect determines the early outline needs minor adjustments for volume-level coherence
- WHEN generating the full volume outline
- THEN it MAY add annotations to chapters 1-3 in the outline (e.g., "suggest strengthening foreshadowing in chapter 2") but SHALL NOT regenerate their L3 contracts or chapter text

#### Requirement: Checkpoint SHALL track mini planning completion

The checkpoint field `quick_start_step` SHALL support value `"F0"` between `"E"` and `"F"`. If interrupted during Step F0, the orchestrator SHALL resume from Step F0.

**Scenario: Interrupt recovery after Step F0**
- GIVEN `quick_start_step == "F0"` and `volumes/vol-01/outline.md` exists
- WHEN the user re-enters Quick Start
- THEN the orchestrator SHALL skip to Step F (chapter writing)

#### Requirement: Genre × Platform invalid combinations SHALL trigger WARNING

**Scenario: Invalid genre-platform combination**
- GIVEN genre is 纯爱BL AND platform is 番茄
- WHEN Step F0 begins
- THEN the orchestrator SHALL log WARNING "纯爱BL 在番茄平台不可发布，请确认平台选择" and continue (non-blocking)

**Scenario: Uncommon genre-platform combination**
- GIVEN genre is 硬科幻 AND platform is 晋江
- WHEN Step F0 begins
- THEN the orchestrator SHALL log WARNING "硬科幻在晋江较为少见，建议确认目标受众" and continue (non-blocking)

---

### M6.2 受众视角评价

#### Requirement: Platform guide SHALL include evaluation weight adjustments

Each `templates/platforms/{platform}.md` SHALL include a `## 评估权重` section defining weight multipliers for the 8 scoring dimensions. Weight range: 0.5-2.0. Default (when absent): 1.0 for all dimensions.

**Scenario: Fanqie platform weights (research-backed)**
- GIVEN `templates/platforms/fanqie.md` contains `## 评估权重` with:
  - pacing: 1.5
  - emotional_impact: 1.5
  - immersion: 1.5
  - character: 0.8
  - style_naturalness: 0.5
  - plot_logic: 0.8
  - storyline_coherence: 0.8
  - foreshadowing: 1.0
- WHEN QualityJudge reads the platform guide
- THEN it SHALL apply these weights; unlisted dimensions default to 1.0

**Scenario: Qidian platform weights (research-backed)**
- GIVEN `templates/platforms/qidian.md` contains `## 评估权重` with:
  - storyline_coherence: 1.5
  - plot_logic: 1.3
  - pacing: 1.0
  - character: 1.0
  - style_naturalness: 0.8
  - immersion: 0.8
  - emotional_impact: 0.8
  - foreshadowing: 1.0
- WHEN QualityJudge reads the platform guide
- THEN it SHALL apply these weights

**Scenario: Jinjiang platform weights (research-backed)**
- GIVEN `templates/platforms/jinjiang.md` contains `## 评估权重` with:
  - character: 1.6
  - emotional_impact: 1.5
  - immersion: 1.1
  - style_naturalness: 1.0
  - pacing: 0.8
  - plot_logic: 0.8
  - storyline_coherence: 0.8
  - foreshadowing: 0.8
- WHEN QualityJudge reads the platform guide
- THEN it SHALL apply these weights

#### Requirement: Platform guide SHALL include golden chapter parameters

Each `templates/platforms/{platform}.md` SHALL include a `## 黄金三章参数` section defining chapter-length, hook-density, and protagonist-timing parameters for Step F0.

**Scenario: Fanqie golden chapter parameters**
- GIVEN `templates/platforms/fanqie.md` contains `## 黄金三章参数`
- WHEN PlotArchitect reads the platform guide during Step F0
- THEN it SHALL use: chapter_word_count=2000-2300, hook_density=每300字, protagonist_timing=200字内含冲突

**Scenario: Qidian golden chapter parameters**
- GIVEN `templates/platforms/qidian.md` contains `## 黄金三章参数`
- WHEN PlotArchitect reads the platform guide during Step F0
- THEN it SHALL use: chapter_word_count=3000-4000, hook_density=每1000字, protagonist_timing=1000字内

**Scenario: Jinjiang golden chapter parameters**
- GIVEN `templates/platforms/jinjiang.md` contains `## 黄金三章参数`
- WHEN PlotArchitect reads the platform guide during Step F0
- THEN it SHALL use: chapter_word_count=3000-4000, hook_density=每1500字, protagonist_timing=第1章内, cp_interaction=前3章内必须

#### Requirement: QualityJudge manifest SHALL support optional platform_guide

The QualityJudge manifest SHALL accept an optional `paths.platform_guide` field. When present, QualityJudge SHALL read the evaluation weight section and apply weighted scoring.

**Scenario: QualityJudge uses weighted scoring**
- GIVEN 8-dimension raw scores: pacing=4.0, foreshadowing=3.5, plot_logic=4.5, character=4.0, emotional_impact=3.5, style_naturalness=4.0, storyline_coherence=3.0, immersion=4.0
- AND platform weights (fanqie): pacing=1.5, emotional_impact=1.5, immersion=1.5, style_naturalness=0.5 (others=1.0 or as specified)
- WHEN QualityJudge computes overall_final
- THEN overall_final = sum(score_i * weight_i) / sum(weight_i) = weighted average

**Scenario: No platform guide falls back to equal weight**
- GIVEN `paths.platform_guide` is absent from QualityJudge manifest
- WHEN QualityJudge computes overall_final
- THEN it SHALL use equal weights (1.0) for all dimensions (backward compatible)

**Scenario: Weight out of range is clamped**
- GIVEN a platform guide specifies `pacing: 3.0` (exceeds max 2.0)
- WHEN QualityJudge reads the weight
- THEN it SHALL clamp to 2.0 and log a WARNING

#### Requirement: QualityJudge SHALL report both raw and weighted scores

The evaluation output SHALL include both `scores_raw` (unweighted per-dimension) and `overall_weighted` (platform-adjusted). Gate decisions SHALL use `overall_weighted` when platform weights are active.

**Scenario: Evaluation output includes both scores**
- GIVEN platform weights are active
- WHEN QualityJudge produces the evaluation JSON
- THEN it SHALL include:
  - `scores: {pacing: 4.0, foreshadowing: 3.5, ...}` (raw per-dimension)
  - `overall_raw: 3.8` (equal-weight average)
  - `overall_weighted: 3.9` (platform-weighted average)
  - `platform_weights: {pacing: 1.5, ...}` (applied weights)
  - `overall_final` = `overall_weighted` (used for gate decision)

#### Requirement: `/novel:dashboard` SHALL display platform-adjusted scores

When platform weights are active, `/novel:dashboard` SHALL display both raw average and weighted average in the quality trends section.

**Scenario: Dashboard shows dual scores**
- GIVEN project has `platform: "fanqie"` and 10 completed chapters
- WHEN user runs `/novel:dashboard`
- THEN the quality section SHALL show:
  - 通用均分 (raw): X.X
  - 番茄适配分 (weighted): X.X

---

## References

- `docs/dr-workflow/m6-golden-chapters-research/final/main.md` — 深度调研综合报告
- `skills/start/SKILL.md` — Quick Start 流程
- `skills/continue/SKILL.md` — 完整 pipeline
- `agents/quality-judge.md` — 评分逻辑
- `skills/novel-writing/references/quality-rubric.md` — 8 维度定义
- `skills/continue/references/context-contracts.md` — Manifest 契约
- `skills/dashboard/SKILL.md` — 状态展示
- `openspec/changes/m5-context-quality-enhancements/specs/context-quality-enhancements/spec.md` — M5 excitement_type 枚举
