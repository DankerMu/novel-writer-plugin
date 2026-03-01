## 1. 产品概述

基于 Claude Code 的多 agent 协作小说创作系统，面向中文网文作者，通过卷制滚动工作流实现长篇小说的高效续写和质量保证。

**核心价值**：
- **续写效率**：基于文件状态冷启动，随时续写下一章，无需重建上下文
- **一致性保证**：自动追踪角色状态、伏笔、世界观，跨 100+ 章维持一致
- **多线叙事**：支持多 POV 群像、势力博弈暗线、跨卷伏笔交汇等复杂叙事结构 [DR-021](../../v5/dr/dr-021-llm-multi-thread-narrative.md)
- **去 AI 化**：4 层风格策略确保输出贴近用户个人文风，降低 AI 痕迹
- **成本可控**：混合模型策略（Opus + Sonnet），每章 ~$0.85

**目标用户**：中文网文作者（MVP）[DR-016](../../v2/dr/dr-016-user-segments.md)

## 2. 产品形态：Claude Code Plugin

### 2.1 交付格式

本产品以 **Claude Code Plugin** 形式交付（plugin name: `novel`），包含 4 个技能（Skills）和 8 个专业 Agent。其中 3 个技能为用户入口（`/novel:start`、`/novel:continue`、`/novel:dashboard`），1 个为共享知识库。Plugin skills 遵循官方命名空间规则 `/{plugin-name}:{skill-name}`。[DR-018](../../v4/dr/dr-018-plugin-api.md) [DR-020](../../v4/dr/dr-020-single-command-ux.md)

```
cc-novel-writer/
├── .claude-plugin/
│   └── plugin.json                    # 插件元数据
├── skills/                            # 4 个技能（3 入口 + 1 知识库）
│   ├── start/
│   │   └── SKILL.md                   # /novel:start     状态感知交互入口
│   ├── continue/
│   │   └── SKILL.md                   # /novel:continue  续写下一章（高频快捷）
│   ├── dashboard/
│   │   └── SKILL.md                   # /novel:dashboard  只读状态查看
│   └── novel-writing/                 # 共享知识库（Claude 按需自动加载）
│       ├── SKILL.md                   # 核心方法论 + 风格指南
│       └── references/
│           ├── style-guide.md         # 去 AI 化规则详解
│           └── quality-rubric.md      # 8 维度评分标准
├── agents/                            # 8 个专业 Agent（自动派生）
│   ├── world-builder.md               # 世界观构建
│   ├── character-weaver.md            # 角色网络
│   ├── plot-architect.md              # 情节架构
│   ├── chapter-writer.md              # 章节写作
│   ├── summarizer.md                  # 摘要生成
│   ├── style-analyzer.md              # 风格提取
│   ├── style-refiner.md               # 去 AI 化润色
│   └── quality-judge.md               # 质量评估
├── hooks/
│   └── hooks.json                     # 事件钩子配置（SessionStart 等）
├── scripts/
│   └── inject-context.sh              # SessionStart 注入项目状态摘要
└── templates/                         # 项目初始化模板
    ├── brief-template.md
    ├── ai-blacklist.json
    └── style-profile-template.json
```

### 2.2 入口技能（三命令混合模式）

采用"引导式入口 + 快捷命令"模式，以 Skills 形式实现（支持 supporting files 和 progressive disclosure），认知负载 < Miller 下限（4 项），新老用户均可高效使用。[DR-020](../../v4/dr/dr-020-single-command-ux.md)

| 命令 | 用途 | 核心流程 |
|------|------|---------|
| `/novel:start` | 状态感知交互入口 | 读 checkpoint → 推荐下一步 → AskUserQuestion → Task 派发 agent |
| `/novel:continue [N]` | 续写 N 章（默认 1） | 读 checkpoint → ChapterWriter → Summarizer → StyleRefiner → QualityJudge → 更新 checkpoint |
| `/novel:dashboard` | 只读状态查看 | 展示进度、评分均值、伏笔状态 |

**`/novel:start` 入口逻辑**：
```
1. 读取 .checkpoint.json
2. 状态感知推荐：
   - 不存在 checkpoint → 推荐"创建新项目 (Recommended)"
   - 当前卷未完成 → 推荐"继续写作 (Recommended)"
   - 当前卷已完成 → 推荐"规划新卷 (Recommended)"
3. AskUserQuestion(options=[推荐项, 质量回顾, 导入研究资料, 其余可用项])
   约束：2-4 选项，单次最多 2-3 个问题（留余量给写作决策）
4. 根据选择 → Task tool 派发对应 agent
```

**AskUserQuestion 约束**（[DR-020](../../v4/dr/dr-020-single-command-ux.md)）：
- 每次 2-4 选项（主菜单恰好 ≤4 项，刚好在限制内）
- 60 秒超时 → 选项标记 "(Recommended)" 辅助快速决策
- 子代理不可用 → `/novel:start` 必须在主 command 中调用 AskUserQuestion
- 单次 `/novel:start` 建议 ≤5 个（尽量合并问题减少交互轮次）

**Command 文件格式**（YAML frontmatter，适用于 SKILL.md）：
```yaml
---
description: 小说创作主入口 — 状态感知交互引导
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, AskUserQuestion
model: sonnet
---
```

### 2.3 架构原则

- **Skills = 入口 + 调度**：`/novel:start` 做状态感知路由，`/novel:continue` 和 `/novel:dashboard` 为高频快捷命令，均以 Skills 实现（支持 supporting files + progressive disclosure）。Plugin name 采用短名 `novel`，遵循 `/{plugin}:{skill}` 命名空间规则
- **Agents = 专业化执行**：每个 agent 有独立的 prompt 模板和 tools 权限，需包含 name/description/model/color/tools frontmatter
- **Skill = 共享知识**：`novel-writing` skill 提供去 AI 化规则、质量评分标准等共享上下文，Claude 按需自动加载
- **Checkpoint 是衔接点**：skills 之间通过 `.checkpoint.json` 传递状态，支持冷启动
- **Orchestrator 是逻辑抽象**：Section 8 定义的状态机是逻辑设计，实际由 3 个入口 skill 分布实现（`/novel:start` 覆盖 INIT/QUICK_START/VOL_PLANNING/VOL_REVIEW，`/novel:continue` 覆盖 WRITING 循环，`/novel:dashboard` 只读），见 Section 8.2 映射表
- **插件资源路径**：插件安装后会被复制到缓存目录（`~/.claude/plugins/cache`），所有对插件内部文件（templates/、references/）的引用必须通过 `${CLAUDE_PLUGIN_ROOT}` 环境变量解析，禁止写死相对路径。项目运行时数据写入用户项目目录（稳定位置），插件自身文件为只读源
- **Hooks 增强可靠性**：Plugin 通过 `hooks/hooks.json` 注册事件钩子。M2 起启用 SessionStart hook（自动注入 checkpoint + 最近摘要）和 PreToolUse hook（路径审计，拦截 chapter pipeline 子代理写入非 `staging/` 的操作）。M3+ 可扩展 PostToolUse 做 schema 校验（需外部脚本）
- **确定性工具演进路线**：MVP 阶段所有操作通过 Claude 原生工具（Read/Write/Grep/Glob）+ Bash 完成。当 LLM 精度不足时（如 NER、黑名单统计），通过 Bash 调用 CLI 脚本补充确定性能力。MCP 是此路径的包装升级（结构化接口 + 自动发现），作为 M4+ 可选优化，不作为核心依赖

### 2.4 用户体验示例

```
首次使用：
> /novel:start
Claude: 检测到无项目。推荐：创建新项目。
       [AskUserQuestion: 创建新项目(Recommended) / 查看帮助]
       [用户选择"创建新项目"]
       请输入小说类型（如：玄幻、都市、悬疑）：
       [用户输入：玄幻]
       [WorldBuilder → 核心设定]
       [CharacterWeaver → 主角+配角]
       请提供 1-3 章风格样本文件路径。

> @chapter-sample-1.md @chapter-sample-2.md
Claude: [StyleAnalyzer → 风格指纹提取]
       [ChapterWriter × 3 → StyleRefiner × 3]
       3 章已生成，评分均值 3.7/5.0。继续？

日常续写：
> /novel:continue
Claude: Vol 2 Ch 48 续写中...
       第 48 章已生成（3120 字），评分 3.9/5.0 ✅

> /novel:continue 3
Claude: Ch 49: 3050字 4.1 ✅ | Ch 50: 2890字 3.2→修订→3.6 ✅ | Ch 51: 3200字 3.8 ✅

卷末回顾（通过 /novel:start 进入）：
> /novel:start
Claude: Vol 2 已完成 51 章。推荐：规划新卷。
       [AskUserQuestion: 规划新卷(Recommended) / 质量回顾 / 继续写作]
       [用户选择"质量回顾"]
       [NER 一致性检查 + 伏笔盘点 + 风格漂移报告]

查看状态：
> /novel:dashboard
Claude: Vol 2, Ch 51/50(超出), 总15万字, 均分3.7, 未回收伏笔3个
```

## 3. 用户画像与市场定位

### 3.1 目标用户：网文作者

**选择依据**（[DR-016](../../v2/dr/dr-016-user-segments.md)）：AI 接受度高、产品匹配度高、市场规模大（中国 2000 万+ 网文作者）

**用户特征**：
- 日更 3000-6000 字，单部作品 100-500 万字
- 核心痛点：灵感枯竭、情节重复、前后矛盾、日更效率压力
- 创作模式：边写边想，每卷（30-50 章）滚动规划，根据读者反馈调整走向
- 付费意愿：$15-30/月

**功能需求优先级**：
1. 续写效率（基于已有内容续写下一章）★★★★★
2. 一致性检查（跨百章的角色/地名/时间线）★★★★★
3. 伏笔追踪（埋设和回收提醒）★★★★
4. 卷级大纲规划★★★★
5. 去 AI 化（输出贴近个人文风）★★★★

### 3.2 差异化定位

**独特卖点**（[DR-017](../../v2/dr/dr-017-competitors.md)）：
1. 卷制滚动工作流（适配网文"边写边想"模式）
2. 自动一致性保证（状态管理 + NER 检查 + 伏笔追踪）
3. 多 agent 专业化分工 + 去 AI 化输出
4. 中文原生支持

**竞品空白**：Sudowrite/NovelAI 未进入中文市场，国内无长篇结构化创作工具。

| 功能 | 本产品 | Sudowrite | NovelAI | ChatGPT |
|------|--------|-----------|---------|---------|
| 续写模式 | ✅ 卷制滚动 | ⚠️ Story Engine | ⚠️ 基础续写 | ⚠️ 对话续写 |
| 多 agent 协作 | ✅ | ❌ | ❌ | ❌ |
| 一致性检查 | ✅ 自动 | ❌ | ❌ | ❌ |
| 伏笔追踪 | ✅ | ❌ | ❌ | ❌ |
| 去 AI 化 | ✅ 4 层策略 | ❌ | ❌ | ❌ |
| 中文支持 | ✅ | ❌ | ⚠️ | ✅ |
