# 黄金三章 Genre-Specific Acceptance Criteria

本文档为 PlotArchitect Step F0（迷你卷规划）生成 L3 章节契约时提供 genre-specific 的 acceptance_criteria 参考。

## 使用方式

PlotArchitect 在 Step F0 模式下生成黄金三章（Ch001-003）的 L3 契约时：
1. 从 `brief.md` 获取 genre
2. 查本表获取该 genre 的章节特定 criteria
3. 将 criteria 合并到对应章节的 `acceptance_criteria` 数组中（与通用 criteria 并列）
4. 若 `platform_guide` 存在，叠加平台特定 criteria（见下方「平台叠加」）

> 本表仅用于黄金三章（Step F0），正式卷规划不强制引用（PlotArchitect 可自行设计 acceptance_criteria）。

## Genre → Acceptance Criteria 映射

### 玄幻/仙侠

| 章节 | Criteria Key | 说明 |
|------|-------------|------|
| Ch001 | `golden_finger_hinted: true` | 第 1 章必须暗示金手指/机缘的存在（不需要完整展示） |
| Ch003 | `first_power_up_or_face_slap: true` | 前 3 章内必须出现首次实力提升或打脸场景 |

### 都市

| 章节 | Criteria Key | 说明 |
|------|-------------|------|
| Ch001 | `protagonist_dilemma_established: true` | 第 1 章必须建立主角的核心困境/矛盾 |

### 科幻

| 章节 | Criteria Key | 说明 |
|------|-------------|------|
| Ch001 | `world_unique_element_shown: true` | 第 1 章必须展示至少一个区别于现实的独特世界元素 |

### 历史

| 章节 | Criteria Key | 说明 |
|------|-------------|------|
| Ch001 | `era_anchored: true` | 第 1 章必须锚定时代背景（明确的历史时期标志） |
| Ch001 | `protagonist_identity_clear: true` | 第 1 章必须明确主角身份定位（穿越者/原住民/权贵/平民等） |

### 悬疑/推理

| 章节 | Criteria Key | 说明 |
|------|-------------|------|
| Ch001 | `core_mystery_presented: true` | 第 1 章必须呈现核心悬念/谜题 |
| Ch001 | `tension_established: true` | 第 1 章必须建立紧张感/危机感 |

### 言情/甜宠

| 章节 | Criteria Key | 说明 |
|------|-------------|------|
| Ch001 | `both_leads_appeared: true` | 第 1 章男女主角必须同时出场 |
| Ch001 | `first_interaction: true` | 第 1 章必须有男女主角的首次互动 |

## 平台叠加 Criteria

以下 criteria 基于平台特性叠加到 genre criteria 之上（与 genre 并列而非互斥）：

| 条件 | Criteria Key | 说明 |
|------|-------------|------|
| platform=番茄 + genre=玄幻/仙侠 Ch001 | `protagonist_in_200_chars: true` | 番茄玄幻第 1 章主角 200 字内登场 |
| platform=晋江 + genre=言情/甜宠 Ch001 | `emotional_tone_hinted: true` | 晋江言情第 1 章暗示情感基调 |

> 平台叠加 criteria 仅在对应 genre + platform 组合时生效。无 platform 或组合不匹配时跳过。

## 通用 Criteria（所有 genre 共享）

以下 criteria 适用于所有黄金三章，与 genre-specific criteria 并列：

- Ch001: 主角在章节前半段出场
- Ch001-003: 每章至少一个核心冲突（与 L3 `objectives[].required` 语义重叠，作为兜底校验保留）
- Ch003: 主线方向明确，读者能判断故事走向

## Genre × Platform 无效/少见组合

PlotArchitect 和入口 Skill 在 Step F0 检查 genre × platform 组合，输出非阻塞 WARNING：

| Genre | Platform | 级别 | WARNING 文本 |
|-------|----------|------|-------------|
| 纯爱BL | 番茄 | 无效 | "纯爱BL 在番茄平台不可发布，请确认平台选择" |
| 硬科幻 | 晋江 | 少见 | "硬科幻在晋江较为少见，建议确认目标受众" |
| 硬核玄幻 | 晋江 | 少见 | "硬核玄幻在晋江较为少见，建议确认目标受众" |
| 言情 | 起点 | 少见 | "言情在起点极为少见，建议确认目标受众" |

> 无效组合输出 WARNING 但不阻塞流程。用户可选择忽略或修改 genre/platform。

## 写入格式约定

PlotArchitect 将 genre-specific criteria 以 `"<criteria_key>: true"` 字符串格式写入 L3 契约的 `acceptance_criteria` 数组（如 `"golden_finger_hinted: true"`）。QualityJudge 通过识别 criteria 字符串中的 key 进行语义检查。黄金三章的 genre-specific criteria 默认 confidence=high（布尔性明确条件），QualityJudge 仅在判断确实存在歧义时降为 medium。

## 未覆盖 Genre 处理

若 genre 不在上述 6 种映射中（如用户自由输入"军事"、"末日"等），PlotArchitect 仅使用「通用 Criteria」段的条目填充 `acceptance_criteria`，不尝试自行推断 genre-specific criteria。
