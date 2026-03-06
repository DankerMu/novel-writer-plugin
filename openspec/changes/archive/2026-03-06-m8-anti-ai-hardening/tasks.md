# Tasks: Anti-AI Detection Hardening

## 1. 黑名单扩展 + 润色指南（M8.1 + M8.2，可并行）

- [ ] 1.1 更新 `templates/ai-blacklist.json`：扩展 simile_cliche 词条 +6、新增 simile_pattern/ai_sentence_pattern/em_dash_ban 类别、words[] 追加"——"、max_words→130、version→1.3.0
- [ ] 1.2 更新 `docs/anti-ai-polish.md`：Layer 6 破折号零容忍、新增 Layer 7 AI 句式原型、Layer 2 比喻密度增强、Layer 4 对话区分规则、快速检查清单追加 2 项

## 2. CW 约束更新（M8.3，依赖 M8.1+M8.2）

- [ ] 2.1 更新 `agents/chapter-writer.md`：Constraint 13 破折号绝对禁止
- [ ] 2.2 更新 `agents/chapter-writer.md`：新增 Constraint 19（AI 句式原型）+ Constraint 20（比喻密度）
- [ ] 2.3 更新 `agents/chapter-writer.md`：Phase 2 Step 6.4 全破折号替换 + 新增 Step 6.11/6.12
- [ ] 2.4 更新 `agents/chapter-writer.md`：P0/P1 列表更新 + P0 预算调整

## 3. QJ 指标 + 评分规则 + Schema（M8.4 + M8.5，依赖 M8.3）

- [ ] 3.1 更新 `agents/quality-judge.md`：style_naturalness 指标 10→13，em_dash_count 判定更新，anti_ai 输出块新增字段
- [ ] 3.2 更新 `skills/novel-writing/references/quality-rubric.md`：§6 指标表追加 3 行、评分阈值更新为 13 项制
- [ ] 3.3 更新 `eval/schema/chapter-eval.schema.json`：statistical_profile 新增 4 字段 + ai_sentence_pattern_details[]

## References

- `templates/ai-blacklist.json` — 黑名单数据源
- `docs/anti-ai-polish.md` — 润色指南
- `agents/chapter-writer.md` — CW 约束 + Phase 2
- `agents/quality-judge.md` — QJ 评估指标
- `skills/novel-writing/references/quality-rubric.md` — 评分标准
- `eval/schema/chapter-eval.schema.json` — 输出 Schema
