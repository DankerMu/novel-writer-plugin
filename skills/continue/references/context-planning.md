# Context Planning（Task Agent）

本文档定义 `/novel:continue` Step 2b 的 **LLM 上下文规划**规则。

目标不是组装 JSON，而是回答一个更关键的问题：

> 这一章的 writer，到底该读哪些上下文，哪些只需要部分片段，哪些应该直接排除？

## 设计原则

- **决定权在 LLM**：`current_state / world_rules / storyline_memory / character_contracts / volume_outline` 等 support-context 的取舍，由 Task agent 决定，不由确定性脚本硬编码。
- **骨架由脚本保证**：`assemble-manifests.py` 只负责基础 manifest、稳定候选路径、固定 inline 字段。
- **核心包不可裁**：契约、大纲、边界、近章正文、风格样本、风格指纹、硬规则、storyline_context 不允许 planner 删除。
- **支撑包可裁剪**：planner 只对 support-context 决定“全给 / 摘录 / 窗口化 / 删除”。
- **materialize 到 staging**：planner 的决策必须写成 `staging/context/...` 下的 staged 文件，并 patch 到 ChapterWriter manifest。

## 输入

planner 至少读取：

- `staging/manifests/chapter-{C:03d}-chapter-writer.json`
- `paths.chapter_contract`
- `chapter_outline_block`
- `paths.recent_chapters[]`
- `storyline_context`
- `hard_rules_list`
- `paths.style_profile`
- `paths.style_samples`

然后按需读取候选 support-context：

- `paths.volume_outline`
- `paths.current_state`
- `paths.world_rules`
- `paths.storyline_memory`
- `paths.adjacent_memories[]`
- `paths.character_contracts[]`
- `foreshadowing_tasks`
- `concurrent_state`
- `transition_hint`
- `paths.platform_guide`
- `paths.project_brief`
- `paths.style_drift`

补充规则：

- `paths.character_contracts[]` 只是骨架脚本给出的初始候选，不是硬边界。
- 若 planner 判断本章还涉及骨架候选之外的角色，可以直接读取 `characters/active/*.json` 扩展候选，并自行生成新的 `staging/context/characters/*.json` staged 副本后 patch 回 ChapterWriter manifest。

## Planner 必须回答的问题

### 1. 哪些角色真的与本章有关

判断依据：

- 本章契约明确出场
- 近章正文中直接承接
- 本章冲突会直接影响
- 本章虽然不出场，但会被讨论/被追查/被牵动

输出：

- 保留的角色列表
- 每个角色需要保留的原因
- 若角色档案过长，保留哪些条目（能力、事实、关系、秘密、禁忌）
- 若初始 `paths.character_contracts[]` 候选不足，必须在 plan 中说明你是如何从 `characters/active/*.json` 扩展候选的

### 2. 哪些世界规则真的会在本章被触发

判断依据：

- 契约显式引用
- 场景行动会触发
- 冲突解决依赖
- 角色能力使用依赖

输出：

- 保留的规则 ID 列表
- 若规则文件过长，提取为 staged 副本

### 3. `current_state` 哪些字段必须进

判断依据：

- 角色当前位置/伤势/资源/关系变化
- 世界状态或任务状态会直接约束本章
- 活跃伏笔会在本章推进
- 该状态若缺失，会导致 writer 写出错误衔接

输出：

- 保留的 state 路径/字段
- 可删除的无关字段

### 4. 哪些故事线记忆要进

规则：

- 当前线 memory：保留与本章主冲突、未解悬念、近期状态变化直接相关的段落
- 相邻线 memory：只有在切线、交汇、信息压力真实影响本章时才保留
- 不能因为文件存在就整份塞入

输出：

- 当前线 memory 取哪些段落
- 哪些 adjacent memory 保留，哪些删除

### 5. 卷大纲如何窗口化

规则：

- 不是默认整卷全给
- 应根据本章所在 arc，保留本章前后必要窗口
- 如本章为交汇/转折/卷尾，可放宽窗口

输出：

- 需要的 chapter window
- 为什么需要这个窗口

### 6. 哪些额外支撑上下文应保留

包括：

- `foreshadowing_tasks`
- `concurrent_state`
- `transition_hint`
- `platform_guide`
- `project_brief`
- `style_drift`

规则：

- 只保留会改变正文决策的项
- 单纯“可能有帮助”但不会改变正文的项，优先删除

## 输出产物

planner 必须写出两个层面的结果。

### A. 规划文件

路径：

- `staging/context-plans/chapter-{C:03d}.json`

建议结构：

```json
{
  "chapter": 12,
  "volume": 1,
  "storyline_id": "main",
  "keep": {
    "character_contracts": [
      {"path": "staging/context/characters/lin-feng.json", "reason": "本章 POV 且直接决策"},
      {"path": "staging/context/characters/su-yao.json", "reason": "章末冲突核心对象"}
    ],
    "world_rules": [
      {"id": "W-003", "reason": "本章能力使用依赖"}
    ],
    "current_state": [
      {"selector": "characters.lin-feng", "reason": "伤势与资源直接影响行动"},
      {"selector": "world_state.black_market", "reason": "本章场景发生地"}
    ],
    "storyline_memory": [
      {"excerpt": "当前线近两章未解悬念", "reason": "章首承接"}
    ],
    "adjacent_memories": [
      {"path": "staging/context/storylines/rival/memory.md", "reason": "交汇事件前置信息"}
    ]
  },
  "drop": {
    "project_brief": "本章无新增项目级信息需求",
    "platform_guide": "style_profile 已覆盖关键参数"
  }
}
```

### B. materialized staged files

路径约定：

- `staging/context/characters/...`
- `staging/context/world/...`
- `staging/context/state/...`
- `staging/context/storylines/...`
- `staging/context/volumes/...`

planner 可以：

- 复制原文件
- 摘录部分段落
- 重写为窗口化副本
- 生成只保留相关字段的 JSON 副本

但必须满足：

- staged 文件内容足够让 writer 独立读取
- 不得只输出“去读原文件第几段”这种悬空指令

## patch ChapterWriter manifest 的规则

planner 完成 materialize 后，必须 patch：

- `staging/manifests/chapter-{C:03d}-chapter-writer.json`

规则：

- 核心包字段不得删：
  - `chapter_outline_block`
  - `storyline_context`
  - `hard_rules_list`
  - `paths.chapter_contract`
  - `paths.style_profile`
  - `paths.style_samples`
  - `paths.recent_chapters`
- 支撑包字段可改为 staged 路径，也可删除
- 被删除的字段，必须在 `context-plan.json` 的 `drop` 中说明原因

## 预算原则

不要求 planner 死守固定 token 数，但应遵循：

- 先保连续性，再保完整性
- 先保当前章决策所需信息，再保背景材料
- 若不确定，优先保留边界相关信息
- 若 support-context 过长，优先改成 staged 摘录，而不是把整份原文件留给 writer

## 禁止事项

- 不得删除核心上下文
- 不得把“上下文规划”变成“预写章节”
- 不得让 writer 再自己决定是否读取 staged support-context 之外的大文件
- 不得修改 StyleRefiner / Summarizer / QualityJudge / ContentCritic manifest 的语义字段
