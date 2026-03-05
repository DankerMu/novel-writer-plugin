# 质量回顾

1. 使用 Glob + Read 收集近 10 章数据（按章节号排序取最新）：
   质量评估数据：
   - `evaluations/chapter-*-eval.json`（overall_final + contract_verification + gate metadata 如有）
   - `logs/chapter-*-log.json`（gate_decision/revisions/force_passed + key chapter judges 如有）
   一致性检查数据（Step 2 使用）：
   - `chapters/chapter-*.md`（一致性检查需要；只取最近 10 章）
   - `summaries/chapter-*-summary.md`（用于交叉验证与降级）
   - `volumes/vol-{V:02d}/chapter-contracts/chapter-*.json`（如存在：用于解析 concurrent_state 做 LS-001 对齐）
   - `storylines/storyline-spec.json` 与 `volumes/vol-{V:02d}/storyline-schedule.json`（如存在）
   - `characters/active/*.json` + `state/current-state.json`（display_name ↔ slug 映射核对）
   风格与黑名单（Step 3 使用）：
   - `style-drift.json`（如存在：active + drifts + detected_chapter）
   - `ai-blacklist.json`（version/last_updated/words/whitelist/update_log）
   - `style-profile.json`（preferred_expressions；用于解释黑名单豁免）
1.5. **旧评估 Track 3 补全检测**：
   - 扫描 Step 1 收集的 eval.json，筛选 `reader_evaluation == null` 或字段缺失的章节
   - 若存在待补全章节，使用 AskUserQuestion 提示：
     ```
     检测到以下章节缺少读者参与度评估（Track 3）：
     Ch {list}

     选项：
     1. 补全评估 (Recommended) — 对这些章节重跑 QualityJudge Track 3
     2. 跳过 — 继续质量回顾，后续再处理
     ```
   - 选项 1 时，逐章执行补全：
     a. 组装 QualityJudge manifest（复用 `/novel:continue` Step 2.6 的路径计算逻辑，追加 `mode: "track3_backfill"`）
     b. 派发 QualityJudge Agent（Task, subagent_type="quality-judge"）：仅执行 Track 3，返回 `reader_evaluation` JSON
     c. 读取对应 `evaluations/chapter-{C:03d}-eval.json`，将返回的 `reader_evaluation` 合并写入 `eval_used.reader_evaluation` 字段
     d. 补全不影响已有 overall/recommendation/gate_decision（Track 3 仅降级不升级，历史门控决策不追溯变更）
   - 选项 2 时跳过，继续 Step 2
2. **一致性检查（NER，周期性每 10 章）**：
   - 章节范围：`[max(1, last_completed_chapter-9), last_completed_chapter]`
   - 实体抽取（优先确定性脚本，失败回退 LLM）：
     - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh`：
       - 逐章执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh chapters/chapter-{C:03d}.md`
       - stdout 必须为合法 JSON（schema 见 `skills/continue/references/continuity-checks.md`）；失败则记录原因并回退
     - 否则 / 脚本失败：基于 `summaries/`（必要时回看 `chapters/`）按同一 schema 抽取 entities，并为每类实体输出 `confidence`
   - 一致性规则（输出 issues，带 severity/confidence/evidence/suggestions）：
     - 角色一致性：display_name ↔ slug_id 映射冲突；state/档案 display_name 不一致；关系值单章剧烈跳变（仅标记，需 evidence）
     - 空间一致性：同一 time_marker 下同一角色出现在多个地点（高置信需同时具备 time_marker + 角色 + 地点的证据片段）
     - 时间线一致性（LS-001 hard 输入）：跨故事线并发状态（concurrent_state）与 time_marker/事件顺序矛盾（按 `timeline_contradiction` issue 输出）
   - 报告落盘（回归友好）：
     - 写入 `logs/continuity/continuity-report-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json`
     - 同步写入/覆盖 `logs/continuity/latest.json`（供 `/novel:continue` 注入 QualityJudge LS-001 使用）
3. 生成质量报告（简洁但可追溯）：
   - 均分与趋势：近 10 章均分 vs 全局均分
   - 低分章节列表：overall_final < 3.5（按分数升序列出，展示 gate_decision + revisions）
   - 强制修订统计：revisions > 0 的章节占比；并区分原因：
     - `Spec/LS high-confidence violation`（contract_verification 中任一 violation 且 confidence="high"）
     - `score 3.0-3.4`（无 high-confidence violation 但 overall 落入区间）
   - force pass：force_passed=true 的章节列表（提示"已达修订上限后强制通过"）
   - 关键章双裁判：存在 secondary judge 的章节，展示 primary/secondary/overall_final（取 min）与使用的裁判（used）
   - 一致性检查简报（来自 `logs/continuity/latest.json`）：
     - issues_total + 按 severity 分布
     - 高严重级（severity=high）的前 3 条（含 evidence 与建议）
     - 若存在 `timeline_contradiction` 且 confidence=high：提示“可能触发 LS-001 hard”，建议优先修正或在后续章节补锚点
   - 风格漂移（每 5 章检测）：
     - 若 `style-drift.json.active=true`：展示 detected_chapter/window + drifts[].directive，并提示"后续章节会自动注入纠偏指令"
     - 否则：展示"未启用纠偏 / 已回归基线并清除"
   - AI 黑名单维护：
     - 展示 `ai-blacklist.json` 的 version/last_updated/words_count/whitelist_count
     - 若存在 `update_log[]`：展示最近 3 条变更摘要（added/exempted/removed），提醒用户可手动编辑 words/whitelist
4. **伏笔盘点 + 跨线桥梁检查**（周期性每 10 章；不阻断写作）：
   - Read `foreshadowing/global.json`（如不存在：跳过伏笔盘点区块）
   - Read `volumes/vol-{V:02d}/foreshadowing.json`（如存在：用于计划对照与 bridge 校验）
   - 统计（用于输出与落盘）：
     - active_count：`status!="resolved"` 的条目数
     - resolved_count：`status=="resolved"` 的条目数
     - overdue_short：`scope=="short"` 且 `status!="resolved"` 且存在 `target_resolve_range=[start,end]` 且 `last_completed_chapter > end`（规则定义见 `skills/continue/references/foreshadowing.md` §4）
     -（可选）plan 对照：若存在本卷 plan，则统计 planned_total / missing_in_global（plan 中 id 在 global 不存在）/ resolved_in_global（plan 中 id 在 global 且 status==resolved）
   - **桥梁检查**（`storylines/storylines.json.relationships[].bridges.shared_foreshadowing[]`）：
     - 若 `relationships` 为空或不存在：跳过桥梁检查
     - 对每个 relationship 的每个 shared_foreshadowing id：
       - 若该 id 存在于 `foreshadowing/global.json.foreshadowing[].id` 或 `volumes/vol-{V:02d}/foreshadowing.json.foreshadowing[].id` → ok
       - 否则记为 broken（断链）
     - broken 项需要包含：missing_id + relationship(from/to/type) + 建议动作（补 plan / 纠正 ID / 确认是否应在本章 planted）
   - 报告落盘（回归友好）：
     - 创建目录（幂等）：`mkdir -p logs/foreshadowing logs/storylines`
     - 写入 `logs/foreshadowing/foreshadowing-check-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json`
     - 同步写入/覆盖 `logs/foreshadowing/latest.json`
     - 写入 `logs/storylines/broken-bridges-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json`
     - 同步写入/覆盖 `logs/storylines/broken-bridges-latest.json`
5. **故事线节奏分析（简报）**（周期性每 10 章；不阻断写作）：
   - Read `volumes/vol-{V:02d}/storyline-schedule.json`（如不存在：跳过节奏分析区块）
   - 在章节范围 `[start, end]`（同 Step 2）内，基于 `summaries/chapter-*-summary.md` 的 `- storyline_id: ...` 统计：
     - appearances：每条 active storyline 的出场次数
     - last_seen_chapter / chapters_since_last（以 end 为基准）
     - dormant_flag（仅对 secondary 线）：
       - 若 `interleaving_pattern.secondary_min_appearance` 匹配 `^every_(\\d+)_chapters$` 得到 `N`
       - 当 `chapters_since_last > N` → 标记为疑似休眠，并建议“安排一次出场或通过回忆重建”
   - 交汇达成率（convergence_events）：
     - 对每个 event.chapter_range=[a,b]，检查 involved_storylines 在 `[a,b]` 内是否都至少出现 1 次
     - 若未达成：列出 missing_storylines，并给出“最近一次出现章/下一次出现章”（在全 summaries 中搜最近）作为偏差提示
   - 报告落盘（JSON）：
     - 创建目录（幂等）：`mkdir -p logs/storylines`
     - 写入 `logs/storylines/rhythm-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json`
     - 同步写入/覆盖 `logs/storylines/rhythm-latest.json`
6. 输出建议动作（不强制）：
   - 对低分/高风险章节：建议用户"回看/手动修订/接受并继续"
   - 若存在多章连续低分：建议先暂停写作，回到"更新设定/调整方向"
