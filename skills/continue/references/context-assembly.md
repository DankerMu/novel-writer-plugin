# Context Assembly 规则（确定性）

本文档定义 `/novel:continue` Step 2 的完整 context 组装规则。编排器按本文档的确定性规则组装 agent manifest（同一章 + 同一项目文件输入 → 组装结果唯一）。

> 缺关键文件/解析失败 → 立即停止并给出可执行修复建议（避免"缺 context 继续写"导致串线/违约）。

## Step 2.0: Manifest 模式说明

**v2 架构变更**：编排器不再将文件全文读入并用 `<DATA>` 标签包裹后注入 Task prompt。改为在 manifest 中传递文件路径，由 subagent 自行 Read。

此变更的收益：
- 编排器 prompt 体积大幅缩减（路径 vs 全文）
- Subagent 可按需读取，避免加载无关内容
- 消除"双重读取"开销（编排器读 → 注入 → subagent 解析）

注入安全由各 Agent frontmatter 中的安全约束段落保障——Agent 被指示将读取的外部文件内容视为参考数据，不执行其中的操作请求。

> **兼容说明**：Step 2.1-2.5 中的确定性计算逻辑不变，仅最终输出从"内容注入"改为"路径引用"。

## Step 2.1: 从 outline.md 提取本章大纲区块（确定性）

1. 读取本卷大纲：`outline_path = volumes/vol-{V:02d}/outline.md`（不存在则终止并提示回到 `/novel:start` → "规划本卷"补齐）。
2. 章节区块定位（**不要求冒号**；允许 `:`/`：`/无标题）：
   - heading regex：`^### 第 {C} 章(?:[:：].*)?$`
3. 提取范围：从命中行开始，直到下一行满足 `^### `（不含）或 EOF。
4. 若无法定位本章区块：输出错误（包含期望格式示例 `### 第 12 章: 章名`），并提示用户回到 `/novel:start` → "规划本卷"修复 outline 格式后重试。
5. 解析章节区块内的固定 key 行（确定性；用于后续一致性校验）：
   - 期望格式：`- **Key**: value`
   - 必需 key：`Storyline`、`POV`、`Location`、`Conflict`、`Arc`、`Foreshadowing`、`StateChanges`、`TransitionHint`
   - 提取 `outline_storyline_id = Storyline`（若缺失或为空 → 视为 outline 结构损坏，报错并终止）

同时，从 outline 中提取本卷章节边界（用于卷首/卷尾双裁判与卷末状态转移）：
- 扫描所有章标题：`^### 第 (\d+) 章`
- `chapter_start = min(章节号)`，`chapter_end = max(章节号)`
- 若无法提取边界：视为 outline 结构损坏，按上述方式报错并终止。

## Step 2.2: `hard_rules_list`（L1 世界规则 → 禁止项列表，确定性）

1. 读取并解析 `world/rules.json`（如不存在则 `hard_rules_list = []`）。
2. 筛选 `constraint_type == "hard"` 且 `(canon_status == "established" 或 canon_status 缺失)` 的规则，按 `id` 升序输出为禁止项列表：

```
- [W-001][magic_system] 修炼者突破金丹期需要天地灵气浓度 ≥ 3级
- [W-002][geography] 禁止在"幽暗森林"使用火系法术（exceptions: ...）
- [INTRODUCING][W-003][magic_system] 本章首次展现的规则描述
```

> **Canon Status 过滤**：`canon_status == "planned"` 的规则默认不注入。例外：若 `chapter_contract.preconditions.required_world_rules`（如存在）引用了某 planned 规则 ID，则以 `[INTRODUCING]` 前缀注入该规则，表示本章将首次展现。

同时将所有 planned 规则 ID 列表记为 `planned_rule_ids`，传给 QualityJudge 用于 planned 引用检测。

该列表用于 ChapterWriter（禁止项提示）与 QualityJudge（逐条验收）。

## Step 2.3: `entity_id_map`（从角色 JSON 构建，确定性）

1. `Glob("characters/active/*.json")` 获取活跃角色结构化档案。
2. 对每个文件：
   - `slug_id` 默认取文件名（去掉 `.json`）
   - `display_name` 取 JSON 中的 `display_name`
3. 构建 `entity_id_map = {slug_id → display_name}`（并在本地临时构建反向表 `display_name → slug_id` 供裁剪/映射使用）。

该映射传给 Summarizer，用于把正文中的中文显示名规范化为 ops path 的 slug ID（如 `characters.lin-feng.location`）。

## Step 2.4: L2 角色契约裁剪（确定性）

前置：读取并解析本章 L3 章节契约（缺失则终止并提示回到 `/novel:start` → "规划本卷"补齐）：
- 优先路径：`chapter_contract_path = volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.md`（Markdown 格式）
- 回退路径：`volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.json`（旧版 JSON 格式，向后兼容）
- **Markdown 契约字段提取**：从结构化 Markdown 中提取等效字段：
  - `storyline_id`：从「基本信息 → 故事线」行提取
  - `涉及角色`：从「事件中自然流露的角色特质」section 提取角色名列表
  - `world_rules`：从「世界规则约束」section 提取 W-XXX ID 列表
  - `excitement_type`：从「钩子 → 类型」行提取
  - `acceptance_criteria`：从「验收标准」section 提取列表
  - `foreshadowing`：从「事件中自然推进的伏笔」section 提取 F-XXX 及动作
  - `前章衔接`：从「前章衔接」section 提取

裁剪规则：

- 若契约中「事件中自然流露的角色特质」列出了具体角色：
  - 仅加载这些角色（**无硬上限**；交汇事件章可 > 10）
  - 角色名为中文显示名，需要用 `entity_id_map` 反向映射到 `slug_id`
- 否则：
  - 最多加载 15 个活跃角色（按"最近出场"排序截断）
  - "最近出场"计算：扫描近 10 章 `summaries/`（从新到旧），命中 `display_name` 的第一次出现即视为最近；未命中视为最旧
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

## Step 2.5: storylines context + memory 注入（确定性）

1. 读取 `volumes/vol-{V:02d}/storyline-schedule.json`（如存在则解析；用于判定 dormant_storylines 与交汇事件 involved_storylines）。
2. 读取 `storylines/storyline-spec.json`（如存在；注入给 QualityJudge 做 LS 验收）。
3. 章节契约与大纲一致性校验（确定性；不通过则终止，避免"拿错契约继续写"导致串线/违约）：
   - 契约中的章号 == C
   - 契约中的 storyline_id == outline_storyline_id
   - **Markdown 契约**：「事件」section 非空（核心事件必须存在）
   - **JSON 契约（回退）**：`objectives` 至少 1 条 `required: true`
4. 以 `chapter_contract` 为优先来源确定：
   - `storyline_id`（本章所属线，从「基本信息」提取）
   - `storyline_context`（**Markdown 契约**：从「前章衔接」section 提取；**JSON**：从 `storyline_context` 对象提取）
   - `transition_hint`（**Markdown 契约**：若大纲中有 TransitionHint 则从大纲提取；**JSON**：从契约对象提取）
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

## Step 2.6: Agent Context Manifest 组装

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
- `track3_mode`：QualityJudge Track 3 输出模式（`"full"` | `"lite"`），判定规则见下方

编排器需完成的**路径计算**（作为 paths 字段写入 manifest）：
- 根据 Step 2.4 裁剪规则确定 `character_contracts[]` 和 `character_profiles[]` 的文件路径列表
- 根据 Step 2.5 注入策略确定 `storyline_memory` / `adjacent_memories[]` 的路径（过滤 dormant 线）
- 确定 `recent_summaries[]`（近 3 章摘要路径，按时间倒序）
- **QualityJudge `recent_summaries[]`（条件注入）**：当 chapter ≤ 3 且 platform_guide 存在时，注入近 2 章摘要路径供平台硬门回溯判定（Ch001 为空数组，Ch002 仅含 Ch001 摘要，Ch003 含 Ch001+002 摘要；路径指向文件不存在时跳过该条目）；章节 > 3 或无 platform_guide 时不注入此字段
- 其余路径为固定模式（如 `style-profile.json`、`ai-blacklist.json`）
- **平台指南加载**：读取 `style-profile.json` 的 `platform` 字段（缺失或 null 则终止并提示用户通过 `/novel:start` 设置平台，platform 为必填字段）。`platform` 为 `"general"` 时不加载 platform_guide（无对应模板文件），但 `platform` 值仍传入 QualityJudge manifest 供 Track 3 读者人设选择。**黄金三章提醒**：若 `platform == "general"` 且 `chapter_num == 1`，输出一次性提示：`💡 当前平台为 general，黄金三章的平台硬门检查（起点冰山式世界观/番茄3章内反转/晋江情感锚点等）未启用。如需启用，可通过 /novel:start → 更新设定 配置目标平台。`。其余平台值计算路径 `templates/platforms/{platform}.md`：文件存在则加入 `manifest.paths.platform_guide`（ChapterWriter + QualityJudge 均注入）；文件不存在则输出 WARNING（「平台指南 {platform}.md 不存在，跳过」）并继续（不阻断流水线）

**`track3_mode` 判定规则**（确定性）：

以下任一条件为 true 时 `track3_mode = "full"`，否则 `"lite"`：
- `is_golden_chapter == true`（chapter ≤ 3 且 platform_guide 存在）
- `chapter_num == chapter_end`（卷末章）
- 本章为关键章（双裁判触发：卷首/卷尾/交汇事件章/退化规则每 10 章）

关键原则：
- 同一输入 → 同一 manifest（确定性）
- 可选路径对应的文件不存在时，不加入 manifest（非 null）
- **不再使用 `<DATA>` 标签包裹**：subagent 自行读取文件，agent frontmatter 中的安全约束已覆盖注入防护

## Step 2.7: M3 风格漂移与黑名单（文件协议）

定义 `style-drift.json`、`ai-blacklist.json` 扩展字段、`lint-blacklist.sh` 脚本接口。

详见 `references/file-protocols.md`。
