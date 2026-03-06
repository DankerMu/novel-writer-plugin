# M8: Anti-AI Detection Hardening — 反 AI 检测硬化

## Why

1. **比喻滥用检测不足**：当前 `simile_cliche` 仅 4 个精确词条，无法覆盖"像X一样""好像X""仿佛X"等通用比喻结构，且无密度限制
2. **AI 句式原型盲区**：作者代理理解/模板化转折/抽象判断/书面腔入侵 4 类结构性 AI 味，词汇级黑名单无法覆盖
3. **破折号容忍度过高**：当前允许 ≤1/千字，实际写作中用户要求绝对零容忍
4. **对话区分度缺失**：角色说话语气相近、机械感强，缺少对话区分度量

## Capabilities

### Enhanced Capabilities

- **黑名单扩展**（`ai-blacklist.json`）：
  - `simile_cliche` 新增 6 词（犹如、好似等）
  - 新增 `simile_pattern` 语义类别（通用比喻结构检测 + 密度限制）
  - 新增 `ai_sentence_pattern` 语义类别（4 类 AI 句式原型）
  - 新增 `em_dash_ban` 零容忍类别
  - max_words 120→130，version 1.2.0→1.3.0

- **CW 约束强化**（`chapter-writer.md`）：
  - 破折号从限频→绝对禁止（Constraint 13）
  - 新增 AI 句式原型约束（Constraint 19）
  - 新增比喻密度约束（Constraint 20）
  - Phase 2 新增 Step 6.11（AI 句式原型扫描）和 Step 6.12（比喻密度扫描）

- **QJ 指标扩展**（`quality-judge.md`）：
  - style_naturalness 从 10→13 指标
  - 新增 simile_density / ai_sentence_pattern_count / dialogue_distinctiveness
  - em_dash_count 判定：count-based → >0 即 AI 特征区

- **评分规则更新**（`quality-rubric.md`）：
  - 指标表追加 3 行，阈值更新为 13 项制
  - 向后兼容：缺失≥4项退化为旧版 7 指标

- **Schema 更新**（`chapter-eval.schema.json`）：
  - anti_ai.statistical_profile 新增 4 字段
  - anti_ai 新增 ai_sentence_pattern_details[]

## Scope

6 个文件修改，无新文件创建，无 pipeline 流程变更。

## Risks

- AI 句式 LLM 检测有误判风险 → 阈值 ≥3 才进 AI 区
- 比喻 ≤3/千字对偏比喻文风可能过严 → style-profile override_constraints 可覆盖
- 破折号零容忍在书信/引用场景不合理 → 实际网文中极少，暂不加豁免
