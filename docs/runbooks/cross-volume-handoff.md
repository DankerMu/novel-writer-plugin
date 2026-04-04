# 跨卷衔接

## Trigger

卷末章提交后，编排器检测到 `last_completed_chapter == chapter_end`（本卷最后一章），自动执行：

1. 卷末核心检查（NER 一致性 + 伏笔盘点 + 故事线节奏分析）
2. 更新 `.checkpoint.json`：`orchestrator_state = "VOL_REVIEW"`
3. 提示用户执行 `/novel:start` 进行 State 清理和下卷规划

## Diagnosis

### 检查上卷产出完整性

| 产出文件 | 路径 | 用途 |
|---------|------|------|
| 卷末回顾 | `volumes/vol-{V:02d}/review.md` | 本卷总结、质量概览、叙事方向 |
| 一致性报告 | `volumes/vol-{V:02d}/continuity-report.json` | 全卷 NER/连续性审计 |
| 未回收伏笔 | `foreshadowing/global.json` 中 `status != "resolved"` 的条目 | 跨卷伏笔传递 |
| 故事线状态 | `storylines/storyline-spec.json` + 各线 `memory.md` | 活跃/休眠线状态 |
| 全局状态 | `state/current-state.json` | 角色位置/关系/世界状态快照 |
| 角色档案 | `characters/active/*.json` | 退役处理后的活跃角色 |

缺失任一关键产出 → 提示用户先完成 `/novel:start → 卷末回顾`。

### 检查待清理项

- `state/current-state.json` 中是否有应退役角色（本卷无出场且非主角）
- `pending_actions[]` 是否有未传播的 `spec_propagation` 条目
- `global.json` 中 `scope == "short"` 但未回收的伏笔（应在卷内解决）

## Actions

### 卷末回顾（`/novel:start → 卷末回顾`）

1. 生成 `volumes/vol-{V:02d}/review.md`：本卷概述、章节评分趋势、角色弧光、伏笔回收率、故事线完成度
2. State 清理：退役角色安全移动 `characters/active/ → characters/retired/`（需用户确认）
3. 清理候选临时条目（临时 NPC、过渡性世界状态）
4. 更新 `orchestrator_state = "VOL_PLANNING"`

### 下卷规划（`/novel:start → 规划新卷`）

PlotArchitect 读取以下输入（**不读取上卷章节全文**，冷启动）：

- `volumes/vol-{V:02d}/review.md`（上卷回顾）
- `foreshadowing/global.json`（未回收伏笔摘要）
- `storylines/storyline-spec.json`（故事线定义 + 状态）
- `world/rules.json`（世界规则，含新确立的 established 条目）
- `characters/active/*.json`（活跃角色契约）
- `state/current-state.json`（全局状态快照）

产出：
- `volumes/vol-{V+1:02d}/outline.md`（下卷大纲）
- `volumes/vol-{V+1:02d}/chapter-contracts/`（各章 L3 契约）
- `volumes/vol-{V+1:02d}/storyline-schedule.json`（故事线调度）
- `volumes/vol-{V+1:02d}/foreshadowing.json`（本卷伏笔计划）

### 状态转移

```
VOL_REVIEW → (review.md + State 清理) → VOL_PLANNING → (outline + contracts) → WRITING
```

更新 `.checkpoint.json`：`current_volume += 1`，`orchestrator_state = "WRITING"`，`last_completed_chapter` 保持（跨卷章节号连续）。

## Acceptance

- `volumes/vol-{V+1:02d}/outline.md` 存在且结构合法（包含 `### 第 N 章` 标题）
- 所有章节的 L3 契约文件生成完毕（`chapter-contracts/chapter-{C:03d}.md`）
- `storyline-schedule.json` 包含活跃故事线调度
- `.checkpoint.json` 进入 `WRITING` 状态，`current_volume` 已递增
- 用户确认下卷规划方向（通过 AskUserQuestion 交互）

## Rollback

- **回顾产出不完整**：重新执行 `/novel:start → 卷末回顾`，不会覆盖已有的合法 `review.md`
- **规划不满意**：用户可在 `VOL_PLANNING` 状态下反复执行 `/novel:start → 规划本卷`，每次重新生成 outline + contracts（覆盖 staging 中的草稿）
- **伏笔跨卷断裂**：在下卷 `foreshadowing.json` 中补充上卷未回收伏笔的延续计划，更新 `global.json` 的 `target_resolve_range`
- **回退到上卷**：若下卷规划提交前发现上卷末尾需修改，将 `orchestrator_state` 手动回退到 `WRITING`，`current_volume` 不变，修改后重新进入 `VOL_REVIEW`
