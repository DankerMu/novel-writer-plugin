# 快速起步工作流（创建新项目 + 黄金三章试写）

> 本文档定义 `/novel:start` 在 INIT/QUICK_START 状态下的完整执行流程。

##### Step A: 收集最少输入（1 轮交互）

> **时间预期**：完整 Quick Start（设定 + 风格 + 黄金三章试写）约需 **50 分钟**。系统将为前 3 章（黄金三章）生成生产级质量的正文，包含完整的 L3 合约检查和质量门控。

使用 **1 次** AskUserQuestion 收集基本信息。题材用选项（玄幻/都市/科幻/历史/悬疑），主角概念和核心冲突由用户自由输入：

1. **题材**（选项：玄幻 / 都市 / 科幻 / 历史 / 悬疑）
2. **主角概念**（自由输入：一句话描述谁 + 起始处境）
3. **核心冲突**（自由输入：一句话描述主角要克服什么）

> Step A 允许自由输入，是 2-4 选项约束的特例：此处收集创意信息，无法用预设选项穷尽。

##### Step A.5: 研究资料建议（条件触发）

收集完输入后，判断是否建议先做背景研究：

- **触发条件**：题材 ∈ {历史, 科幻, 军事} 或主角/冲突描述中涉及专业领域（医学、法律、古代制度等）
- **触发时**：使用 AskUserQuestion 提示：



- 选项 2 时：提示用户执行 `/doc-workflow`（或等效的 deep-research 流程），完成后再回来 `/novel:start` 继续
- **不触发时**（玄幻、都市、悬疑等通用题材）：跳过此步，直接进入 Step B

##### Step B: 风格来源（1 轮交互）

使用 AskUserQuestion 询问风格来源（2-4 选项）：



根据用户选择，设置 `source_type` 并**立即收集该路径所需信息**：
- 选项 1 → `source_type: "original"`，追问用户粘贴 1-3 章样本文本（存入临时变量，Step E 传给 StyleAnalyzer）
- 选项 2 → `source_type: "reference"`，追问用户输入参考作者名（如"远瞳"、"猫腻"），存入 `reference_author` 变量
- 选项 3 → `source_type: "template"`，展示预置模板列表让用户选择，存入 `style_template_id`
- 选项 4 → `source_type: "write_then_extract"`（先跳过 StyleAnalyzer，试写后回填）

**平台偏好采集**（在 Step B 内完成，不延迟到后续步骤）：

风格来源选择完成后，使用 AskUserQuestion 询问目标平台：



- 选项 1 → `platform = "fanqie"`
- 选项 2 → `platform = "qidian"`
- 选项 3 → `platform = "jinjiang"`
- 选项 4 → `platform = null`
- Other（用户输入自定义字符串）→ `platform = 该字符串`（如 `"zongheng"`，系统将尝试加载 `templates/platforms/{platform}.md`；文件不存在时 WARNING 并跳过）

`platform` 值在 Step C 写入 `style-profile.json` 的 `platform` 字段。

> 关键：每条路径的补充信息必须在 Step B 内收齐，不得延迟到 Step E 再问。Step E 仅执行 StyleAnalyzer 派发，不再与用户交互。

##### Step B.5: Brief 交互完善（1-2 轮交互）

用 Step A/B 已收集的信息预填 `brief-template.md`，**将预填结果展示给用户**并请求补充：

1. **自动填充字段**（从已收集信息推导）：
   - `genre` ← Step A 题材
   - `core_conflict` ← Step A 核心冲突
   - `protagonist_identity` ← Step A 主角概念
   - `style_source` ← Step B source_type
   - `reference_works` ← Step B reference_author（若有）

2. **使用 AskUserQuestion 请求用户补充关键字段**（1 轮，允许自由输入）：
   - **书名**（可留空让系统生成）
   - **基调**（轻松幽默 / 热血燃向 / 暗黑压抑 / 细腻温暖 / Other）
   - **节奏**（快节奏爽文 / 慢热型 / 张弛交替 / Other）

3. **展示预填 brief 预览**，询问用户确认或修改：

   选项 2 时进入自由输入修改轮，用户可补充书名、目标字数、读者画像等任意字段。

> Brief 是整个创作流水线的基础输入。未经用户确认的 brief 不得传入后续 Agent。

##### Step C: 初始化项目结构

1. 创建项目目录结构（参考 `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md` §9.1）
2. 从 `${CLAUDE_PLUGIN_ROOT}/templates/` 复制模板文件到项目目录（至少生成以下文件）：
   - `brief.md`：从 `brief-template.md` 复制并用用户输入填充占位符
   - `style-profile.json`：从 `style-profile-template.json` 复制（后续由 StyleAnalyzer 填充）。若 Step B 采集了 `platform` 值（非 null），立即写入 `style-profile.json` 的 `platform` 字段
   - `ai-blacklist.json`：从 `ai-blacklist.json` 复制
3. **初始化最小可运行文件**（模板复制后立即创建，确保后续 Agent 可正常读取）：
   - `.checkpoint.json`：`{"last_completed_chapter": 0, "current_volume": 0, "orchestrator_state": "QUICK_START", "pipeline_stage": null, "inflight_chapter": null, "quick_start_step": "C", "revision_count": 0, "pending_actions": [], "last_checkpoint_time": "<now>"}`
   - `state/current-state.json`：`{"schema_version": 1, "state_version": 0, "last_updated_chapter": 0, "characters": {}, "world_state": {}, "active_foreshadowing": []}`
   - `foreshadowing/global.json`：`{"foreshadowing": []}`
   - `storylines/storyline-spec.json`：`{"spec_version": 1, "rules": []}` （WorldBuilder 初始化后由入口 Skill 填充默认 LS-001~005）
   - `storylines/storylines.json`：`{"storylines": [], "relationships": [], "storyline_types": ["type:main_arc", "type:faction_conflict", "type:conspiracy", "type:mystery", "type:character_arc", "type:parallel_timeline"]}` （WorldBuilder 在 Step D 填充具体故事线）
   - 创建空目录：`staging/chapters/`、`staging/summaries/`、`staging/state/`、`staging/storylines/`、`staging/evaluations/`、`staging/foreshadowing/`、`chapters/`、`summaries/`、`evaluations/`、`logs/`

##### Step D: 世界观 + 角色 + 故事线

4. 使用 Task 派发 WorldBuilder Agent（**轻量模式**）：仅输出 ≤3 条核心 L1 hard 规则 + 精简叙述文档
5. 使用 Task 派发 CharacterWeaver Agent 创建主角和核心配角（≤3 个角色）
6. WorldBuilder 协助初始化 `storylines/storylines.json`（默认仅 1 条 `type:main_arc` 主线，不创建额外故事线）
6.5. **研究资料建议检查**：若 WorldBuilder 输出了 `world/research-suggestions.json`，展示建议列表并提示：

   选项 2 时提示用户执行研究流程，完成后 `/novel:start` 回来继续（checkpoint 已保存进度）
7. 更新 `.checkpoint.json`：`quick_start_step = "D"`

##### Step E: 风格提取（或跳过）

8. **按 Step B 选择的路径执行**（所需信息已在 Step B 收集完毕，此处**不再与用户交互**，直接派发 Agent）：
   - `original`：用 Step B 收集的样本文本 → 派发 StyleAnalyzer（原创分析模式）
   - `reference`：用 Step B 收集的 `reference_author` → 派发 StyleAnalyzer（仿写模式）
   - `template`：用 Step B 收集的 `style_template_id` → 派发 StyleAnalyzer（模板模式）
   - `write_then_extract`：跳过此步，使用默认 style-profile（`source_type: "write_then_extract"`，`writing_directives` 为空，统计字段为 null）。ChapterWriter 遇到 null 字段时应基于 brief 中的题材使用体裁默认值（如玄幻：`avg_sentence_length: 18, dialogue_ratio: 0.35, narrative_voice: "第三人称限制"`）
9. 更新 `.checkpoint.json`：`quick_start_step = "E"`

##### Step F0: 迷你卷规划（黄金三章 L3 合约）

> 为前 3 章生成结构化的大纲、L3 章节契约、伏笔计划和故事线调度，使试写章节获得与正式写作相同的 Spec-Driven 支撑。

9a. **创建 vol-01 目录**（幂等）：`mkdir -p volumes/vol-01/chapter-contracts staging/volumes/vol-01/chapter-contracts`

9b. **Genre × Platform 组合检查**（非阻塞）：
   - 从 `brief.md` 读取 `genre`，从 `style-profile.json` 读取 `platform` 字段，若 `platform` 非空则检查 `templates/platforms/{platform}.md` 是否存在
   - 按以下 WARNING 表检查（参考 `skills/novel-writing/references/golden-chapter-criteria.md` § Genre × Platform 无效/少见组合）：
     - 无效组合：`纯爱BL + 番茄` → WARNING "纯爱BL 在番茄平台不可发布，请确认平台选择"
     - 少见组合：`硬科幻 + 晋江` / `硬核玄幻 + 晋江` / `言情 + 起点` → WARNING 建议确认目标受众
   - WARNING 输出到用户但不阻塞流程
   - 无 platform_guide → 跳过此检查

9c. **组装 PlotArchitect mini context**：
   - `volume_plan`: `{"volume": 1, "chapter_range": [1, 3]}`
   - `mode`: `"mini"`（标识迷你卷规划模式，PlotArchitect 据此精简输出）
   - `brief`: 读取 `brief.md`
   - `world_rules`: 读取 `world/rules.json`（若存在）
   - `characters`: 传入 `characters/active/*.json` + `characters/active/*.md` 路径列表（PlotArchitect 按需 Read）
   - `style_profile`: 读取 `style-profile.json`（PlotArchitect 据此感知快/慢节奏偏好）
   - `platform_guide`: 读取 platform_guide 文件路径（若存在）。PlotArchitect 读取其 `## 黄金三章参数` section 获取平台差异化参数（章节字数、钩子密度、主角登场时限等）
   - `storylines`: 读取 `storylines/storylines.json`
   - `foreshadowing`: 读取 `foreshadowing/global.json`
   - **不传入** `prev_volume_review`（首卷无前卷）
   - **不传入** `prev_chapter_summaries`（尚无已完成章节）
   - **平台缺省处理**：若无 `platform_guide`，PlotArchitect 使用默认参数：2500-3500 字/章、每 800 字 1 个钩子、主角 300 字内登场、金手指前 3 章内出现

9d. **派发 PlotArchitect Agent**（Task, subagent_type="plot-architect"）：
   - 输出写入 staging 目录：
     - `staging/volumes/vol-01/outline.md`（仅 3 章，`### 第 1 章` ~ `### 第 3 章`）
     - `staging/volumes/vol-01/chapter-contracts/chapter-001.json` ~ `chapter-003.json`（含 `excitement_type`）
     - `staging/volumes/vol-01/foreshadowing.json`（初始伏笔计划）
     - `staging/volumes/vol-01/storyline-schedule.json`（初始故事线调度，仅主线）

9e. **校验 PlotArchitect 产物**（复用 `references/vol-planning.md` Step 4 校验规则的子集）：
   - `outline.md` 可解析：3 个 `### 第 N 章` 区块，连续覆盖 1-3
   - 每个区块含 8 个固定 key 行（Storyline/POV/Location/Conflict/Arc/Foreshadowing/StateChanges/TransitionHint）
   - `chapter-contracts/` 3 个文件均可解析，`chapter == C`、`storyline_id` 与 outline 一致、`objectives` 至少 1 条 `required: true`
   - `foreshadowing.json` 和 `storyline-schedule.json` 为合法 JSON
   - 校验失败 → 输出修复建议并终止（不继续到 Step F）

9f. **Commit staging → 正式目录**：`mv staging/volumes/vol-01/* → volumes/vol-01/`（幂等覆盖），清空 `staging/volumes/`

9g. 更新 `.checkpoint.json`：`quick_start_step = "F0"`

##### Step F: 黄金三章试写（完整 pipeline）

10. 使用 Task 逐章派发完整流水线（共 3 章），**复用 `/novel:continue` Step 2-3 的完整流水线**（ChapterWriter → Summarizer → StyleRefiner → QualityJudge → 质量门控）。

    > Step F0 已生成 outline + L3 contracts + storyline-schedule + foreshadowing，本步骤使用与 `/novel:continue` 完全一致的完整流水线。

    **与 `/novel:continue` 的差异（仅以下几点）**：

    - **第 1 章启用双裁判**（关键章规则）：Sonnet 主评 + Opus 副评，`overall_final = min(primary, secondary)`
    - **第 2、3 章**：单裁判（Sonnet）
    - **不执行**周期性维护（试写阶段无风格基线，漂移检测无意义）
    - **中断恢复**：与 `/novel:continue` Step 1.5 一致

    其余所有行为（Manifest 组装、双轨验收、质量门控阈值、事务提交）均与 `/novel:continue` Step 2-3 完全相同，详见 `skills/continue/SKILL.md`。

11. 第 3 章 commit 完成后，更新 `.checkpoint.json`：`quick_start_step = "F"`

##### Step G: 展示结果 + 明确下一步

12. 展示试写结果摘要：3 章标题 + 字数 + QualityJudge 评分（第 1 章标注双裁判结果）+ 门控决策 + 修订次数{有 platform 时附带平台适配分 `overall_weighted`}
13. **若 Step B 选择了 `write_then_extract`**：此时派发 StyleAnalyzer 从试写 3 章**提取并填充** `style-profile.json` 的分析字段（`avg_sentence_length`、`dialogue_ratio`、`rhetoric_preferences` 等），`source_type` 保持 `"write_then_extract"` 不变
14. 使用 AskUserQuestion 给出明确下一步选项：



15. **根据用户选择分支**：
    - 选项 1（进入卷规划）：写入 `.checkpoint.json`（`current_volume = 1, last_completed_chapter = 3, orchestrator_state = "VOL_PLANNING"`），删除 `quick_start_step` 字段
    - 选项 2（调整风格）：保持 `orchestrator_state = "QUICK_START"`，`quick_start_step = "D"`，清除 `style-profile.json` 中非模板字段（保留 `_*_comment` 和 `source_type`），回到 Step E
    - 选项 3（重新试写）：保持 `orchestrator_state = "QUICK_START"`，`quick_start_step = "E"`，清除以下产物后回到 Step F0：
      - `staging/` 下所有试写产物
      - `chapters/chapter-00{1,2,3}.md`、`summaries/chapter-00{1,2,3}-summary.md`、`evaluations/chapter-00{1,2,3}-eval.json`
      - `logs/chapter-00{1,2,3}-log.json`
      - `state/chapter-00{1,2,3}-crossref.json`
      - `storylines/*/memory.md`（仅清除试写期间创建的 memory 文件）
      - `volumes/vol-01/` 下的 outline.md、chapter-contracts/、foreshadowing.json、storyline-schedule.json（Step F0 产物）
      - `state/current-state.json` 中 `state_version` 回退到 0
      - `foreshadowing/global.json` 清除试写章写入的条目

---

## 继续快速起步

- 读取 `.checkpoint.json`，确认 `orchestrator_state == "QUICK_START"`
- 读取 `quick_start_step` 字段，从**中断处的下一步**继续执行：
  - `"C"` → Step D（世界观 + 角色 + 故事线）
  - `"D"` → Step E（风格提取）
  - `"E"` → Step F0（迷你卷规划）
  - `"F0"` → Step F（黄金三章试写）。进入 Step F 后，若 `pipeline_stage != null` 且 `inflight_chapter != null`，按 `/novel:continue` Step 1.5 中断恢复规则从断点继续
  - `"F"` → Step G（展示结果 + 下一步）
- 每个 Step 开始前，先检查该步骤的产物是否已存在（例如 Step D 检查 `world/rules.json`，Step F0 检查 `volumes/vol-01/outline.md` + `volumes/vol-01/chapter-contracts/chapter-001.json`），避免重复生成
- quick start 完成后更新 `.checkpoint.json`：`current_volume = 1, last_completed_chapter = 3, orchestrator_state = "VOL_PLANNING"`，删除 `quick_start_step`

> 注意：Step A/B/B.5 不持久化 checkpoint（仅收集用户输入和确认 brief，约 3-5 分钟）。若在 Step C 写入 checkpoint 之前中断，用户将回到 INIT 状态重新创建项目，这是可接受的重做成本。
