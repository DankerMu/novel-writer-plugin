# 伏笔生命周期

## Trigger

以下任一情况触发本 runbook：

- 滑窗校验报告伏笔问题（`logs/continuity/latest.json` 中伏笔相关 issue）
- 伏笔到期未回收：`foreshadowing/global.json` 中 `scope == "short"` 且 `last_completed_chapter > target_resolve_range[1]`
- 每 10 章自动伏笔盘点（`last_completed_chapter % 10 == 0`）发现异常
- 伏笔状态与正文实际内容不一致

## Diagnosis

读取 `foreshadowing/global.json`，逐条检查：

| 字段 | 检查内容 |
|------|---------|
| `status` | 当前状态（planted / advanced / resolved） |
| `target_resolve_range` | 计划回收窗口 `[start, end]` |
| `last_updated_chapter` | 最后一次状态变更的章节号 |
| `history[]` | 各章的 `{chapter, action, detail}` 记录 |
| `scope` | short / medium / long，决定超期紧迫度 |
| `planted_chapter` / `planted_storyline` | 埋设来源 |

同时读取 `volumes/vol-{V:02d}/foreshadowing.json`（计划层），对比计划与事实的差异。

### 问题分类

- **超期未回收**：`status != "resolved"` 且当前章 > `target_resolve_range[1]`
- **停滞未推进**：`status == "planted"` 且 `last_updated_chapter` 距当前章 > 10 章
- **状态降级**：`global.json` 中状态高于正文实际体现（如标记 advanced 但正文无推进痕迹）
- **遗漏埋设**：计划层有条目但 `global.json` 无对应记录（planted 未执行）

## Actions

### 超期伏笔处理

1. **加速回收**：在接下来 1-3 章的 L3 契约中追加伏笔回收任务，PlotArchitect 规划回收情节
2. **延期**：更新 `target_resolve_range[1]` 到新的目标章节，记录延期理由到 `history[]`
3. **标记放弃**：将 `status` 设为 `resolved`，`history[]` 追加 `{action: "abandoned", detail: "原因"}`（仅限 `scope == "short"` 且叙事已转向的情况）

### 停滞伏笔推进

- 在下一章 context manifest 的 `foreshadowing_tasks` 中提高该伏笔优先级
- ChapterWriter 在正文中自然加入暗示或推进段落
- Summarizer 提取 foreshadow ops 更新 `global.json`

### 状态不一致修复

- 正文已推进但 `global.json` 未更新 → 手动更新 `global.json`（`status` 单调推进，追加 `history` 条目）
- `global.json` 标记过高 → **不可降级**（planted → advanced → resolved 单调），需在后续章节补充正文内容使其匹配

### 遗漏埋设补充

- 确认计划层条目是否仍然有效（与当前剧情方向是否冲突）
- 有效 → 加入下一章 `foreshadowing_tasks`，由 CW 植入
- 无效 → 从 `volumes/vol-{V:02d}/foreshadowing.json` 移除或标记 `skip`

## Acceptance

- `foreshadowing/global.json` 所有条目的 `status` 与正文实际一致
- 无超期未处理伏笔（全部已回收、已延期、或已标记放弃）
- `history[]` 记录完整，每次状态变更均有 `{chapter, action, detail}`
- 滑窗校验 / 10 章盘点无伏笔相关 issue

## Rollback

- **回收失败**：若在目标章节内无法自然回收（与主线冲突），优先选择延期而非强行插入
- **批量超期**：若同时有 3+ 条伏笔超期，优先处理 `scope == "short"` 的条目，`medium`/`long` 可整体延期一卷
- **降级策略**：当伏笔密度过高影响叙事节奏时，标记低优先级伏笔为 abandoned 并在 `logs/foreshadowing/` 中记录决策原因，供卷末回顾时审查
