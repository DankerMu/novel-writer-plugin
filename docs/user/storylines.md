# 多线叙事指南

本系统支持多 POV 群像、势力暗线、跨卷伏笔交汇等复杂叙事结构。

## 核心概念

### 故事线（Storyline）

每条故事线有固定 ID（连字符命名，如 `main-arc`、`faction-war`），一经定义不可重命名。

**类型**（`type:` 前缀）：

| 类型 | 说明 |
|------|------|
| `type:main_arc` | 主线，贯穿全书 |
| `type:faction_conflict` | 势力冲突线 |
| `type:conspiracy` | 阴谋暗线 |
| `type:mystery` | 悬疑/谜题线 |
| `type:character_arc` | 角色成长线 |
| `type:parallel_timeline` | 平行时间线 |

### 卷级角色（Volume Role）

每条故事线在每卷中有不同角色：

- **primary**：本卷主要推进的线（通常 1-2 条）
- **secondary**：辅助线，有最小出场频率要求
- **seasoning**：调味线，偶尔出场，不做频率要求

## 快速起步

快速起步阶段，系统只初始化 1 条 `type:main_arc` 主线：

```json
{
  "storylines": [
    {
      "id": "main-arc",
      "name": "主线名称",
      "type": "type:main_arc",
      "scope": "novel",
      "status": "active"
    }
  ]
}
```

后续在卷规划阶段，PlotArchitect 会根据剧情需要建议新增故事线。

## 活跃线限制

**同时活跃 ≤4 条**。这是硬约束（LS-002），超出时系统会要求你暂停或合并故事线。

为什么限制 4 条？因为每章写作时 ChapterWriter 需要接收所有活跃线的 context，线太多会导致 context 过载和串线风险。

## 卷级调度

进入卷规划时，PlotArchitect 生成 `storyline-schedule.json`：

```json
{
  "active_storylines": [
    { "storyline_id": "main-arc", "volume_role": "primary" },
    { "storyline_id": "faction-war", "volume_role": "secondary" }
  ],
  "interleaving_pattern": {
    "secondary_min_appearance": "every_8_chapters"
  },
  "convergence_events": [
    {
      "event": "两线在第 20 章交汇",
      "involved_storylines": ["main-arc", "faction-war"],
      "target_chapter_range": [18, 22]
    }
  ]
}
```

关键字段：

- `secondary_min_appearance`：副线最小出场间隔（如 `every_8_chapters` = 每 8 章至少出现 1 次）
- `convergence_events`：交汇事件——多条线在指定章节范围内汇合

## 防串线机制

三层防护：

1. **结构化 Context**：ChapterWriter 每次只接收当前章相关的故事线状态，而非全部
2. **反串线指令**：prompt 中明确标注「本章属于 X 线，不得出现 Y 线的信息」
3. **QualityJudge 后验**：LS-005 规则检查跨线实体是否泄漏

每次续写都是独立的 LLM 调用，不依赖前一章的会话历史。

## 交汇事件

当多条故事线需要汇合时（如主角终于遇到暗线反派），在 `convergence_events` 中定义：

- 涉及哪些线
- 目标章节范围
- 交汇后的状态变化

卷末回顾时，系统会检查交汇事件是否在预定范围内达成。

## 故事线记忆

每条故事线有独立记忆文件 `storylines/{id}/memory.md`（≤500 字），由 Summarizer 每章更新。

记忆文件记录这条线的关键事实，供 ChapterWriter 写作时参考，避免遗忘已建立的设定。

## 桥梁关系

故事线之间可以定义桥梁（bridge），表示两条线通过共享伏笔或角色关联：

```json
{
  "relationships": [
    {
      "from": "main-arc",
      "to": "conspiracy",
      "type": "bridge:shared_foreshadowing",
      "bridges": {
        "shared_foreshadowing": ["foreshadow-id-1", "foreshadow-id-2"]
      }
    }
  ]
}
```

卷末回顾时，系统检查桥梁是否断链（共享伏笔是否在全局索引中存在）。

## 日常操作

| 场景 | 操作 |
|------|------|
| 新增故事线 | 卷规划时由 PlotArchitect 建议，你确认 |
| 暂停故事线 | 将 status 改为 `dormant`（不计入活跃线） |
| 合并故事线 | 交汇事件达成后，将一条线标记为 `resolved` |
| 查看节奏 | `/novel:dashboard` 展示各线出场频率和休眠提醒 |

## 注意事项

- 故事线 ID 用连字符（`main-arc`），类型用下划线 + `type:` 前缀（`type:main_arc`）
- 不要手动编辑 `storylines/storylines.json`，通过 `/novel:start` → 更新设定来操作
- 多线体系的完整能力在卷规划阶段才会展开，快速起步阶段保持简单
