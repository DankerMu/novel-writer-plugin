# 更新设定

1. 使用 AskUserQuestion 确认更新类型（世界观/新增角色/更新角色/退场角色/关系）
2. 变更前快照（用于 Spec 传播差异分析，确定性）：
   - 世界观更新：
     - Read `world/*.md`（传入路径列表，WorldBuilder 按需 Read）
     - Read `world/rules.json`（如存在）
   - 角色更新：Read 目标角色的 `characters/active/*.json`（如存在）
   - 退场角色（用于退场保护检查）：
     - Read 目标角色的 `characters/active/{id}.json`（如存在）
     - Read `characters/relationships.json`（如存在）
     - Read `state/current-state.json`（如存在）
     - Read `foreshadowing/global.json`（如存在）
     - Read `storylines/storylines.json`（如存在）
     - Read `volumes/vol-{V:02d}/storyline-schedule.json`（如存在）
3. 使用 Task 派发 WorldBuilder Agent 执行增量更新（世界观模式或角色模式，写入变更文件 + changelog）
   - 世界观更新（WorldBuilder）增量输入字段（确定性字段名）：
     - `existing_world_docs`（`world/*.md` 原文集合）
     - `existing_rules_json`（`world/rules.json`）
     - `update_request`（新增/修改需求）
     - `last_completed_chapter`（从 `.checkpoint.json.last_completed_chapter` 读取，用于更新变更规则的 `last_verified`）
   - 退场角色（WorldBuilder 角色退场模式）退场保护检查（入口 Skill 必须在调用退场模式前执行；`docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` §8.5）：
     - **保护条件 A — 活跃伏笔引用**：`foreshadowing/global.json` 中 scope ∈ {`medium`,`long`} 且 status != `resolved` 的条目，若其 `description`/`history.detail` 命中角色 `slug_id` 或 `display_name` → 不可退场
     - **保护条件 B — 故事线关联**：`storylines/storylines.json` 中任意 storyline（含 dormant/planned）若 `pov_characters` 或 `relationships.bridges.shared_characters` 命中角色 → 不可退场
     - `角色关联 storylines` 的计算：从 `storylines/storylines.json` 反查出包含该角色的 storyline `id` 集合（按 `pov_characters`/`bridges.shared_characters` 匹配 `slug_id`/`display_name`）；无法可靠确定时按保守策略视为有关联并阻止退场
     - **保护条件 C — 未来交汇事件**：本卷 `storyline-schedule.json.convergence_events` 若存在未来章节范围（相对 `last_completed_chapter`），且其 `involved_storylines` 与角色关联 storylines 有交集（或 `trigger/aftermath` 文本命中角色）→ 不可退场
     - 若触发保护：拒绝退场并解释命中证据（伏笔/故事线/交汇事件），不执行退场
   - 退场保护检查通过后，使用 Task 派发 WorldBuilder Agent（角色退场模式）执行退场（无需重复检查）
4. 变更后差异分析与标记（最小实现；目的：可追溯传播，避免 silent drift）：
   - 若 `world/rules.json` 发生变化：
     - 找出变更的 `rule_id` 集合（按 `id` 对齐，diff `rule`/`constraint_type`/`exceptions` 等关键字段）
     - 受影响 L2（角色契约）识别规则：
       1) 明确引用：角色契约 `rule` 文本中出现 `W-XXX`
       2) 最小关键字：从变更规则 `rule` 句子中抽取 3-5 个关键短语，在角色契约 `rule` 文本中命中则视为可能受影响
     - 受影响 L3（章节契约）识别规则：
       1) 明确引用：`preconditions.required_world_rules` 含变更 `W-XXX`
       2) 受影响角色：`preconditions.character_states` 含受影响角色（按 display_name 匹配）
     - 将结果写入 `.checkpoint.json.pending_actions`（新增一条 `type: "spec_propagation"` 记录：包含 changed_rule_ids + affected_character_contracts + affected_chapter_contracts）
   - 若角色契约发生变化：
     - 以角色 `slug_id` 为主键，记录该角色为受影响实体
     - 扫描本卷及后续 `volumes/**/chapter-contracts/*.json`：若 `preconditions.character_states` 含该角色 display_name 或 `acceptance_criteria`/`objectives` 提及该角色，则标记受影响
     - 写入 `.checkpoint.json.pending_actions`（`type: "spec_propagation"`，包含 changed_character_ids + affected_chapter_contracts）
5. 输出变更传播摘要并提示用户：
   - 推荐回到 `VOL_PLANNING` 重新生成/审核受影响的角色契约与章节契约，再继续写作（避免规则变更后隐性矛盾）
