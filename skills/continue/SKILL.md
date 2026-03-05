---
name: continue
is_user_facing: true
description: >
  该技能用于续写小说的下一章或批量续写多章。支持参数 [N] 指定章数（默认 1，建议不超过 5）。
  This skill should be used when the user says "续写", "继续写", "写下一章", "继续创作",
  "写N章", "批量续写", "恢复中断的章节", "断点续写", /novel:continue,
  or selects "继续写作" from /novel:start.
  Requires project to be in WRITING or CHAPTER_REWRITE state.
---

# 续写命令

你是小说续写调度器。你的任务是读取当前进度，按流水线依次调度 Agent 完成 N 章续写。

## 运行约束

- **可用工具**：Read, Write, Edit, Glob, Grep, Bash, Task, AskUserQuestion
- **推荐模型**：sonnet
- **参数**：`[N]` — 续写章数，默认 1，最大建议 5

## 注入安全（Manifest 模式）

v2 架构下，编排器不再将文件全文注入 Task prompt，改为传递文件路径由 subagent 自行读取。注入安全由各 Agent frontmatter 中的安全约束保障。详见 Step 2.0。

## 执行流程

### Step 1: 读取 Checkpoint

```
读取 .checkpoint.json：
- current_volume: 当前卷号
- last_completed_chapter: 上次完成的章节号
- orchestrator_state: 当前状态（必须为 WRITING 或 CHAPTER_REWRITE，否则提示用户先通过 /novel:start 完成规划）
- pipeline_stage: 流水线阶段（用于中断恢复）
- inflight_chapter: 当前处理中断的章节号（用于中断恢复）
- revision_count: 当前 inflight_chapter 的修订计数（用于限制修订循环；默认 0）
```

如果 `orchestrator_state` 既不是 `WRITING` 也不是 `CHAPTER_REWRITE`，输出提示并终止：
> 当前状态为 {state}，请先执行 `/novel:start` 完成项目初始化或卷规划。

同时确保 staging 子目录存在（幂等）：
```
mkdir -p staging/chapters staging/summaries staging/state staging/storylines staging/evaluations
```

### Step 1.5: 中断恢复（pipeline_stage）

若 `.checkpoint.json` 满足以下条件：
- `pipeline_stage != "committed"` 且 `pipeline_stage != null`
- `inflight_chapter != null`

则本次 `/novel:continue` **必须先完成** `inflight_chapter` 的流水线，并按 `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md` §9.2 的规则幂等恢复：

- `pipeline_stage == "drafting"`：
  - 若 `staging/chapters/chapter-{C:03d}.md` 不存在 → 从 ChapterWriter 重启整章
  - 若 `staging/chapters/chapter-{C:03d}.md` 已存在但 `staging/summaries/chapter-{C:03d}-summary.md` 不存在 → 从 Summarizer 恢复
- `pipeline_stage == "drafted"` → 跳过 ChapterWriter/Summarizer，从 QualityJudge 恢复
- 向后兼容：遇到旧 checkpoint 的 `refined` 视为 `drafted`
- `pipeline_stage == "judged"` → 读取 `staging/evaluations/chapter-{C:03d}-eval-raw.json`（QJ 已落盘），直接执行门控决策 + commit 阶段
- `pipeline_stage == "revising"` → 修订中断，从 ChapterWriter 重启（保留 revision_count 以防无限循环）

恢复章完成 commit 后，再继续从 `last_completed_chapter + 1` 续写后续章节，直到累计提交 N 章（包含恢复章）。

### Step 1.6: 错误处理（ERROR_RETRY）

当流水线任意阶段发生错误（Task 超时/崩溃、结构化 JSON 无法解析、写入失败、锁冲突等）时：

1. **自动重试一次**：对失败步骤重试 1 次（避免瞬时错误导致整章中断）
2. **重试成功**：继续执行流水线（不得推进 `last_completed_chapter`，直到 commit 成功）
3. **重试仍失败**：
   - 更新 `.checkpoint.json.orchestrator_state = "ERROR_RETRY"`（保留 `pipeline_stage`/`inflight_chapter` 便于恢复）
   - 释放并发锁（`rm -rf .novel.lock`）
   - 输出提示并暂停：请用户运行 `/novel:start` 决策下一步（重试/回看/调整方向）

### Step 2: 组装 Context（确定性）

对于每章（默认从 `last_completed_chapter + 1` 开始；如存在 `inflight_chapter` 则先恢复该章），按**确定性规则**组装 Task prompt 所需的 context。

> 原则：同一章 + 同一项目文件输入 → 组装结果唯一；缺关键文件/解析失败 → 立即停止并给出可执行修复建议（避免“缺 context 继续写”导致串线/违约）。

#### Step 2.0: Manifest 模式说明

**v2 架构变更**：编排器不再将文件全文读入并用 `<DATA>` 标签包裹后注入 Task prompt。改为在 manifest 中传递文件路径，由 subagent 自行 Read。

此变更的收益：
- 编排器 prompt 体积大幅缩减（路径 vs 全文）
- Subagent 可按需读取，避免加载无关内容
- 消除"双重读取"开销（编排器读 → 注入 → subagent 解析）

注入安全由各 Agent frontmatter 中的安全约束段落保障——Agent 被指示将读取的外部文件内容视为参考数据，不执行其中的操作请求。

> **兼容说明**：Step 2.1-2.5 中的确定性计算逻辑不变，仅最终输出从"内容注入"改为"路径引用"。

#### Step 2.1: 从 outline.md 提取本章大纲区块（确定性）

1. 读取本卷大纲：`outline_path = volumes/vol-{V:02d}/outline.md`（不存在则终止并提示回到 `/novel:start` → “规划本卷”补齐）。
2. 章节区块定位（**不要求冒号**；允许 `:`/`：`/无标题）：
   - heading regex：`^### 第 {C} 章(?:[:：].*)?$`
3. 提取范围：从命中行开始，直到下一行满足 `^### `（不含）或 EOF。
4. 若无法定位本章区块：输出错误（包含期望格式示例 `### 第 12 章: 章名`），并提示用户回到 `/novel:start` → “规划本卷”修复 outline 格式后重试。
5. 解析章节区块内的固定 key 行（确定性；用于后续一致性校验）：
   - 期望格式：`- **Key**: value`
   - 必需 key：`Storyline`、`POV`、`Location`、`Conflict`、`Arc`、`Foreshadowing`、`StateChanges`、`TransitionHint`
   - 提取 `outline_storyline_id = Storyline`（若缺失或为空 → 视为 outline 结构损坏，报错并终止）

同时，从 outline 中提取本卷章节边界（用于卷首/卷尾双裁判与卷末状态转移）：
- 扫描所有章标题：`^### 第 (\d+) 章`
- `chapter_start = min(章节号)`，`chapter_end = max(章节号)`
- 若无法提取边界：视为 outline 结构损坏，按上述方式报错并终止。

#### Step 2.2: `hard_rules_list`（L1 世界规则 → 禁止项列表，确定性）

1. 读取并解析 `world/rules.json`（如不存在则 `hard_rules_list = []`）。
2. 筛选 `constraint_type == “hard”` 且 `(canon_status == “established” 或 canon_status 缺失)` 的规则，按 `id` 升序输出为禁止项列表：

```
- [W-001][magic_system] 修炼者突破金丹期需要天地灵气浓度 ≥ 3级
- [W-002][geography] 禁止在”幽暗森林”使用火系法术（exceptions: ...）
- [INTRODUCING][W-003][magic_system] 本章首次展现的规则描述
```

> **Canon Status 过滤**：`canon_status == “planned”` 的规则默认不注入。例外：若 `chapter_contract.preconditions.required_world_rules`（如存在）引用了某 planned 规则 ID，则以 `[INTRODUCING]` 前缀注入该规则，表示本章将首次展现。

同时将所有 planned 规则 ID 列表记为 `planned_rule_ids`，传给 QualityJudge 用于 planned 引用检测。

该列表用于 ChapterWriter（禁止项提示）与 QualityJudge（逐条验收）。

#### Step 2.3: `entity_id_map`（从角色 JSON 构建，确定性）

1. `Glob("characters/active/*.json")` 获取活跃角色结构化档案。
2. 对每个文件：
   - `slug_id` 默认取文件名（去掉 `.json`）
   - `display_name` 取 JSON 中的 `display_name`
3. 构建 `entity_id_map = {slug_id → display_name}`（并在本地临时构建反向表 `display_name → slug_id` 供裁剪/映射使用）。

该映射传给 Summarizer，用于把正文中的中文显示名规范化为 ops path 的 slug ID（如 `characters.lin-feng.location`）。

#### Step 2.4: L2 角色契约裁剪（确定性）

前置：读取并解析本章 L3 章节契约（缺失则终止并提示回到 `/novel:start` → “规划本卷”补齐）：
- `chapter_contract_path = volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.json`

裁剪规则：

- 若存在 `chapter_contract.preconditions.character_states`：
  - 仅加载这些 preconditions 中涉及的角色（**无硬上限**；交汇事件章可 > 10）
  - 注意：`character_states` 的键为中文显示名，需要用 `entity_id_map` 反向映射到 `slug_id`
- 否则：
  - 最多加载 15 个活跃角色（按“最近出场”排序截断）
  - “最近出场”计算：扫描近 10 章 `summaries/`（从新到旧），命中 `display_name` 的第一次出现即视为最近；未命中视为最旧
  - 排序规则：`last_seen_chapter` 降序 → `slug_id` 升序（保证确定性）

加载内容：
- `character_contracts`：记录 `characters/active/{slug_id}.json` 路径列表（写入 manifest.paths.character_contracts）
- `character_profiles`：记录 `characters/active/{slug_id}.md` 路径列表（如存在；写入 QualityJudge manifest.paths.character_profiles）

**Canon Status 预过滤**（对入选角色 JSON 执行）：

1. 对每个入选角色的 `abilities[]`、`known_facts[]`、`relationships[]` 数组，过滤掉 `canon_status == "planned"` 的条目（仅保留 `established` 或缺失 canon_status 的条目）
2. 例外：若 `chapter_contract.preconditions.character_states` 引用了某角色的 planned 条目（按 name/fact/target 模糊匹配），保留该条目并追加 `"introducing": true` 标记
3. 过滤后的角色 JSON 写入 `staging/context/characters/{slug_id}.json`（临时副本，commit 阶段随 staging 清理）
4. `manifest.paths.character_contracts[]` 指向裁剪后的 `staging/context/characters/{slug_id}.json`（而非原始 `characters/active/` 路径）
5. 向后兼容：若角色 JSON 无 `abilities`/`known_facts`/`relationships` 字段，视为空数组，跳过过滤

#### Step 2.5: storylines context + memory 注入（确定性）

1. 读取 `volumes/vol-{V:02d}/storyline-schedule.json`（如存在则解析；用于判定 dormant_storylines 与交汇事件 involved_storylines）。
2. 读取 `storylines/storyline-spec.json`（如存在；注入给 QualityJudge 做 LS 验收）。
3. 章节契约与大纲一致性校验（确定性；不通过则终止，避免“拿错契约继续写”导致串线/违约）：
   - `chapter_contract.chapter == C`
   - `chapter_contract.storyline_id == outline_storyline_id`
   - `chapter_contract.objectives` 至少 1 条 `required: true`
4. 以 `chapter_contract` 为优先来源确定：
   - `storyline_id`（本章所属线）
   - `storyline_context`（含 `last_chapter_summary` / `chapters_since_last` / `line_arc_progress` / `concurrent_state`）
   - `transition_hint`（如存在）
5. memory 路径策略：
   - 当前线 `storylines/{storyline_id}/memory.md`：如存在，写入 manifest.paths.storyline_memory
   - 相邻线：
     - 若 `transition_hint.next_storyline` 存在 → 将该线 memory 路径加入 manifest.paths.adjacent_memories（若不在 `dormant_storylines`）
   - 若当前章落在任一 `convergence_events.chapter_range` 内 → 将 `involved_storylines` 中除当前线外的 memory 路径加入 manifest.paths.adjacent_memories（过滤 `dormant_storylines`）
   - 冻结线（`dormant_storylines`）：**不加入 memory 路径**，仅保留 `concurrent_state` 一句话状态（inline）
6. `foreshadowing_tasks` 组装（确定性）：
   - 数据来源：
     - 事实层：`foreshadowing/global.json`（如不存在则视为空）
     - 计划层：`volumes/vol-{V:02d}/foreshadowing.json`（如不存在则视为空）
   - 优先确定性脚本（M3+ 扩展点；见 `docs/dr-workflow/novel-writer-tool/final/spec/06-extensions.md`）：
     - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/query-foreshadow.sh`：
       - 执行（超时 10 秒）：`timeout 10 bash ${CLAUDE_PLUGIN_ROOT}/scripts/query-foreshadow.sh {C}`
       - 若退出码为 0 且 stdout 为合法 JSON 且 `.items` 为 list → `foreshadowing_tasks = .items`
       - 否则（脚本缺失/失败/输出非 JSON）→ 回退规则过滤（不得阻断流水线）
   - 规则过滤回退（确定性；详见 `references/foreshadowing.md`）：
     a. 读取并解析 global 与本卷计划 JSON（允许 schema 为 object.foreshadowing[]；缺失则视为空）。
     b. 选取候选（按 `id` 去重；输出按 `id` 升序）：
        - **计划命中**：本卷计划中满足以下任一条件的未回收条目：
          - `planted_chapter == C`（本章计划埋设）
          - `target_resolve_range` 覆盖 `C`（本章处于计划推进/回收窗口）
        - **事实命中**：global 中满足以下任一条件的未回收条目：
          - `target_resolve_range` 覆盖 `C`
          - `scope=="short"` 且 `target_resolve_range` 存在且 `C > target_resolve_range[1]`（超期 short）
     c. 合并字段（不覆盖事实）：
        - 若某 `id` 同时存在于 global 与 plan：以 global 为主，仅在 global 缺失时从 plan 回填 `description/scope/target_resolve_range`。
     d. 得到 `foreshadowing_tasks`（list；为空则 `[]`）。

#### Step 2.6: Agent Context Manifest 组装

按 Agent 类型组装 **context manifest**（内联计算值 + 文件路径），字段契约详见 `references/context-contracts.md`。

**Manifest 模式**：编排器不再读取文件全文注入 Task prompt，而是计算文件路径并传入 manifest。Subagent 在执行时用 Read 工具自行读取所需文件。

编排器仍需完成的**确定性计算**（作为 inline 字段直接写入 manifest）：
- `chapter_outline_block`：从 outline.md 提取的本章区块文本（Step 2.1 已完成）
- `hard_rules_list`：从 rules.json 筛选的禁止项列表（Step 2.2 已完成）
- `entity_id_map`：从角色 JSON 构建的 slug↔display_name 映射（Step 2.3 已完成）
- `foreshadowing_tasks`：跨文件聚合的伏笔子集（Step 2.5 已完成）
- `storyline_context` / `concurrent_state` / `transition_hint`：从 contract/schedule 解析（Step 2.5 已完成）
- `ai_blacklist_top10`：有效黑名单前 10 词（从 ai-blacklist.json 快速提取）
- `style_drift_directives`：从 style-drift.json 提取的纠偏指令列表（Step 2.7；仅 active=true 时）

编排器需完成的**路径计算**（作为 paths 字段写入 manifest）：
- 根据 Step 2.4 裁剪规则确定 `character_contracts[]` 和 `character_profiles[]` 的文件路径列表
- 根据 Step 2.5 注入策略确定 `storyline_memory` / `adjacent_memories[]` 的路径（过滤 dormant 线）
- 确定 `recent_summaries[]`（近 3 章摘要路径，按时间倒序）
- **QualityJudge `recent_summaries[]`（条件注入）**：当 chapter ≤ 3 且 platform_guide 存在时，注入近 2 章摘要路径供平台硬门回溯判定（Ch001 为空数组，Ch002 仅含 Ch001 摘要，Ch003 含 Ch001+002 摘要；路径指向文件不存在时跳过该条目）；章节 > 3 或无 platform_guide 时不注入此字段
- 其余路径为固定模式（如 `style-profile.json`、`ai-blacklist.json`）
- **平台指南加载**：读取 `style-profile.json` 的 `platform` 字段（缺失或 null 则终止并提示用户通过 `/novel:start` 设置平台，platform 为必填字段）。`platform` 为 `"general"` 时不加载 platform_guide（无对应模板文件），但 `platform` 值仍传入 QualityJudge manifest 供 Track 3 读者人设选择。其余平台值计算路径 `templates/platforms/{platform}.md`：文件存在则加入 `manifest.paths.platform_guide`（ChapterWriter + QualityJudge 均注入）；文件不存在则输出 WARNING（「平台指南 {platform}.md 不存在，跳过」）并继续（不阻断流水线）

关键原则：
- 同一输入 → 同一 manifest（确定性）
- 可选路径对应的文件不存在时，不加入 manifest（非 null）
- **不再使用 `<DATA>` 标签包裹**：subagent 自行读取文件，agent frontmatter 中的安全约束已覆盖注入防护

#### Step 2.7: M3 风格漂移与黑名单（文件协议）

定义 `style-drift.json`、`ai-blacklist.json` 扩展字段、`lint-blacklist.sh` 脚本接口。

详见 `references/file-protocols.md`。

### Step 3: 逐章流水线

对每一章执行以下 Agent 链：

```
for chapter_num in range(start, start + remaining_N):
  # remaining_N = N - (1 if inflight_chapter was recovered else 0)

  0. 获取并发锁（见 `docs/dr-workflow/novel-writer-tool/final/prd/10-protocols.md` §10.7）:
     - 原子获取：mkdir .novel.lock（已存在则失败）
     - 获取失败：
       - 读取 `.novel.lock/info.json` 报告持有者信息（pid/started/chapter）
       - 若 `started` 距当前时间 > 30 分钟，视为僵尸锁 → `rm -rf .novel.lock` 后重试一次
       - 否则提示用户存在并发执行，拒绝继续（避免 staging 写入冲突）
     - 写入 `.novel.lock/info.json`：`{"pid": <PID>, "started": "<ISO-8601>", "chapter": <N>}`
     更新 checkpoint: pipeline_stage = "drafting", inflight_chapter = chapter_num

  1. ChapterWriter Agent → 生成初稿 + 润色（Phase 1 + Phase 2）
     输入: chapter_writer_manifest（inline 计算值 + 文件路径；Agent 自行 Read 文件）
     输出: staging/chapters/chapter-{C:03d}.md（+ 可选 hints）+ staging/logs/style-refiner-chapter-{C:03d}-changes.json

  2. Summarizer Agent → 生成摘要 + 权威状态增量 + 串线检测
     输入: summarizer_manifest（inline 计算值 + 文件路径）
     输出: staging/summaries/chapter-{C:03d}-summary.md + staging/state/chapter-{C:03d}-delta.json + staging/state/chapter-{C:03d}-crossref.json + staging/storylines/{storyline_id}/memory.md
     更新 checkpoint: pipeline_stage = "drafted"

  3. QualityJudge Agent → 质量评估（Track 1+2+3 统一评估）
     （可选确定性工具）中文 NER 实体抽取（用于一致性/LS-001 辅助信号）：
       - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh`：
         - 执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh staging/chapters/chapter-{C:03d}.md`
         - 若退出码为 0 且 stdout 为合法 JSON → 记为 `ner_entities_json`，写入 quality_judge_manifest.ner_entities
       - 若脚本不存在/失败/输出非 JSON → `ner_entities_json = null`，不得阻断流水线（QualityJudge 回退 LLM 抽取 + confidence）
     （可选）注入最近一致性检查摘要（供 LS-001 参考，不直接替代正文判断）：
       - 若存在 `logs/continuity/latest.json`：
         - Read 并裁剪为小体积 JSON（仅保留 scope/chapter_range + 与 timeline/location 相关的 high/medium issues，最多 5 条，含 evidence）
         - 注入到 quality_judge_manifest.continuity_report_summary
       - 若文件不存在/读取失败/JSON 无效 → continuity_report_summary = null，不得阻断流水线
     （可选确定性工具）黑名单精确命中统计：
       - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh`：
         - 执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh staging/chapters/chapter-{C:03d}.md ai-blacklist.json`
         - 若退出码为 0 且 stdout 为合法 JSON → 记为 `blacklist_lint_json`，写入 quality_judge_manifest.blacklist_lint
       - 若脚本不存在/失败/输出非 JSON → `blacklist_lint_json = null`，不得阻断流水线（回退 LLM 估计）
     输入: quality_judge_manifest（inline 计算值 + 文件路径；cross_references 来自 staging/state/chapter-{C:03d}-crossref.json）
     输出: staging/evaluations/chapter-{C:03d}-eval-raw.json（QJ 直接落盘；含 overall_raw + overall_weighted（有 platform_guide 且含评估权重时）+ overall（= overall_weighted 或 overall_raw）+ platform_weights + reader_evaluation（Track 3 读者评估，可为 null））
     编排器读取 eval-raw.json 用于门控决策和双裁判合并，无需从 agent 文本输出中解析 JSON
     关键章双裁判:
       - 关键章判定：
         - 卷首章：chapter_num == chapter_start
         - 卷尾章：chapter_num == chapter_end
         - 交汇事件章：chapter_num 落在任一 storyline_schedule.convergence_events.chapter_range（含边界）内（若某 event 的 chapter_range 缺失或为 null，跳过该 event）
       - 若为关键章：使用 Task(subagent_type="quality-judge", model="opus") 再调用一次 QualityJudge 得到 secondary_eval
       - 最坏情况合并（用于门控）：
         - overall_final = min(primary_eval.overall, secondary_eval.overall)
         - has_high_confidence_violation = high_violation(primary_eval) OR high_violation(secondary_eval)
         - eval_used = overall 更低的一次（primary/secondary；若相等，优先使用 secondary_eval——更强模型的判断）
       - 记录：primary/secondary 的 model + overall + overall_raw + overall_weighted + eval_used + overall_final（写入 eval metadata 与 logs，便于回溯差异与成本）
     普通章：
       - overall_final = primary_eval.overall
       - has_high_confidence_violation = high_violation(primary_eval)
       - eval_used = primary_eval
     更新 checkpoint: pipeline_stage = "judged"

  5. 质量门控决策（Gate Decision Engine）:
     门控决策（详见 `references/gate-decision.md`）：
       - high-confidence violation → revise（强制修订）
       - 平台硬门任一 fail（章节 001-003 且有 platform_guide）→ revise（强制修订）
       - overall ≥ 4.0 且无上述硬门失败 → pass
       - overall ≥ 3.5 → polish（ChapterWriter Phase 2 二次润色）
       - overall ≥ 3.0 → revise（ChapterWriter Opus 修订，最多 2 轮）
       - overall ≥ 2.0 → pause_for_user（暂停，通知用户审核）
       - overall < 2.0 → pause_for_user_force_rewrite（强制重写，暂停）
       - 修订上限 2 次后 overall ≥ 3.0 且无 high violation 且无平台硬门 fail 且无 reader_evaluation 黄金三章硬门 fail（QJ 内部已处理） → force_passed
     QualityJudge 已内化 engagement overlay → 编排器直接映射 recommendation 到 gate_decision：
       - pass → pass, polish → polish, revise → revise, review → pause_for_user, rewrite → pause_for_user_force_rewrite

  6. 事务提交（staging → 正式目录）:
     - 移动 staging/chapters/chapter-{C:03d}.md → chapters/chapter-{C:03d}.md
     - 移动 staging/summaries/chapter-{C:03d}-summary.md → summaries/
     - 移动 staging/evaluations/chapter-{C:03d}-eval.json → evaluations/（含 reader_evaluation）
     - 移动 staging/storylines/{storyline_id}/memory.md → storylines/{storyline_id}/memory.md
     - 移动 staging/state/chapter-{C:03d}-crossref.json → state/chapter-{C:03d}-crossref.json（保留跨线泄漏审计数据）
     - 合并 state delta: 校验 ops（§10.6）→ 逐条应用 → state_version += 1 → 追加 state/changelog.jsonl
     - **Canon Status 升级**（基于 Summarizer canon_hints）：
       - 读取 `staging/state/chapter-{C:03d}-delta.json` 的顶层 `canon_hints` 字段（缺失则跳过整个升级步骤）
       - 对每条 hint（`{type, hint, confidence, evidence}`）：
         - 按 `type` 在对应源中搜索 `canon_status == "planned"` 的条目：
           - `type == "world_rule"` → 搜索 `world/rules.json` 的 `rules[]`，按 `hint` 与 `rule` 字段模糊匹配
           - `type == "ability" | "known_fact" | "relationship"` → 搜索 `characters/active/*.json` 对应数组，按 `hint` 与 `name`/`fact`/`target` 模糊匹配
         - 检查本章 `ops[]` 中是否存在与该 hint 关联的 `set`/`foreshadow` 操作（双条件：hint 匹配 + ops 关联证据）
         - 双条件均满足 → 升级：`canon_status: "planned" → "established"` + 更新 `last_verified: C`
         - 单条件或零条件 → 跳过（保持 planned）
       - 幂等：已 established 的条目跳过
       - 写回 `world/rules.json` / `characters/active/{slug_id}.json`
       - 记录每条升级操作到 `state/changelog.jsonl`（`{chapter, op: "canon_upgrade", target, from: "planned", to: "established"}`）
     - 更新 foreshadowing/global.json（从 foreshadow ops 提取；幂等合并，详见 `references/foreshadowing.md`）：
       - 读取 `staging/state/chapter-{C:03d}-delta.json`，筛选 `ops[]` 中 `op=="foreshadow"` 的记录
       - 读取 `foreshadowing/global.json`（不存在则初始化为 `{"foreshadowing":[]}`）
       - 读取（可选）`volumes/vol-{V:02d}/foreshadowing.json`（用于在 global 缺条目/缺元数据时回填 `description/scope/target_resolve_range`；不得覆盖既有事实字段）
       - 对每条 foreshadow op（按 ops 顺序）更新对应条目：
         - `history` 以 `{chapter:C, action:value}` 去重后追加 `{chapter, action, detail}`
         - `status` 单调推进（resolved > advanced > planted；不得降级）
         - `planted_chapter`/`planted_storyline` 仅在 planted/缺失时回填；`last_updated_chapter` 取 max
       - 写回 `foreshadowing/global.json`（JSON，UTF-8）
     - 处理 unknown_entities: 从 Summarizer 输出提取 unknown_entities，追加写入 logs/unknown-entities.jsonl；若累计 ≥ 3 个未注册实体，在本章输出中警告用户
     - 更新 .checkpoint.json（last_completed_chapter + 1, pipeline_stage = "committed", inflight_chapter = null, revision_count = 0）
     - 状态转移：
       - 若 chapter_num == chapter_end：更新 `.checkpoint.json.orchestrator_state = “VOL_REVIEW”` 并提示用户运行 `/novel:start` 执行卷末回顾
       - 否则：更新 `.checkpoint.json.orchestrator_state = “WRITING”`（若本章来自 CHAPTER_REWRITE，则回到 WRITING）
     - 写入 logs/chapter-{C:03d}-log.json（stages 耗时/模型、gate_decision、revisions、force_passed；关键章额外记录 primary/secondary judge 的 model+overall 与 overall_final；token/cost 为估算值或 null，见降级说明）
     - 清空 staging/ 本章文件（含 eval-raw.json 中间文件）
     - 释放并发锁: rm -rf .novel.lock

     - **Step 3.7: M3 周期性维护（非阻断，详见 `references/periodic-maintenance.md`）**
       - AI 黑名单动态维护：从 QualityJudge suggestions 读取候选 → 自动追加（confidence medium+high, count≥3, words<80）或记录候选
       - 风格漂移检测（每 5 章）：WorldBuilder（风格漂移检测模式）提取 metrics → 与基线对比 → 漂移则写入 style-drift.json / 回归则清除 / 超时(>15章)则 stale_timeout

  7. 输出本章结果:
     > 第 {C} 章已生成（{word_count} 字），评分 {overall_final}/5.0{有 platform 时追加「（{platform_display_name}适配分 {overall_weighted}）」}{eval.json 含 reader_evaluation 时追加「，读者参与度 {overall_engagement}/5.0」}，门控 {gate_decision}，修订 {revision_count} 次 {pass_icon}
```

### Step 4: 定期检查触发

- 每完成 5 章（last_completed_chapter % 5 == 0）：输出质量简报（均分 + 低分章节 + 主要风险）+ 风格漂移检测结果（是否生成/清除 style-drift.json），并提示用户可运行 `/novel:start` 进入“质量回顾/调整方向”
- 每完成 10 章（last_completed_chapter % 10 == 0）：触发周期性盘点提醒（建议运行 `/novel:start` → “质量回顾”，将生成：
  - 一致性报告：`logs/continuity/latest.json` 与 `logs/continuity/continuity-report-*.json`
  - 伏笔盘点与桥梁检查：`logs/foreshadowing/latest.json`、`logs/storylines/broken-bridges-latest.json`
  - 故事线节奏分析：`logs/storylines/rhythm-latest.json`）
- 到达本卷末尾章节：提示用户执行 `/novel:start` 进行卷末回顾

### Step 5: 汇总输出

多章模式下汇总：
```
续写完成：
Ch {X}: {字数}字 {分数} {状态} | Ch {X+1}: {字数}字 {分数} {状态} | ...
```

## 约束

- 每章严格按 ChapterWriter(含润色) → Summarizer → QualityJudge(含读者评估) 顺序
- 质量不达标时自动修订最多 2 次
- 写入使用 staging → commit 事务模式（详见 Step 2-6）
- **Agent 写入边界**：ChapterWriter/Summarizer 仅写入 `staging/` 目录，QualityJudge 仅写入 `staging/evaluations/chapter-{C:03d}-eval-raw.json`，正式目录（`chapters/`、`summaries/`、`state/`、`storylines/`、`evaluations/`）由入口 Skill 在 commit 阶段操作
- 所有输出使用中文
