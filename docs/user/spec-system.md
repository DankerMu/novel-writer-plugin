# 规范体系

本系统用 4 层规范驱动写作，确保长篇小说在数百章后仍保持一致性。

## 四层规范概览

```
L1 世界规则    → 硬约束，不可违反（类似编译错误）
L2 角色契约    → 能力/行为边界，变更需走协议
L3 章节契约    → 每章的前置/后置条件（类似函数签名）
LS 故事线规范  → 多线叙事约束（防串线、控节奏）
```

## L1 世界规则

**文件**：`world/rules.json`
**生成者**：WorldBuilder

每条规则标注 `hard`（不可违反）或 `soft`（可有例外但需说明理由）：

```json
{
  "id": "W-001",
  "category": "magic_system",
  "rule": "修炼者突破金丹期必须经历雷劫",
  "constraint_type": "hard",
  "exceptions": []
}
```

快速起步阶段只生成 ≤3 条核心 hard 规则，后续卷规划时按需扩展。

ChapterWriter 收到 hard 规则时会以禁止项注入：违反即自动拒绝。

**canon_status**（M5.1）：每条规则含 `canon_status` 字段，区分已确立事实（`established`）和卷规划预案（`planned`）。编排器预过滤 planned 规则，仅注入 established 给 ChapterWriter；章节契约引用的 planned 规则以 `[INTRODUCING]` 前缀注入。Summarizer 输出 `canon_hints` 后，编排器在 commit 阶段将 planned 升级为 established。缺失时默认 `established`（向后兼容）。

## L2 角色契约

**文件**：`characters/active/*.json`
**生成者**：WorldBuilder（角色模式）

定义每个角色的能力边界和行为模式：

- 能力上限（不能做什么）
- 性格底线（绝不会做的事）
- 关系约束（敌友关系不可突变）
- 成长轨迹（从 A 到 B 需要什么条件）

**结构化数组**（M5.1）：角色 JSON 新增 `abilities[]`、`known_facts[]`、`relationships[]` 数组，每个条目含可选 `canon_status`（`established`/`planned`），编排器预过滤 planned 条目后传给 ChapterWriter。例外：章节契约 `preconditions.character_states` 引用的 planned 条目保留并标记 `introducing: true`，表示本章将首次展现。缺失时视为空数组。

角色退场有三重保护：活跃伏笔检查 → 故事线依赖检查 → 用户确认。

## L3 章节契约

**文件**：`volumes/vol-XX/chapter-contracts/chapter-XXX.md`
**生成者**：PlotArchitect（卷规划阶段）

每章的前置条件（写之前必须满足什么）和后置条件（写完后必须达成什么）：

- 继承哪条故事线
- 必须推进的情节点
- 必须出场的角色
- 伏笔埋设/回收要求
- 状态变更预期
- **爽点类型**（`excitement_type`，M5.3）：从 8 种枚举中标注 1-2 个（`power_up`/`reversal`/`cliffhanger`/`emotional_peak`/`mystery_reveal`/`confrontation`/`worldbuilding_wow`/`setup`），ChapterWriter 据此调整写作重心，QualityJudge 评估爽点是否落地。`setup` 与其他类型互斥（铺垫章用独立评分标准）

QualityJudge 验收时逐条检查章节契约的达成情况。

## LS 故事线规范

**文件**：`storylines/storyline-spec.json`
**规则编号**：LS-001 ~ LS-005

5 条核心故事线规则：

| 规则 | 说明 |
|------|------|
| LS-001 | 故事线 ID 一经定义不可重命名 |
| LS-002 | 同时活跃故事线 ≤4 条 |
| LS-003 | 交汇事件必须按 schedule 在指定范围内完成 |
| LS-004 | 副线最小出场频率（如每 8 章至少 1 次） |
| LS-005 | 跨线实体不可泄漏（A 线的秘密不能无故出现在 B 线） |

详见 [多线叙事指南](storylines.md)。

## 质量门控

QualityJudge 采用双轨验收：

1. **合规检查**（硬门槛）：L1/L2/L3/LS 逐条校验，有 high-confidence 违规即强制修订
2. **质量评分**（软评估）：8 维度加权评分

| 维度 | 权重 |
|------|------|
| 情节逻辑 | 18% |
| 角色塑造 | 18% |
| 沉浸感 | 15% |
| 风格自然度 | 15% |
| 伏笔处理 | 10% |
| 节奏 | 8% |
| 情感冲击 | 8% |
| 故事线连贯 | 8% |

评分阈值：≥4.0 通过，3.5-3.9 二次润色，3.0-3.4 自动修订，2.0-2.9 人工审核，<2.0 强制重写。

## 文件结构

```
project/
├── brief.md                  创作纲领
├── .checkpoint.json           进度快照
├── style-profile.json         风格指纹（含 platform 平台标识）
├── ai-blacklist.json          AI 用语黑名单
├── world/
│   ├── geography.md           地理设定
│   ├── history.md             历史背景
│   ├── rules.md               规则叙述
│   ├── rules.json             L1 结构化规则
│   └── changelog.md           变更记录
├── characters/
│   └── active/                活跃角色档案 + L2 契约
├── storylines/
│   ├── storylines.json        故事线定义
│   ├── storyline-spec.json    LS 规范
│   └── {id}/memory.md         各线记忆文件
├── volumes/vol-XX/
│   ├── outline.md             卷大纲
│   ├── storyline-schedule.json 故事线调度
│   ├── foreshadowing.json     伏笔计划
│   └── chapter-contracts/     L3 章节契约
├── chapters/                  章节正文
├── summaries/                 章节摘要
├── evaluations/               质量评估
├── foreshadowing/global.json  伏笔全局索引
├── state/current-state.json   世界状态快照
└── logs/                      流水线日志
```
