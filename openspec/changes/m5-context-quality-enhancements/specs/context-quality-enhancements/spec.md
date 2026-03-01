# Spec: 上下文质量增强

## M5.1 Canon Status

### Requirement: L1 rules SHALL distinguish established canon from planned content

Each entry in `world/rules.json` SHALL include a `canon_status` field with value `"established"` or `"planned"`. When the field is absent, it SHALL default to `"established"` for backward compatibility.

**Scenario: ChapterWriter receives only established rules**
- GIVEN a `rules.json` containing 5 rules, 3 with `canon_status: "established"` and 2 with `canon_status: "planned"`
- WHEN the orchestrator computes `hard_rules_list` for ChapterWriter manifest
- THEN only the 3 `established` rules are included in `hard_rules_list`

**Scenario: Backward compatibility with missing field**
- GIVEN a `rules.json` entry without `canon_status` field
- WHEN the orchestrator processes it
- THEN it SHALL treat the entry as `canon_status: "established"`

### Requirement: L2 character contracts SHALL support canon_status on key facts

Each character contract in `characters/active/*.json` SHALL support an optional `canon_status` field on entries within `abilities`, `known_facts`, and `relationships` arrays. Default: `"established"`.

**Scenario: Planned ability is not treated as known**
- GIVEN a character with `abilities: [{name: "破天剑法", canon_status: "planned"}]`
- WHEN ChapterWriter references this character
- THEN the ability SHALL NOT appear in the character's capability summary unless the chapter contract explicitly introduces it

### Requirement: Summarizer SHALL auto-upgrade canon_status after chapter confirms content

When Summarizer extracts `state_ops` that reference a rule or fact currently marked `planned`, it SHALL emit a `canon_upgrade` operation to change its status to `established`.

**Scenario: Rule becomes established through narrative**
- GIVEN `rules.json` contains `{id: "R-007", rule: "龙脉每百年觉醒一次", canon_status: "planned"}`
- WHEN chapter 15 narrates the dragon vein awakening and Summarizer extracts this as a state_op
- THEN Summarizer SHALL output `{op: "canon_upgrade", target: "rules/R-007", new_status: "established"}`

### Requirement: QualityJudge SHALL warn when chapter references planned content

During L1 compliance checking, QualityJudge SHALL flag a WARNING (not FAIL) when the chapter text references facts currently marked as `planned`.

**Scenario: Accidental reference to planned rule**
- GIVEN a chapter mentions "龙脉百年觉醒" but `R-007` is still `planned`
- WHEN QualityJudge performs L1 compliance check
- THEN it SHALL emit a warning: `"引用了未确立的规则 R-007（当前状态: planned）"`

---

## M5.2 Platform Guide

### Requirement: style-profile.json SHALL support an optional platform field

`style-profile.json` SHALL accept an optional `platform` field (string). Recognized values: `"fanqie"`, `"qidian"`, `"jinjiang"`, `"zongheng"`, `"custom"`. When absent or unrecognized, no platform guide is loaded.

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

### Requirement: Platform guide template SHALL cover key writing dimensions

Each `templates/platforms/{platform}.md` SHALL include at minimum:
- 节奏密度（Pacing Density）：每千字建议爽点/转折数
- 章末钩子（Chapter Hook）：平台读者对章末悬念的期望强度
- 设定展示（Worldbuilding Exposition）：信息密度偏好
- 情感线权重（Romance Weight）：感情线在总体叙事中的占比建议

**Scenario: ChapterWriter uses platform guide**
- GIVEN platform guide specifies "节奏密度: 每千字 ≥1 个小转折"
- WHEN ChapterWriter writes a 3000-char chapter
- THEN the chapter SHOULD contain at least 3 pacing beats

---

## M5.3 Excitement Type

### Requirement: L3 chapter contract SHALL support excitement_type field

Each chapter contract's `objectives` section SHALL support an optional `excitement_type` field. Value is an array of 1-2 strings from the enumeration:

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

**Scenario: PlotArchitect generates excitement_type**
- GIVEN a volume outline with chapter 15 described as "主角觉醒龙脉之力，击退追兵"
- WHEN PlotArchitect generates L3 contract for chapter 15
- THEN `objectives.excitement_type` SHALL be `["power_up", "confrontation"]`

**Scenario: Setup chapter relaxes excitement evaluation**
- GIVEN chapter contract has `excitement_type: ["setup"]`
- WHEN QualityJudge evaluates the chapter
- THEN the "节奏控制" dimension SHALL NOT penalize the absence of explicit excitement beats

### Requirement: QualityJudge SHALL evaluate excitement delivery

When `excitement_type` is present and is NOT `["setup"]`, QualityJudge SHALL include an "爽点落地" sub-assessment within the "节奏控制" scoring dimension.

**Scenario: Excitement type mismatch**
- GIVEN contract specifies `excitement_type: ["reversal"]` but the chapter contains no plot reversal
- WHEN QualityJudge evaluates
- THEN the "节奏控制" score SHALL be penalized and the evaluation SHALL note: `"合约要求 reversal 但未检测到局势逆转"`

---

## References

- [PRD §9 Data Schemas](../../../docs/dr-workflow/novel-writer-tool/final/prd/09-data.md)
- [Spec §2 Skills](../../../docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md)
- [Context Contracts](../../../skills/continue/references/context-contracts.md)
