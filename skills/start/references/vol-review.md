# 卷末回顾

1. 收集本卷 `evaluations/`、`summaries/`、`foreshadowing/global.json`、`storylines/`，生成本卷回顾要点（质量趋势、低分章节、未回收伏笔、故事线节奏、桥梁断链）
2. **全卷一致性报告（NER）**：
   - **幂等性检查**：若 `volumes/vol-{V:02d}/continuity-report.json` 已存在（由 `/novel:continue` 卷末自动回顾生成），提示用户”卷末一致性检查已自动完成”，提供选项：使用现有报告（Recommended）/ 重新生成。选择”使用现有”时跳过 NER 抽取，直接读取既有报告用于 Step 4 review.md 生成
   - 章节范围：优先使用本卷 `outline.md` 解析得到的 `[chapter_start, chapter_end]`；若解析失败则退化为”本卷 evaluations/ 与 summaries/ 中匹配 `chapter-(\d{3})` 的章节号集合，取 min/max 作为范围”
   - 实体抽取与报告 schema：见 `skills/continue/references/continuity-checks.md`
   - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh`：逐章执行抽取；否则回退 LLM（优先 summaries，必要时回看 chapters），按同一 schema 抽取 entities，并为每类实体输出 confidence
   - 输出 timeline/location/relationship/mapping 等 issues（含 severity/confidence/evidence/suggestions）
   - 落盘：
     - 写入 `volumes/vol-{V:02d}/continuity-report.json`
     - 同步写入/覆盖 `logs/continuity/latest.json`（供后续 `/novel:continue` 注入 QualityJudge LS-001）
3. **伏笔盘点 + 桥梁检查 + 节奏分析**（卷级汇总；不阻断）：
   - 章节范围：使用 Step 2 得到的 `[chapter_start, chapter_end]`
   - Read（如存在）：
     - 本卷伏笔计划：`volumes/vol-{V:02d}/foreshadowing.json`
     - 本卷故事线调度：`volumes/vol-{V:02d}/storyline-schedule.json`
     - 全局故事线定义：`storylines/storylines.json`
   - 伏笔盘点（计划 vs 事实）：
     - planned_total：本卷 plan 中条目数（如 plan 缺失则为 0）
     - resolved_in_global：plan 中 id 在 `foreshadowing/global.json` 存在且 status==resolved
     - pending_in_global：plan 中 id 在 global 存在且 status!=resolved
     - missing_in_global：plan 中 id 在 global 不存在（可能“计划未埋设”或“Summarizer 漏提取”）
     - overdue_short：同质量回顾规则（`scope=="short"` 且未回收且超过 `target_resolve_range` 上限）（规则定义见 `skills/continue/references/foreshadowing.md` §4）
     - 落盘：写入 `volumes/vol-{V:02d}/foreshadowing-report.json`
   - 桥梁检查（shared_foreshadowing traceable）：
     - 若 `relationships` 为空或不存在：跳过桥梁检查
     - 对 `storylines/storylines.json.relationships[].bridges.shared_foreshadowing[]` 的每个 id：
       - 若存在于 global 或本卷 plan → ok，否则记为 broken（含 from/to/type + 建议动作）
     - 落盘：写入 `volumes/vol-{V:02d}/broken-bridges.json`
   - 节奏分析（storyline rhythm）：
     - 基于 summaries 的 `- storyline_id: ...`，在 `[chapter_start, chapter_end]` 内统计每条 active storyline 出场次数、last_seen、最大休眠间隔
     - 基于 schedule 的 `secondary_min_appearance`（如能解析 every_N）对 secondary 线给出“疑似休眠”提示
     - convergence_events 达成率：检查 involved_storylines 是否都在 event.range 内出现；未达成则列 missing + 偏差提示
     - 落盘：写入 `volumes/vol-{V:02d}/storyline-rhythm.json`
   - 同步 latest（便于 `/novel:continue` 与 `/novel:dashboard` 快速展示）：
     - 创建目录（幂等）：`mkdir -p logs/foreshadowing logs/storylines`
     - 覆盖写入：`logs/foreshadowing/latest.json`、`logs/storylines/broken-bridges-latest.json`、`logs/storylines/rhythm-latest.json`
4. 写入 `volumes/vol-{V:02d}/review.md`（在回顾中增加以下小节）：
   - 质量趋势与低分章节
   - 伏笔完成度与风险项（引用 `foreshadowing-report.json` 的关键统计 + overdue 列表）
   - 桥梁断链清单（引用 `broken-bridges.json`，按严重度/数量提示）
   - 故事线节奏简报（引用 `storyline-rhythm.json`：出场统计 + 疑似休眠 + 交汇达成）
   - 一致性报告摘要（issues_total、high 严重级列表、LS-001 风险提示）
5. State 清理（每卷结束时，`docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` §8.5；生成清理报告供用户确认）：
   - Read `state/current-state.json`（如存在）
   - Read `world/rules.json`（如存在；用于辅助判断"持久化属性"vs"临时条目"；缺失时该判断无法执行，相关条目一律归为候选）
   - Read `characters/retired/*.json`（如存在；若 `characters/retired/` 目录不存在则先创建）并构建 `retired_ids`
   - **确定性安全清理（可直接执行）**：
     - 从 `state/current-state.json.characters` 移除 `retired_ids` 的残留条目
   - **候选清理（默认不自动删除）**：
     - 标记并汇总"过期临时条目"候选，判断规则：
       1. `state/current-state.json.world_state` 中的临时标记（如活动状态、事件标志）：无活跃伏笔引用 AND 无故事线引用 AND 不属于 L1 rules 中定义的持久化属性
       2. `state/current-state.json.characters.{id}` 中的临时属性（如 inventory 中的一次性物品、临时 buff）：无伏笔引用 AND 无故事线引用
       3. 不确定的条目一律归为"候选"而非"确定性清理"，由用户决定
   - 在 `volumes/vol-{V:02d}/review.md` 追加 "State Cleanup" 段落：已清理项 + 候选项 + 删除理由
   - AskUserQuestion 让用户确认是否应用候选清理（不确定项默认保留）
6. AskUserQuestion 让用户确认"进入下卷规划 / 调整设定 / 导入研究资料"
7. 确认进入下卷规划后更新 `.checkpoint.json`：`current_volume += 1, orchestrator_state = "VOL_PLANNING"`（其余字段保持；`pipeline_stage=null`, `inflight_chapter=null`）
