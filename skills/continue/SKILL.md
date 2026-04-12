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
- schema_version: checkpoint 格式版本（当前为 2；缺失视为 1）
- current_volume: 当前卷号
- last_completed_chapter: 上次完成的章节号
- orchestrator_state: 当前状态（必须为 WRITING 或 CHAPTER_REWRITE，否则提示用户先通过 /novel:start 完成规划）
- pipeline_stage: 流水线阶段（用于中断恢复；枚举见下方）
- inflight_chapter: 当前处理中断的章节号（用于中断恢复）
- revision_count: 当前 inflight_chapter 的修订计数（用于限制修订循环；默认 0）
```

**版本检查**：若 `schema_version` 缺失或 < 2，输出 WARNING：`⚠️ 检测到旧版 checkpoint（schema_version={v}），建议通过 /novel:start 重建。` 不阻断续写，但在首次 commit 时自动补写 `schema_version: 2`。

**pipeline_stage 枚举及语义**：

| stage | 含义 | 恢复策略 |
|-------|------|----------|
| `null` / `committed` | 无中断，正常状态 | 从 `last_completed_chapter + 1` 开始 |
| `drafting` | API Writer / CW 执行中 | 检查 staging 文件决定从 API Writer/CW 或 SR 恢复 |
| `refining` | StyleRefiner 执行中 | 从 StyleRefiner 重启 |
| `refined` | StyleRefiner 完成 | 从 Summarizer 恢复 |
| `drafted` | Summarizer 已完成 | 从 QualityJudge + ContentCritic 并行恢复 |
| `judged` | QualityJudge + ContentCritic 均已完成 | 读 eval-raw + content-eval-raw 执行门控+commit |
| `revising` | ChapterWriter 修订中 | 从 CW 重启（保留 revision_count） |

如果 `orchestrator_state` 既不是 `WRITING` 也不是 `CHAPTER_REWRITE`，输出提示并终止：
> 当前状态为 {state}，请先执行 `/novel:start` 完成项目初始化或卷规划。

**Spec 传播检查**：若 `.checkpoint.json.pending_actions[]` 存在且含 `type == "spec_propagation"` 的条目：
- 输出 WARNING：`⚠️ 检测到未传播的设定变更（{pending_actions.length} 项），受影响章节契约可能与最新世界规则/角色能力不一致。建议先执行 /novel:start → "卷规划" 传播变更。`
- 列出每项 pending_action 的摘要（affected_chapters + change_type）
- **不阻断**续写（用户可选择忽略），但每次 `/novel:continue` 启动时都重复提醒，直到 pending_actions 被消费

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
  - 若 `staging/chapters/chapter-{C:03d}.md` 不存在 → 从 API Writer 重启整章（降级 CW）
  - 若 `staging/chapters/chapter-{C:03d}.md` 已存在且 `staging/logs/style-refiner-chapter-{C:03d}-changes.json` 不存在 → 从 StyleRefiner 恢复
  - 若两者均存在 → 从 Summarizer 恢复
- `pipeline_stage == "refining"`：
  - 若 `staging/logs/style-refiner-chapter-{C:03d}-changes.json` 不存在 → 从 StyleRefiner 重启
  - 若已存在 → 从 Summarizer 恢复
- `pipeline_stage == "refined"` → 从 Summarizer 恢复
- `pipeline_stage == "drafted"` → 跳过 ChapterWriter/StyleRefiner/Summarizer，从 QualityJudge 恢复
- `pipeline_stage == "judged"` → 读取 `staging/evaluations/chapter-{C:03d}-eval-raw.json`（QJ）和 `staging/evaluations/chapter-{C:03d}-content-eval-raw.json`（CC），直接执行门控决策 + commit 阶段；任一文件不存在或 JSON 无效 → 降级到 `pipeline_stage == "drafted"`（从 QJ+CC 重新评估）
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

按确定性规则组装 agent manifest。完整计算规则见 [`references/context-assembly.md`](references/context-assembly.md)（Step 2.0-2.7）。

> 原则：同一章 + 同一项目文件输入 → 组装结果唯一；缺关键文件/解析失败 → 立即停止并给出可执行修复建议。

主要步骤：
1. **2.1** 从 outline.md 提取本章大纲区块 + 章节边界（chapter_start/chapter_end）
2. **2.2** 从 rules.json 筛选 hard_rules_list 禁止项
3. **2.3** 从角色 JSON 构建 entity_id_map
4. **2.4** L2 角色契约裁剪（canon_status 预过滤 + recency 排序）
5. **2.5** storylines context + memory + foreshadowing 聚合
6. **2.6** 按 Agent 类型组装 manifest（inline 计算值 + 路径；含 `track3_mode` 判定）
7. **2.7** 风格漂移与黑名单文件协议（详见 `references/file-protocols.md`）

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

  1. API Writer → 生成初稿（纯净环境调用，绕过 Claude Code 系统提示词）
     1a. 将 chapter_writer_manifest 写入 staging/manifests/chapter-{C:03d}-manifest.json
     1b. 执行：`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/api-writer.py staging/manifests/chapter-{C:03d}-manifest.json --project <novel_project_root> --output staging/chapters/chapter-{C:03d}.md`
     1c. 若 API 调用失败（网络/超时/余额不足）→ 降级为 ChapterWriter Agent 执行（日志记录降级原因）
     输出: staging/chapters/chapter-{C:03d}.md
     更新 checkpoint: pipeline_stage = "refining"

  1.5. StyleRefiner Agent → 机械合规润色（去 AI 化）
     输入: style_refiner_manifest（paths: chapter_draft + style_samples + style_profile + ai_blacklist + style_guide + style_drift；inline: style_drift_directives）
     输出: staging/chapters/chapter-{C:03d}.md（覆写）+ staging/logs/style-refiner-chapter-{C:03d}-changes.json
     更新 checkpoint: pipeline_stage = "refined"

  2. Summarizer Agent → 生成摘要 + 权威状态增量 + 串线检测
     输入: summarizer_manifest（inline 计算值 + 文件路径）
     输出: staging/summaries/chapter-{C:03d}-summary.md + staging/state/chapter-{C:03d}-delta.json + staging/state/chapter-{C:03d}-crossref.json + staging/storylines/{storyline_id}/memory.md
     更新 checkpoint: pipeline_stage = "drafted"

  3. QualityJudge + ContentCritic **并行**评估
     **预处理**（两个 Agent 共用，执行一次）：
     （可选确定性工具）中文 NER 实体抽取：
       - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh`：
         - 执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh staging/chapters/chapter-{C:03d}.md`
         - 若退出码为 0 且 stdout 为合法 JSON → 记为 `ner_entities_json`，写入 quality_judge_manifest.ner_entities
       - 若脚本不存在/失败/输出非 JSON → `ner_entities_json = null`，不得阻断流水线
     （可选）注入最近一致性检查摘要：
       - 若存在 `logs/continuity/latest.json`：裁剪并注入 quality_judge_manifest.continuity_report_summary
       - 否则 → null
     （可选确定性工具）黑名单精确命中统计：
       - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh`：
         - 执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh staging/chapters/chapter-{C:03d}.md ai-blacklist.json`
         - 若退出码为 0 且 stdout 为合法 JSON → 写入 quality_judge_manifest.blacklist_lint
       - 否则 → null

     **并行派发**（两个 Task 同时发起）：
     3a. QualityJudge Agent → Track 1 合规 + Track 2 评分
         输入: quality_judge_manifest（inline 计算值 + 文件路径）
         输出: staging/evaluations/chapter-{C:03d}-eval-raw.json
     3b. ContentCritic Agent → Track 3 读者参与度 + Track 4 内容实质性
         输入: content_critic_manifest（inline 计算值 + 文件路径；track3_mode 由 context-assembly 2.6 判定）
         输出: staging/evaluations/chapter-{C:03d}-content-eval-raw.json

     **并行完成后**：
     编排器验证两份 eval-raw 文件均存在且可解析为合法 JSON；任一不存在或解析失败 → 按 Step 1.6 错误处理流程重试对应 Agent
     编排器读取两份 eval-raw 用于门控决策合并

     **关键章双裁判**（仅对 QualityJudge，ContentCritic 不需双裁判）:
       - 关键章判定：
         - 卷首章：chapter_num == chapter_start
         - 卷尾章：chapter_num == chapter_end
         - 交汇事件章：chapter_num 落在任一 storyline_schedule.convergence_events.chapter_range 内
         - **退化规则**：若无 convergence_events，每 10 章首章（`chapter_num % 10 == 1` 且非卷首章）视为关键章
       - 若为关键章：使用 Task(subagent_type="quality-judge", model="opus") 再调用一次 QualityJudge 得到 secondary_eval
       - 最坏情况合并：overall_final = min(primary.overall, secondary.overall)；has_high_confidence_violation = primary OR secondary
       - eval_used = overall 更低的一次（相等时优先 secondary）
     普通章：overall_final = primary_eval.overall；eval_used = primary_eval
     更新 checkpoint: pipeline_stage = "judged"

  5. 质量门控决策（Gate Decision Engine）:
     门控决策合并 QJ + CC 结果（详见 `references/gate-decision.md`）：
       Step A — QJ 基础决策（Track 1+2）：
       - high-confidence violation → revise
       - 平台硬门任一 fail → revise
       - overall ≥ 4.0 → pass / ≥ 3.5 → polish / ≥ 3.0 → revise / ≥ 2.0 → pause_for_user / < 2.0 → pause_for_user_force_rewrite
       Step B — CC 内容实质性硬门（Track 4）：
       - 任一 substance 维度 < 3.0 → revise（不可跳过）
       - content_substance_overall < 2.0 → pause_for_user
       Step C — CC 读者参与度 overlay（Track 3，只降级不升级）：
       - 黄金三章 engagement < 3.0 → revise
       - QJ pass + engagement < 2.5 → polish
       - QJ pass + engagement < 3.0 → warning（不降级）
       Step D — 合并取最严：gate_decision = max_severity(A, B, C)
       修订上限兜底：2 次后 overall ≥ 3.0 且无 high violation 且无硬门 fail 且无 substance_violation 且无黄金三章 engagement < 3.0 → force_passed

  6. 事务提交（staging → 正式目录）:
     - 移动 staging/chapters/chapter-{C:03d}.md → chapters/chapter-{C:03d}.md
     - 移动 staging/summaries/chapter-{C:03d}-summary.md → summaries/
     - 移动 staging/evaluations/chapter-{C:03d}-eval.json → evaluations/（含 eval_used + content_eval）
     - 移动 staging/storylines/{storyline_id}/memory.md → storylines/{storyline_id}/memory.md
     - 移动 staging/state/chapter-{C:03d}-crossref.json → state/chapter-{C:03d}-crossref.json（保留跨线泄漏审计数据）
     - 合并 state delta: 校验 ops（§10.6）→ 逐条应用 → state_version += 1 → 追加 state/changelog.jsonl
     - **Canon Status 升级**（基于 Summarizer canon_hints）：
       - 读取 `staging/state/chapter-{C:03d}-delta.json` 的顶层 `canon_hints` 字段（必须存在；缺失时输出 WARNING `"Summarizer 未输出 canon_hints 字段，planned→established 升级被跳过"` 并跳过升级步骤）
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
       - 若 chapter_num == chapter_end：更新 `.checkpoint.json.orchestrator_state = “VOL_REVIEW”` 并提示用户运行 `/novel:start` 进行 State 清理和下卷规划（卷末核心检查已由 Step 8 自动完成）
       - 否则：更新 `.checkpoint.json.orchestrator_state = “WRITING”`（若本章来自 CHAPTER_REWRITE，则回到 WRITING）
     - 写入 logs/chapter-{C:03d}-log.json（stages 耗时/模型、gate_decision、revisions、force_passed；关键章额外记录 primary/secondary judge 的 model+overall 与 overall_final；token/cost 为估算值或 null，见降级说明）
     - 清空 staging/ 本章文件（含 eval-raw.json 中间文件）
     - 释放并发锁: rm -rf .novel.lock

     - **Step 3.7: M3 周期性维护（非阻断，详见 `references/periodic-maintenance.md`）**
       - AI 黑名单动态维护：从 QualityJudge suggestions 读取候选 → 自动追加（confidence medium+high, count≥3, words<80）或记录候选
       - 风格漂移检测（每 5 章）：WorldBuilder（风格漂移检测模式）提取 metrics → 与基线对比 → 漂移则写入 style-drift.json / 回归则清除 / 超时(>15章)则 stale_timeout

  7. 输出本章结果:
     > 第 {C} 章已生成（{word_count} 字），评分 {overall_final}/5.0{有 platform 时追加「（{platform_display_name}适配分 {overall_weighted}）」}{content_eval 含 reader_evaluation 时追加「，读者参与度 {overall_engagement}/5.0」}{content_eval 含 content_substance 时追加「，内容实质 {content_substance_overall}/5.0」}，门控 {gate_decision}，修订 {revision_count} 次 {pass_icon}

  8. **定期检查（循环内，每章提交后立即判定）**:
     - **滑窗一致性校验（每 5 章触发，窗口 10 章，步长 5）**：
       - 触发条件：`last_completed_chapter >= 10` 且 `last_completed_chapter % 5 == 0`
       - **Hook 强制触发**：`check-sliding-window.sh`（PreToolUse hook）在章节提交到 `chapters/` 时自动检测校验点，注入 systemMessage——编排器不得跳过
       - 窗口范围：`[max(1, last_completed_chapter - 9), last_completed_chapter]`（天然形成 ch1-10, ch6-15, ch11-20... 的重叠滑窗）
       - **执行流程**（agent 驱动，读原文而非摘要/评估文件）：
         1. 读取窗口内所有章节**原文**（`chapters/chapter-{C:03d}.md`）+ 对应**大纲区块**（`volumes/vol-{V:02d}/outline.md` 中 `### 第 N 章` 段落）+ 对应**章节契约**（`volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.md`）
         2. **正文↔契约/大纲对齐检查**（逐章）：
            - 契约「事件」section 描述的核心事件是否在正文中完整呈现
            - 契约「冲突与抉择」的冲突/抉择/赌注是否在正文中有对应情节
            - 契约「局势变化」表的章末状态是否与正文实际演进一致
            - 契约「验收标准」各条是否满足
            - 大纲 Storyline/POV/Location 是否与正文匹配
            - 大纲 Foreshadowing 指定的伏笔动作是否在正文中体现
         3. **跨章连续性检查**：角色位置/状态连续性、时间线矛盾、世界规则合规性、伏笔推进一致性、跨线信息泄漏
         4. 可选辅助：NER 实体抽取（`scripts/run-ner.sh`，脚本优先，LLM fallback）
         5. 报告落盘：`logs/continuity/continuity-report-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json` + 覆盖 `logs/continuity/latest.json`
       - **自动修复**：对可修复问题（事实性矛盾、连续性断裂、角色状态不一致、正文偏离契约/大纲）直接编辑受影响章节原文；不可自动修复的问题（剧情逻辑矛盾、需调整契约/大纲等）列出并提示用户
       - **阻断流水线**：校验 + 修复完成前不得继续下一章
       - 输出简报：issues_total + 已修复数 + 未修复高严重级 + LS-001 高置信提示
     - **质量简报（每 5 章触发）**：`last_completed_chapter % 5 == 0` 时输出近 5 章均分 + 低分章节 + 风格漂移检测结果
     - **伏笔盘点 + 跨线桥梁检查（每 10 章触发）**：`last_completed_chapter >= 10` 且 `last_completed_chapter % 10 == 0` 时自动执行（流程与 `quality-review.md` Step 4 一致），报告落盘到 `logs/foreshadowing/` + `logs/storylines/`
     - **故事线节奏分析（每 10 章触发）**：与伏笔盘点同步触发（流程与 `quality-review.md` Step 5 一致），报告落盘到 `logs/storylines/rhythm-*.json`
     - **Track 3 补全检测（每 10 章触发）**：`last_completed_chapter % 10 == 0` 时扫描近 10 章 `evaluations/chapter-*-eval.json`，筛选 `content_eval.reader_evaluation == null` 的章节；若存在，输出列表并提示用户可运行 `/novel:start → 质量回顾` 补全（不阻断续写）
     - **卷末自动回顾**：到达本卷末尾章节（`chapter_num == chapter_end`）时，**自动执行**以下核心检查（不只是提醒）：
       - 全卷 NER 一致性报告（流程与 `vol-review.md` Step 2 一致），落盘到 `volumes/vol-{V:02d}/continuity-report.json` + `logs/continuity/latest.json`
       - 伏笔盘点 + 桥梁检查 + 故事线节奏分析（流程与 `vol-review.md` Step 3 一致），落盘到 `volumes/vol-{V:02d}/` 对应文件
       - 输出卷末简报：一致性 issues + 未回收伏笔 + 桥梁断链 + 故事线休眠/交汇达成率
       - **不自动执行**的部分（仍需用户手动 `/novel:start → 卷末回顾`）：State 清理（需用户确认）、review.md 生成、下卷方向选择
       - 提示用户："卷末核心检查已自动完成，建议运行 `/novel:start` 进行 State 清理和下卷规划"
```

### Step 4: 汇总输出

多章模式下汇总：
```
续写完成：
Ch {X}: {字数}字 {分数} {状态} | Ch {X+1}: {字数}字 {分数} {状态} | ...
```

## 约束

- 每章严格按 API Writer（降级 CW）→ StyleRefiner → Summarizer → [QualityJudge + ContentCritic 并行] 顺序
- 质量不达标时自动修订最多 2 次
- 写入使用 staging → commit 事务模式（详见 Step 2-6）
- **Agent 写入边界**：ChapterWriter/StyleRefiner/Summarizer 仅写入 `staging/` 目录，QualityJudge 仅写入 `staging/evaluations/chapter-{C:03d}-eval-raw.json`，ContentCritic 仅写入 `staging/evaluations/chapter-{C:03d}-content-eval-raw.json`，正式目录由入口 Skill 在 commit 阶段操作
- 所有输出使用中文
