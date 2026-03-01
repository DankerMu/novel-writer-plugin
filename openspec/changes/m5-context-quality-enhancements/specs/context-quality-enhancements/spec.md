# Spec: 上下文质量增强

## ADDED Requirements

### M5.1 Canon Status

#### Requirement: L1 rules SHALL distinguish established canon from planned content

Each entry in `world/rules.json` SHALL include a `canon_status` field with value `"established"` or `"planned"`. When the field is absent, it SHALL default to `"established"` for backward compatibility.

**Scenario: ChapterWriter receives only established rules**
- GIVEN a `rules.json` containing 5 rules, 3 with `canon_status: "established"` and 2 with `canon_status: "planned"`
- WHEN the orchestrator computes `hard_rules_list` for ChapterWriter manifest
- THEN it SHALL apply filter `constraint_type == "hard" AND (canon_status == "established" OR canon_status absent)`, resulting in only the established hard rules

**Scenario: Backward compatibility with missing field**
- GIVEN a `rules.json` entry without `canon_status` field
- WHEN the orchestrator processes it
- THEN it SHALL treat the entry as `canon_status: "established"`

#### Requirement: L2 character contracts SHALL support canon_status on key facts

Each character contract in `characters/active/*.json` SHALL support an optional `canon_status` field on entries within `abilities`, `known_facts`, and `relationships` arrays. Default: `"established"`.

**Scenario: Orchestrator pre-filters planned abilities**
- GIVEN a character with `abilities: [{name: "破天剑法", canon_status: "planned"}, {name: "基础剑术", canon_status: "established"}]`
- WHEN the orchestrator assembles `paths.character_contracts[]` in manifest Step 2.4
- THEN the character JSON passed to ChapterWriter SHALL only contain the `established` ability (`基础剑术`)

**Scenario: Chapter contract introduces a planned ability**
- GIVEN a character ability `{name: "破天剑法", canon_status: "planned"}` AND chapter_contract.preconditions references "破天剑法" as introduced in this chapter
- WHEN the orchestrator assembles the character JSON
- THEN the ability SHALL be included with an `introducing: true` marker

#### Requirement: WorldBuilder SHALL initialize canon_status as planned

When WorldBuilder or PlotArchitect creates a new rule or character fact during volume planning, it SHALL set `canon_status: "planned"`. Only the orchestrator commit-stage process may upgrade to `"established"`.

**Scenario: New rule created during planning**
- GIVEN WorldBuilder generates a new rule `{id: "W-015", rule: "幽冥海域禁止飞行"}`
- WHEN the rule is written to `rules.json`
- THEN the entry SHALL include `canon_status: "planned"`

#### Requirement: Summarizer SHALL output canon_hints for commit-stage processing

Summarizer SHALL output an optional `canon_hints` field: an array of rule/fact IDs that this chapter's narrative may have established. Summarizer does NOT need to read `rules.json`; it infers from the chapter content which world-building elements were narratively confirmed.

**Scenario: Chapter establishes a planned rule**
- GIVEN chapter 15 narrates the dragon vein awakening
- WHEN Summarizer generates the chapter summary
- THEN `canon_hints` SHALL include an entry like `{type: "rule", hint: "龙脉觉醒相关规则", confidence: "high"}`

#### Requirement: Orchestrator commit stage SHALL deterministically upgrade canon_status

During `/novel:continue` Step 6 (commit), the orchestrator SHALL cross-validate `canon_hints` against `state_ops` and the planned entries in `rules.json` / character contracts. A planned entry SHALL be upgraded to `"established"` only when:
1. It appears in `canon_hints`, AND
2. A matching `set` or `foreshadow` op exists in `state_ops`

The upgrade SHALL be idempotent (upgrading an already-established entry is a no-op). Each upgrade SHALL be logged to `state/changelog.jsonl`.

**Scenario: Deterministic canon upgrade**
- GIVEN `canon_hints` contains `{type: "rule", hint: "龙脉觉醒"}` AND `state_ops` contains `{op: "set", path: "world_state.dragon_vein", value: "awakened"}`
- WHEN the orchestrator matches this against `rules.json` entry `{id: "W-007", rule: "龙脉每百年觉醒一次", canon_status: "planned"}`
- THEN `W-007.canon_status` SHALL be upgraded to `"established"` and `last_verified` updated to the current chapter number

**Scenario: Hint without matching state_op is ignored**
- GIVEN `canon_hints` mentions a rule but no corresponding `state_ops` entry exists
- WHEN the orchestrator processes commit
- THEN the rule SHALL remain `"planned"` (prevents misupgrade from mere discussion)

#### Requirement: QualityJudge SHALL warn when chapter references planned content

During L1 compliance checking, QualityJudge SHALL support a `"warning"` status value in `l1_checks` (in addition to `"pass"` and `"violation"`). Warnings SHALL NOT count as violations and SHALL NOT trigger revision gates.

**Scenario: Accidental reference to planned rule**
- GIVEN a chapter mentions "龙脉百年觉醒" but `W-007` is still `planned`
- WHEN QualityJudge performs L1 compliance check
- THEN it SHALL emit `{rule_id: "W-007", status: "warning", detail: "引用了未确立的规则 W-007（当前状态: planned）"}`

---

### M5.2 Platform Guide

#### Requirement: style-profile.json SHALL support an optional platform field

`style-profile.json` SHALL accept an optional `platform` field (string). The orchestrator SHALL resolve platform guides by convention: `templates/platforms/{platform}.md`. Any string value is accepted; no enumeration is maintained.

**Scenario: Platform field triggers guide loading**
- GIVEN `style-profile.json` contains `{platform: "fanqie"}`
- WHEN the orchestrator computes ChapterWriter manifest
- THEN `paths.platform_guide` SHALL be set to `templates/platforms/fanqie.md`

**Scenario: Missing platform field skips loading**
- GIVEN `style-profile.json` has no `platform` field
- WHEN the orchestrator computes ChapterWriter manifest
- THEN `paths.platform_guide` SHALL be absent from the manifest

**Scenario: Platform guide file not found**
- GIVEN `platform: "zongheng"` but `templates/platforms/zongheng.md` does not exist
- WHEN the orchestrator computes manifest
- THEN `paths.platform_guide` SHALL be absent and a WARNING logged

#### Requirement: `/novel:start` SHALL collect platform preference during quick start

During `/novel:start` Step B (style information collection), the orchestrator SHALL offer an optional platform selection. The chosen value SHALL be stored in `style-profile.json` as the `platform` field.

**Scenario: User selects platform during quick start**
- GIVEN a user is going through `/novel:start` quick start
- WHEN Step B presents platform options (番茄/起点/晋江/其他/跳过)
- THEN the selected value SHALL be written to `style-profile.json` as `platform`

#### Requirement: Platform guide template SHALL cover key writing dimensions

Each `templates/platforms/{platform}.md` SHALL include at minimum:
- 节奏密度（Pacing Density）：每千字建议爽点/转折数
- 章末钩子（Chapter Hook）：平台读者对章末悬念的期望强度
- 设定展示（Worldbuilding Exposition）：信息密度偏好
- 情感线权重（Romance Weight）：感情线在总体叙事中的占比建议

Additional dimensions (章节字数偏好, 对话密度, etc.) are encouraged but not required.

**Scenario: ChapterWriter uses platform guide as fallback**
- GIVEN platform guide specifies "节奏密度: 每千字 ≥1 个小转折" AND style-profile has no explicit pacing preference
- WHEN ChapterWriter writes a 3000-char chapter
- THEN the chapter SHOULD contain at least 3 pacing beats

#### Requirement: style-profile SHALL take priority over platform guide

When `style-profile.json` and platform guide provide conflicting guidance on the same dimension, `style-profile.json` SHALL take priority. Platform guide serves as fallback for dimensions not covered by the style profile.

**Scenario: Style-profile overrides platform pacing**
- GIVEN style-profile indicates a slow-paced literary style AND platform guide recommends high pacing density
- WHEN ChapterWriter resolves writing parameters
- THEN the slow-paced style from style-profile SHALL prevail

---

### M5.3 Excitement Type

#### Requirement: L3 chapter contract SHALL support excitement_type as a root-level field

Each chapter contract SHALL support an optional `excitement_type` field at the contract root level (parallel to `preconditions`, `objectives`, `postconditions`). Value is an array of 1-2 strings from the enumeration:

| Type | 含义 |
|------|------|
| `power_up` | 实力提升 / 获得新能力 |
| `reversal` | 局势逆转 / 反杀 |
| `cliffhanger` | 章末悬念 |
| `emotional_peak` | 情感高潮 / 虐心 / 甜蜜 |
| `mystery_reveal` | 谜底揭晓 / 真相大白 |
| `confrontation` | 正面对决 / 高燃对抗 |
| `worldbuilding_wow` | 世界观震撼展示 |
| `setup` | 铺垫章（无显式爽点，为后续蓄力） |

An optional `excitement_note: string` field MAY accompany `excitement_type` for free-text explanation when enumerations are insufficient.

**Constraint**: `setup` is mutually exclusive with all other types. Schema SHALL reject arrays containing `setup` alongside other values.

**Field semantics**:
- Field absent = skip excitement evaluation (backward compatibility)
- `["setup"]` = relax pacing evaluation, use "铺垫有效性" criteria instead
- `["power_up", "confrontation"]` = dual excitement requirements
- `[]` (empty array) = schema SHALL reject; treated as absent

#### Requirement: PlotArchitect SHALL populate excitement_type when generating L3 contracts

PlotArchitect SHALL assign 1-2 `excitement_type` values to each chapter contract based on the volume outline. When the outline describes a transitional/setup chapter, PlotArchitect SHALL use `["setup"]`.

**Scenario: PlotArchitect generates excitement_type**
- GIVEN a volume outline with chapter 15 described as "主角觉醒龙脉之力，击退追兵"
- WHEN PlotArchitect generates L3 contract for chapter 15
- THEN the contract root SHALL contain `excitement_type: ["power_up", "confrontation"]`

**Scenario: PlotArchitect marks setup chapter**
- GIVEN a volume outline with chapter 14 described as "主角潜入敌营，收集情报"
- WHEN PlotArchitect generates L3 contract
- THEN the contract root SHALL contain `excitement_type: ["setup"]`

#### Requirement: QualityJudge SHALL evaluate excitement delivery within the pacing dimension

When `excitement_type` is present and is NOT `["setup"]`, QualityJudge SHALL include an "爽点落地" sub-assessment within the `pacing` scoring dimension. QualityJudge encountering an unrecognized enumeration value SHALL log a WARNING and skip evaluation for that type (not crash).

**Scenario: Excitement type mismatch**
- GIVEN contract specifies `excitement_type: ["reversal"]` but the chapter contains no plot reversal
- WHEN QualityJudge evaluates
- THEN the `pacing` score SHALL be penalized and the evaluation SHALL note: `"合约要求 reversal 但未检测到局势逆转"`

**Scenario: Setup chapter uses alternative pacing criteria**
- GIVEN chapter contract has `excitement_type: ["setup"]`
- WHEN QualityJudge evaluates the `pacing` dimension
- THEN it SHALL NOT penalize the absence of explicit excitement beats; instead it SHALL evaluate "铺垫有效性" (whether the chapter creates anticipation for subsequent chapters, whether information delivery has rhythm)

**Scenario: Unknown excitement_type value**
- GIVEN chapter contract has `excitement_type: ["face_slap"]` (not in current enum)
- WHEN QualityJudge evaluates
- THEN it SHALL log a WARNING `"未知 excitement_type: face_slap，跳过该类型评估"` and evaluate remaining known types normally

---

### Cross-Feature Interactions

#### Requirement: Planned rules referenced by chapter_contract SHALL be conditionally injected

When a chapter_contract's `preconditions` or `objectives` references a world rule or character ability that is currently `planned`, the orchestrator SHALL inject that specific entry with an `introducing: true` marker instead of filtering it out. This prevents ChapterWriter from lacking context for planned power_ups or reveals.

**Scenario: Power-up depends on planned rule**
- GIVEN `excitement_type: ["power_up"]` AND chapter_contract.preconditions references rule W-007 (currently `planned`)
- WHEN the orchestrator assembles ChapterWriter manifest
- THEN W-007 SHALL be included in `hard_rules_list` with `introducing: true` annotation

#### Requirement: excitement_type SHALL take priority over platform_guide pacing suggestions

When `excitement_type: ["setup"]` is set, platform guide's pacing density recommendations SHALL be relaxed for this chapter. Per-chapter contract specificity overrides per-project platform defaults.

**Scenario: Setup chapter overrides platform pacing**
- GIVEN platform guide says "每千字 ≥1 转折" but chapter has `excitement_type: ["setup"]`
- WHEN QualityJudge evaluates pacing
- THEN the platform pacing density requirement SHALL NOT apply; setup criteria SHALL be used instead

---

## References

- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md` — PRD §9 Data Schemas
- `docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md` — Spec §2 Skills
- `skills/continue/references/context-contracts.md` — Context Contracts
- `agents/quality-judge.md` — QualityJudge agent definition (l1_checks schema)
- `agents/summarizer.md` — Summarizer agent definition (state_ops schema)
