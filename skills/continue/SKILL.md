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
- revision_scope: 当前修订的子流水线类型（"trivial" | "targeted" | "full" | null；用于中断恢复精确还原修订模式；缺失视为 "full"）
- failed_dimensions: 当前修订的失分维度列表（revision_scope="trivial"/"targeted" 时非空；缺失视为 []）
- failed_tracks: 当前修订的需复检 Track 列表（缺失视为 []）
- eval_backend: 评估后端（"codex" | "opus"；缺失视为 "codex"）
```

**版本检查**：若 `schema_version` 缺失或 < 2，输出 WARNING：`⚠️ 检测到旧版 checkpoint（schema_version={v}），建议通过 /novel:start 重建。` 不阻断续写，但在首次 commit 时自动补写 `schema_version: 2`。

**pipeline_stage 枚举及语义**：

| stage | 含义 | 恢复策略 |
|-------|------|----------|
| `null` / `committed` | 无中断，正常状态 | 从 `last_completed_chapter + 1` 开始 |
| `drafting` | API Writer / CW 执行中 | 检查 staging 文件决定从 API Writer/CW 或 SR 恢复 |
| `refining` | StyleRefiner 执行中 | 从 StyleRefiner 重启 |
| `refined` | StyleRefiner 完成 | 从 QualityJudge + ContentCritic 并行恢复；轻量修订（`revision_scope=="trivial"`）：直接 force_passed → Summarizer；定向修订（`revision_scope=="targeted"`）：从 [QJ ∥ CC] 并行恢复（检查输出存在性，仅重跑缺失） |
| `judged` | QJ + CC 完成 | 读取 eval-raw，执行门控决策；通过后从 Summarizer 恢复 |
| `summarized` | Summarizer 已完成（gate 通过后） | 从事务提交（commit）恢复 |
| `revising` | ChapterWriter 修订中 | 从 CW 重启（保留 revision_count + revision_scope + failed_dimensions + failed_tracks；revision_scope 缺失时降级为 "full"；trivial 恢复后跳过 QJ/CC 直接 force_passed） |
| `direct_fixing` | 定向修订耗尽后 Task agent 直接修复中 | 检查 staging chapter 是否已修改：已修改 → 从 SR(lite) 恢复；未修改 → 重跑 Task agent |

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

### Step 1.5–1.6: 中断恢复与错误处理

规则的权威来源为 [`references/checkpoint-recovery.md`](references/checkpoint-recovery.md)（Step 1.5 按 pipeline_stage 幂等恢复 + Step 1.6 ERROR_RETRY 重试策略）。

恢复章完成 commit 后，再继续从 `last_completed_chapter + 1` 续写后续章节，直到累计提交 N 章（包含恢复章）。

### Step 2: 组装 Context（脚本组装 + agent 审查 + 主控校验）

使用 Python 脚本完成确定性 manifest 组装（json.dumps 保证 JSON 序列化正确），再由 Task agent 审查输出，主控做结构校验。规则的权威来源为 [`references/context-assembly.md`](references/context-assembly.md)（Step 2.0-2.7）。

> 收益：消除 LLM 手工拼 JSON 导致的双引号转义错误；主控不再读取源文件，context 窗口占用 ~500 tokens。

**Step 2a: 脚本组装 + agent 审查**

派发 Task agent（通用类型，model="sonnet"）执行以下两步：

```
Task prompt：
  你是 context 组装审查器。先调脚本组装 manifest，再审查输出。

  ## 第一步：调脚本组装

  执行以下命令：
  bash: python3 ${CLAUDE_PLUGIN_ROOT}/scripts/assemble-manifests.py \
    -c {C} -v {V} -p {PROJECT_ROOT} \
    --eval-backend {eval_backend} \
    {--revision 'JSON字符串' 如果 revision_state 非 null}

  脚本输出 5 个 manifest JSON 到 staging/manifests/。
  若脚本以非 0 退出：报告 stderr 错误信息，不继续审查。

  ## 第二步：审查输出

  Read 每个 staging/manifests/chapter-{C:03d}-*.json，抽查：
  1. JSON 可解析（脚本用 json.dumps，理论上必定合法，但确认无误）
  2. chapter_outline_block 内容与 outline.md 对应区块一致
  3. storyline_id 与大纲/契约一致
  4. paths 中引用的文件存在（抽查 3-5 个关键路径）
  5. entity_id_map 角色名与 characters/active/ 一致
  6. hard_rules_list 条目数与 world/rules.json 中 hard+established 数量匹配
  7. 修订模式下，CW manifest 含 required_fixes / chapter_draft 字段

  发现问题 → 报告具体字段和期望值（不自己手动修 JSON）。
  全部通过 → 报告 "审查通过"。
```

> **修订回环复用**：gate_decision="revise" 时，重新派发 Step 2a 并传入 `revision_state`（作为 `--revision` JSON 参数），脚本自动在 CW manifest 追加修订字段。主控不需要自行 patch manifest。

**Step 2b: 主控校验**（manifest 结构校验，不读源文件）

```
for agent in [chapter-writer, style-refiner, summarizer, quality-judge, content-critic]:
  path = staging/manifests/chapter-{C:03d}-{agent}.json
  1. 文件存在 + JSON 可解析
  2. 必需字段：chapter (int), volume (int)
  3. CW/Sum: storyline_id (string) 非空
  4. CW/QJ/CC: chapter_outline_block (string) 非空
  5. CW/SR/QJ/CC: paths 对象存在且 paths.style_profile 文件存在
  6. Sum: entity_id_map 至少 1 条
```

校验任一失败 → 按 Step 1.6 错误处理。全部通过 → 进入 Step 3。

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
     执行：`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/api-writer.py staging/manifests/chapter-{C:03d}-chapter-writer.json --project <novel_project_root> --output staging/chapters/chapter-{C:03d}.md`
     若 API 调用失败（网络/超时/余额不足）→ 降级为 ChapterWriter Agent，传入 manifest 路径：`staging/manifests/chapter-{C:03d}-chapter-writer.json`（日志记录降级原因）
     输出: staging/chapters/chapter-{C:03d}.md
     更新 checkpoint: pipeline_stage = "refining"

  1.5. StyleRefiner Agent → 机械合规润色（去 AI 化）
     输入: manifest 文件 `staging/manifests/chapter-{C:03d}-style-refiner.json`（Agent 自行 Read）
     输出: staging/chapters/chapter-{C:03d}.md（覆写）+ staging/logs/style-refiner-chapter-{C:03d}-changes.json
     更新 checkpoint: pipeline_stage = "refined"

  2. QualityJudge + ContentCritic **并行**评估
     **预处理 — 草稿依赖字段补丁**（两个 Agent 共用，执行一次；在 SR 完成后、QJ/CC 调度前执行）：

     > manifest 仅含项目静态数据（路径 + 确定性计算值），不含草稿依赖的 lint/NER 结果。以下预处理在草稿产出后执行，将结果**原地 patch 到已有的 QJ manifest 文件**（`staging/manifests/chapter-{C:03d}-quality-judge.json`，JSON merge，不重新组装）。eval_backend="codex" 时 patch 后由 codex-eval.py 读取注入 task content。

     （可选确定性工具）中文 NER 实体抽取：
       - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh`：
         - 执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh staging/chapters/chapter-{C:03d}.md`
         - 若退出码为 0 且 stdout 为合法 JSON → patch 到 QJ manifest: `ner_entities = <json>`
       - 若脚本不存在/失败/输出非 JSON → 不 patch（字段保持缺失），不得阻断流水线
     （可选）注入最近一致性检查摘要：
       - 若存在 `logs/continuity/latest.json`：裁剪并 patch 到 QJ manifest: `continuity_report_summary = <trimmed>`
       - 否则 → 不 patch
     （可选确定性工具）黑名单精确命中统计：
       - 若存在 `${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh`：
         - 执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh staging/chapters/chapter-{C:03d}.md ai-blacklist.json`
         - 若退出码为 0 且 stdout 为合法 JSON → patch 到 QJ manifest: `blacklist_lint = <json>`
       - 否则 → 不 patch

     **执行流程**（Codex 优先，失败 fallback Opus Task agent）：
     3a. 组装 QJ + CC task content（并行）:
         `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py staging/manifests/chapter-{C:03d}-quality-judge.json --agent quality-judge --project <root>")`  ─┐ 并行
         `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py staging/manifests/chapter-{C:03d}-content-critic.json --agent content-critic --project <root>")` ─┘ 并行
     3b. 两个独立 codeagent-wrapper 并行执行:
         `Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-{C:03d}-quality-judge.md", timeout=3600000)`  ─┐ 并行
         `Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-{C:03d}-content-critic.md", timeout=3600000)` ─┘ 并行
     3c. 各自校验:
         `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema quality-judge --project <root> --chapter {C}")`
         `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema content-critic --project <root> --chapter {C}")`
         任一校验失败 → 重试一次（从 3b 重跑对应 agent）；二次失败 → 该 agent fallback
     **Codex 不可用 fallback**（逐 agent 独立 fallback，一个失败不影响另一个）：
     - QJ fallback: Task(subagent_type="quality-judge", model="opus")，传入 manifest 路径
     - CC fallback: Task(subagent_type="content-critic", model="opus")，传入 manifest 路径

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

  3. 质量门控决策（Gate Decision Engine）:
     门控决策合并 QJ + CC 结果（详见 `references/gate-decision.md`）：
       Step A — QJ 基础决策（Track 1+2）：
       - high-confidence violation → revise
       - 平台硬门任一 fail → revise
       - overall ≥ 4.0 → pass / ≥ 3.5 → polish / ≥ 3.0 → revise / ≥ 2.0 → pause_for_user / < 2.0 → pause_for_user_force_rewrite
       Step B — CC 内容实质性硬门（Track 4 + Track 5）：
       - 任一 substance 维度 < 3.0 → revise（不可跳过）
       - content_substance_overall < 2.0 → pause_for_user
       - pov_violation（含 cross_storyline_leak）→ revise
       Step C — CC 读者参与度 overlay（Track 3，只降级不升级）：
       - 黄金三章 engagement < 3.0 → revise
       - QJ pass + engagement < 2.5 → polish
       - QJ pass + engagement < 3.0 → warning（不降级）
       Step D — 合并取最严：gate_decision = max_severity(A, B, C)
       Step E — 计算 revision_scope + failed_dimensions + failed_tracks（详见 gate-decision.md §门控输出增强）
       修订上限兜底：轻量修订 1 轮直接 force_passed；定向修订 1 轮后未通过 → 直接修复模式（Task agent + SR，跳过 QJ/CC）+ force_passed；全量修订 2 轮后 overall ≥ 3.0 且无 high violation 且无硬门 fail 且无 substance_violation 且无黄金三章 engagement < 3.0 → force_passed

     **修订子流水线分支**（gate_decision="revise" 且可进入修订：trivial/定向 `revision_count < 1`，全量 `revision_count < 2`）：

     > **修订禁用 API Writer**：以下修订子流水线**必须**使用 ChapterWriter Agent，**不得**调用 API Writer。API Writer 仅用于上方 Step 1 的初始稿件生成。修订前先重新派发 manifest 组装器（传入 `revision_state`），获取含修订字段的 manifest 后再启动子流水线。

     3t. **revision_scope = "trivial"**（轻量修订，约 15-20K tokens）：
         适用：len(failed_dimensions) <= 1 且 len(failed_tracks) == 0 且 overall_final >= 3.5
         ```
         CW(targeted) → SR(lite) → force_passed
         ```
         **CW + SR 阶段**（串行，同 targeted 模式）：
         - CW manifest 追加: `revision_scope="trivial"` + `failed_dimensions` + `required_fixes`
         - SR manifest 追加: `lite_mode=true` + `paths.revision_diff`

         **SR 完成后**：
         - 跳过 QJ/CC 复检——单维度边缘失分 + 无 Track 级问题 + overall ≥ 3.5，修补必然小改动
         - 沿用上轮 eval，元数据追加 `trivial_fix: true` + `patched_dimensions: [<failed_dimensions>]`
         - 标记 `force_passed=true`，覆写 `gate_decision = "pass"` → Summarizer（Step 4）→ commit（Step 5）

     3a. **revision_scope = "targeted"**（定向修订，约 35-45K tokens）：
         适用：无 high_violation、无 platform_hard_gate_fail、无 substance_severe、overall_final ≥ 3.0（且不满足 trivial 条件）
         ```
         CW(targeted, failed_dimensions) → SR(lite, revision_diff) → [QJ(recheck) ∥ CC(recheck)]
         ```
         > 修订子流水线中 QJ/CC 的调度遵循 Step 2 相同的 Codex 优先 + fallback 逻辑。manifest 中追加的 recheck_mode 等字段通过 codex-eval.py 注入 task content。

         **CW + SR 阶段**（串行）：
         - CW manifest 追加: `revision_scope="targeted"` + `failed_dimensions` + `required_fixes`
         - CW 输出额外产物: `staging/logs/revision-diff-chapter-{C:03d}.json`（修改段落索引）
         - SR manifest 追加: `lite_mode=true` + `paths.revision_diff`

         **SR 完成后、并行前的 manifest 预处理**（同步执行，不涉及 LLM 调用）：
         - QJ manifest 追加: `recheck_mode=true` + `failed_dimensions` + `failed_tracks` + `paths.previous_eval` + `paths.revision_diff`
         - CC manifest 追加: `recheck_mode=true` + `failed_tracks` + `paths.previous_eval` + `paths.revision_diff`
         - Step 2 预处理（NER/黑名单 lint → patch 到 QJ manifest）：在修订后的章节上重新执行

         **QJ + CC 并行派发**（Codex 优先，逐 agent 独立 fallback）：
         - 两个 `codex-eval.py --agent` 组装（并行）→ 两个 `codeagent-wrapper`（并行）→ 各自 `--validate`
         - 任一 agent Codex 失败 → 该 agent fallback 到 Task(subagent_type=对应agent, model="opus")
         - Checkpoint：`pipeline_stage` 保持 `"refined"` 直到并行全部完成 → 更新为 `"judged"`

         **并行完成后**：
         - 验证两份输出均存在且可解析为合法 JSON（任一缺失/解析失败 → 按 Step 1.6 重试对应 agent）
         - **Escalation 处理**：若 QJ 或 CC 任一输出含 `recheck_escalated: true` → 丢弃 QJ+CC 输出（eval-raw + content-eval-raw），降级为 revision_scope="full"，从全量 [QJ + CC 并行] 重跑（不重跑 CW/SR，仅重跑评估）
         - 进入 Step 3 门控决策合并

     3b. **revision_scope = "full"**（全量修订，约 90K tokens）：
         适用：有 high_violation 或 platform_hard_gate_fail 或 substance_severe 或 overall_final < 3.0
         ```
         CW(revision) → SR → [QJ + CC 并行]
         ```

  4. Summarizer → 生成摘要 + 权威状态增量（仅 gate_decision in ["pass", "polish"] 时执行）
     > **Sum 在 gate 之后**：仅对通过质量门控的终稿生成摘要，避免对被拒章节浪费 token。修订子流水线（3a/3b）中不调用 Sum——修订后重新进入 Step 2 → Step 3 → gate，通过后才执行 Step 4。
     **执行流程**（Codex 优先，失败 fallback Opus Task agent）：
     4a. 组装 task content:
         `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py staging/manifests/chapter-{C:03d}-summarizer.json --agent summarizer --project <root>")`
     4b. Codex 执行:
         `Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-{C:03d}-summarizer.md", timeout=3600000)`
     4c. 校验 staging 输出:
         `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema summarizer --project <root> --chapter {C}")`
         校验失败 → 重试一次（从 4b 重跑）；二次失败 → fallback
     **Codex 不可用 fallback**：Task(subagent_type="summarizer", model="opus")，传入 manifest 路径
     输入: manifest 文件 `staging/manifests/chapter-{C:03d}-summarizer.json`（Agent/codex-eval.py 自行读取）
     输出: staging/summaries/chapter-{C:03d}-summary.md + staging/state/chapter-{C:03d}-delta.json + staging/storylines/{storyline_id}/memory.md
     更新 checkpoint: pipeline_stage = "summarized"

  5. 事务提交（staging → 正式目录）:
     - 移动 staging/chapters/chapter-{C:03d}.md → chapters/chapter-{C:03d}.md
     - 移动 staging/summaries/chapter-{C:03d}-summary.md → summaries/
     - 移动 staging/evaluations/chapter-{C:03d}-eval.json → evaluations/（含 eval_used + content_eval）
     - 移动 staging/storylines/{storyline_id}/memory.md → storylines/{storyline_id}/memory.md
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

     - **Step 5.1: M3 周期性维护（非阻断，详见 `references/periodic-maintenance.md`）**
       - AI 黑名单动态维护：从 QualityJudge suggestions 读取候选 → 自动追加（confidence medium+high, count≥3, words<80）或记录候选
       - 风格漂移检测（每 5 章）：WorldBuilder（风格漂移检测模式）提取 metrics → 与基线对比 → 漂移则写入 style-drift.json / 回归则清除 / 超时(>15章)则 stale_timeout

  6. 输出本章结果:
     > 第 {C} 章已生成（{word_count} 字），评分 {overall_final}/5.0{有 platform 时追加「（{platform_display_name}适配分 {overall_weighted}）」}{content_eval 含 reader_evaluation 时追加「，读者参与度 {overall_engagement}/5.0」}{content_eval 含 content_substance 时追加「，内容实质 {content_substance_overall}/5.0」}，门控 {gate_decision}，修订 {revision_count} 次 {pass_icon}

  7. **定期检查（循环内，每章提交后立即判定）**:
     - **滑窗一致性校验（每 5 章触发，窗口 10 章，步长 5）**：
       - 触发条件：`last_completed_chapter >= 10` 且 `last_completed_chapter % 5 == 0`
       - **Hook 强制触发**：`check-sliding-window.sh`（PreToolUse hook）在章节提交到 `chapters/` 时自动检测校验点，注入 systemMessage——编排器不得跳过
       - 窗口范围：`[max(1, last_completed_chapter - 9), last_completed_chapter]`（天然形成 ch1-10, ch6-15, ch11-20... 的重叠滑窗）

       **执行流程**（Codex 优先，失败 fallback Opus Task agent）：
       1. 组装滑窗 manifest（window 范围 + 章节/契约/大纲路径列表）
       2. 组装 task content:
          `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py sliding-window-manifest.json --agent sliding-window --project <root>")`
       3. Codex 执行（读取 10 章原文 + 契约 + 大纲，输出报告 JSON）:
          `Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/sliding-window.md", timeout=7200000)`
       4. 校验报告:
          `Bash("python3 ${CLAUDE_PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema sliding-window --project <root>")`
          校验失败 → 重试一次（从 3 重跑）；二次失败 → 进入 fallback
       5. 编排器读取 `staging/logs/continuity/continuity-report-*.json`
       6. 对 `auto_fixable == true` 的条目：使用 Edit 工具修改 `chapters/chapter-{fix_chapter:03d}.md`（定位 `current_text` → 替换为 `suggested_fix`）
       7. 不可自动修复的问题列出并提示用户
       8. 复制报告到正式目录: `logs/continuity/` + 覆盖 `latest.json`

       **Codex 不可用时 fallback**（codeagent-wrapper 不存在 / 执行失败 / 校验二次失败）：
       - 输出 WARNING：`⚠️ Codex 滑窗校验失败，fallback 到 Opus Task agent`
       - 使用 Opus Task agent 执行同等检查：
         1. 读取窗口内所有章节原文 + 大纲区块 + 章节契约
         2. 正文↔契约/大纲对齐检查 + 跨章连续性检查
         3. 可选辅助：NER 实体抽取（`scripts/run-ner.sh`）
         4. 报告落盘 + 自动修复（同 Codex 路径 5-8 步）

       **约束**：
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

- 每章严格按 API Writer（降级 CW）→ StyleRefiner → [QualityJudge + ContentCritic 并行] → Gate → Summarizer（仅通过时） 顺序
- 质量不达标时自动修订（定向修订 1 轮 + 直接修复兜底；全量修订最多 2 轮）
- 写入使用 staging → commit 事务模式（详见 Step 2-6）
- **Agent 写入边界**：ChapterWriter/StyleRefiner/Summarizer 仅写入 `staging/` 目录，QualityJudge 仅写入 `staging/evaluations/chapter-{C:03d}-eval-raw.json`，ContentCritic 仅写入 `staging/evaluations/chapter-{C:03d}-content-eval-raw.json`，正式目录由入口 Skill 在 commit 阶段操作。Summarizer 在 gate 后执行，仅对终稿生成摘要
- 所有输出使用中文
