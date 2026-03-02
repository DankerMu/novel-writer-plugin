# Tasks: AudienceEval Agent

## 1. Agent 定义 + Schema（M7.1）

- [ ] 1.1 创建 `agents/audience-eval.md`：完整 agent 定义（frontmatter + Role + Goal + 4 套 persona + 6 维度评分 + 跳读检测 + 情感弧线 + 平台信号 + 黄金三章警告 + Output JSON + Constraints）
- [ ] 1.2 创建 `eval/schema/chapter-audience.schema.json`：输出 JSON Schema（reader_scores / overall_engagement / suspicious_skim_paragraphs / emotional_arc / platform_signal / golden_chapter_flags / reader_feedback）
- [ ] 1.3 更新 `skills/continue/references/context-contracts.md`：追加 AudienceEval manifest 定义（inline: chapter, volume, platform, excitement_type, is_golden_chapter; paths: chapter_draft, recent_summaries, style_profile, chapter_contract）+ 返回值契约

## 2. Pipeline 集成 + 门控叠加（M7.2）

- [ ] 2.1 更新 `skills/continue/SKILL.md`：Step 3 流水线插入 Step 4.5（QJ 之后、门控之前），组装 manifest → 调用 audience-eval → 写入 staging/evaluations/chapter-{C:03d}-audience.json；失败/超时(60s) → null + WARNING
- [ ] 2.2 更新 `skills/continue/SKILL.md`：Step 5 门控决策追加 AudienceEval 叠加逻辑（引用 gate-decision.md）
- [ ] 2.3 更新 `skills/continue/SKILL.md`：Step 6 commit 追加移动 audience.json；Step 7 输出追加参与度
- [ ] 2.4 更新 `skills/continue/references/gate-decision.md`：追加「AudienceEval 叠加门控」section（黄金三章 engagement<3.0→revise、普通章 pass+engagement<2.5→polish、失败降级、修订指令融合）
- [ ] 2.5 更新 `skills/novel-writing/references/quality-rubric.md`：门控决策表追加 AudienceEval 行 + 脚注

## 3. Dashboard + Fixtures（M7.3）

- [ ] 3.1 更新 `skills/dashboard/SKILL.md`：Step 1 数据源追加 audience.json、Step 2 统计追加参与度/6维度/跳读/弧线/平台信号、Step 3 输出追加「读者参与度」区块、前置检查追加缺省
- [ ] 3.2 更新 `skills/dashboard/references/sample-output.md`：场景 1 追加读者参与度示例、场景 2 追加「暂无读者视角数据」
- [ ] 3.3 创建 `eval/fixtures/demo-project/evaluations/chapter-001-audience.json`：番茄 persona 示例
- [ ] 3.4 创建 `eval/fixtures/demo-project/evaluations/chapter-002-audience.json`：不同 persona/分数示例

## References

- `agents/quality-judge.md` — 参考 agent 定义模式
- `eval/schema/chapter-eval.schema.json` — 参考 schema 模式
- `skills/continue/SKILL.md` — Pipeline 集成点（Step 3, line 305）
- `skills/continue/references/gate-decision.md` — 门控决策引擎
- `skills/continue/references/context-contracts.md` — Manifest 契约
- `skills/novel-writing/references/quality-rubric.md` — 评分标准+门控表
- `skills/dashboard/SKILL.md` — Dashboard 展示
