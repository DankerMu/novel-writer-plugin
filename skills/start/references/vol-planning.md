# 规划本卷 / 规划新卷

> 仅当 `orchestrator_state == "VOL_PLANNING"`（或完成卷末回顾后进入 VOL_PLANNING）时执行。

0. 计算本卷规划章节范围（确定性）：
   - `V = current_volume`
   - `plan_start = last_completed_chapter + 1`
   - `plan_end = V * 30`（每卷 30 章约定；如 `plan_start > plan_end` 视为数据异常，提示用户先修复 `.checkpoint.json`）
   - 创建目录（幂等）：`mkdir -p staging/volumes/vol-{V:02d}/chapter-contracts`
1. 若 `.checkpoint.json.pending_actions` 存在与本卷有关的 `type == "spec_propagation"` 待办（例如世界规则/角色契约变更影响到 `plan_start..plan_end`）：
   - 展示待办摘要（变更项 + 受影响角色/章节契约）
   - AskUserQuestion 让用户选择：
     1) 先处理待办并重新生成受影响契约 (Recommended)
     2) 继续规划（保留待办，后续人工处理）
     3) 取消
2. 组装 PlotArchitect context（确定性，按 `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` §8.3）：
   - `volume_plan`: `{ "volume": V, "chapter_range": [plan_start, plan_end] }`
   - `prev_volume_review`：传入 `volumes/vol-{V-1:02d}/review.md` 路径（如存在；PlotArchitect 按需 Read）
   - `global_foreshadowing`：读取 `foreshadowing/global.json`
   - `storylines`：读取 `storylines/storylines.json`
   - `project_brief`：读取 `brief.md`（PlotArchitect 从中提取 genre 用于 excitement_type 映射；后续卷中 brief 仍为有效输入源）
   - `world_docs`：传入 `world/*.md` 路径列表 + `world/rules.json` 路径（PlotArchitect 按需 Read）
   - `characters`：传入 `characters/active/*.md` + `characters/active/*.json` 路径列表（PlotArchitect 按需 Read）
   - `user_direction`：用户额外方向指示（如有）
   - `prev_chapter_summaries`（首卷替代 `prev_volume_review`）：若 `prev_volume_review` 不存在且 `last_completed_chapter > 0`，传入最近 3 章 `summaries/chapter-*-summary.md` 路径列表（PlotArchitect 按需 Read）
   - `inherit_mode`（黄金三章继承）：若以下条件**全部**满足，启用继承模式：
     - `V == 1`（第 1 卷）
     - `plan_start > 1`（已有已完成章节，即 `last_completed_chapter > 0`）
     - `volumes/vol-01/outline.md` 已存在（Step F0 已生成前 3 章 outline）
     - `volumes/vol-01/chapter-contracts/chapter-001.json` 已存在
   - 启用继承模式时，额外传入 PlotArchitect：
     - `inherit_mode: true`
     - `existing_outline_path`: `volumes/vol-01/outline.md`（PlotArchitect 读取已有章节 outline，从 `plan_start` 章开始扩展）
     - `existing_contracts_range`: `[1, last_completed_chapter]`（已固化的 L3 contracts 范围，不可重写）
     - `chapter_summaries`: 读取 `summaries/chapter-001-summary.md` ~ `chapter-{last_completed_chapter:03d}-summary.md`
     - `existing_foreshadowing_path`: `volumes/vol-01/foreshadowing.json`（已有伏笔计划，扩展而非重建）
     - `existing_schedule_path`: `volumes/vol-01/storyline-schedule.json`（已有调度，扩展而非重建）
3. 使用 Task 派发 PlotArchitect Agent 生成本卷规划产物（写入 staging 目录，step 6 commit 到正式路径）：
   - `staging/volumes/vol-{V:02d}/outline.md`（严格格式：每章 `###` 区块 + 固定 `- **Key**:` 行）
   - `staging/volumes/vol-{V:02d}/storyline-schedule.json`
   - `staging/volumes/vol-{V:02d}/foreshadowing.json`
   - `staging/volumes/vol-{V:02d}/new-characters.json`（可为空数组）
   - `staging/volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.json`（`C ∈ [plan_start, plan_end]`）
   - （注意：`foreshadowing/global.json` 为事实索引，由 `/novel:continue` 在每章 commit 阶段从 `foreshadow` ops 更新；卷规划阶段不生成/覆盖 global.json）
   - **继承模式下 PlotArchitect 的行为约束**（仅 `inherit_mode == true` 时适用）：
     - `outline.md`：保留已有章节（1-{last_completed_chapter}）的 `### 第 N 章` 区块不变，可在区块末尾追加 `<!-- [NOTE] ... -->` 标记行（如建议加强某处伏笔）；从 `plan_start` 章开始新增区块
     - `chapter-contracts/`：已有章节的 `.json` 只读不改；从 `plan_start` 章开始生成新 contracts
     - `foreshadowing.json`：在已有条目基础上扩展（新增 + 更新 target_resolve_range），不删除已有条目
     - `storyline-schedule.json`：在已有调度基础上扩展（新增 chapter range 覆盖、convergence_events），不删除已有 active_storylines
     - `new-characters.json`：正常输出（扫描 plan_start..plan_end 中引用但未注册的角色）
   - **继承模式下的额外校验**：`outline.md` 中 `1..last_completed_chapter` 范围的 `### 第 N 章` 区块仍然存在（确保 PlotArchitect 未误删已有章节）
4. 规划产物校验（对 `staging/` 下的产物执行；失败则停止并给出修复建议，禁止"缺文件继续写"导致断链）：
   - `outline.md` 可解析：可用 `/^### 第 (\\d+) 章/` 找到章节区块，且连续覆盖 `plan_start..plan_end`（不允许跳章，否则下游契约缺失会导致流水线崩溃）
   - 每个章节区块包含固定 key 行：`Storyline/POV/Location/Conflict/Arc/Foreshadowing/StateChanges/TransitionHint`
     - 允许 `TransitionHint` 值为空；但 key 行必须存在（便于机器解析）
   - `storyline-schedule.json` 可解析（JSON），`active_storylines` ≤ 4，且本卷 `outline.md` 中出现的 `storyline_id` 均属于 `active_storylines`
   - `chapter-contracts/` 全量存在且可解析（JSON），并满足最小一致性检查：
     - `chapter == C`
     - `storyline_id` 与 outline 中 `- **Storyline**:` 一致
     - `objectives` 至少 1 条 `required: true`
   - 链式传递检查（最小实现）：若 `chapter-{C-1}.json.postconditions.state_changes` 中出现角色 X，则 `chapter-{C}.json.preconditions.character_states` 必须包含 X（值可不同，代表显式覆盖）。对 `plan_start` 章：
     - 继承模式下 `chapter-{plan_start-1}.json` 存在（Step F0 已生成）→ 正常执行链式传递检查
     - 非继承模式或 `chapter-{plan_start-1}.json` 不存在 → 跳过该章的链式传递检查，其 preconditions 由 PlotArchitect 从试写摘要派生
   - `foreshadowing.json` 与 `new-characters.json` 均存在且为合法 JSON
5. 审核点交互（AskUserQuestion）：
   - 展示摘要：
     - `storyline-schedule.json` 的活跃线与交汇事件概览
     - 每章 1 行清单：`Ch C | Storyline | Conflict | required objectives 简写`
   - 让用户选择：
     1) 确认并进入写作 (Recommended)
     2) 我想调整方向并重新生成（清空 `staging/volumes/` 和 `staging/foreshadowing/` 后重新派发 PlotArchitect）
     3) 暂不进入写作（保持 VOL_PLANNING，规划产物保留在 staging 中）
6. 若确认进入写作：
   - commit 规划产物（staging → 正式目录）：
     - `mv staging/volumes/vol-{V:02d}/* → volumes/vol-{V:02d}/`（幂等覆盖）
     - 清空 `staging/volumes/` 和 `staging/foreshadowing/`
   - 读取 `volumes/vol-{V:02d}/new-characters.json`：
     - 若非空：批量调用 CharacterWeaver 创建角色档案 + L2 契约（按 `first_chapter` 升序派发 Task，便于先创建早出场角色）
   - 更新 `.checkpoint.json`（`orchestrator_state = "WRITING"`, `pipeline_stage = null`, `inflight_chapter = null`, `revision_count = 0`）
