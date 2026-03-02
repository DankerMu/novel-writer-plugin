# novel — 中文网文多 Agent 协作创作系统

Claude Code 插件，5 个 AI Agent 协作完成网文创作全流程：世界观构建 → 卷级规划 → 章节续写（含去 AI 润色） → 质量验收（含读者体验评估）。内置去 AI 化四层策略和 Spec-Driven 规范体系，产出接近人类写手的长篇中文网络小说。

## 快速开始

### 前置条件

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 已安装并登录
- Python 3.10+（评估脚本需要）

### 安装

**方式一：Marketplace 安装（推荐）**

```bash
# 1. 添加 marketplace（只需一次）
claude plugin marketplace add DankerMu/cc-novel-writer

# 2. 安装插件
claude plugin install novel
```

安装后在任意目录启动 `claude` 即可使用 `/novel:start` 等命令。

**方式二：`--plugin-dir` 按会话加载**

```bash
# 克隆到本地
git clone https://github.com/DankerMu/cc-novel-writer.git ~/cc-novel-writer

# 启动时挂载插件
mkdir ~/my-novel && cd ~/my-novel
claude --plugin-dir ~/cc-novel-writer
```

> **Tip**：添加 alias 省去每次输入路径：`alias novel='claude --plugin-dir ~/cc-novel-writer'`

### 三个入口命令

| 命令 | 用途 |
|------|------|
| `/novel:start` | 从创作纲领（brief）冷启动一个新项目 |
| `/novel:continue` | 续写下一章 / 推进到下一卷 |
| `/novel:dashboard` | 查看当前项目进度、状态与统计 |

**30 秒体验**：执行 `/novel:start`，按提示填写题材、主角和核心冲突，系统自动创建项目结构并试写 3 章。详见 [快速起步指南](docs/user/quick-start.md)。

### 推荐配套

以下技能非必须，但能显著提升创作质量：

| 技能 | 用途 | 安装 |
|------|------|------|
| `doc-workflow` | 深度背景研究（历史/科幻/军事题材推荐） | 见 [CCskill 仓库](https://github.com/DankerMu/CCskill) |
| `brainstorming` | 结构化脑暴（世界观/角色/情节设计） | 同上 |
| `deep-research` | 多源信息综合研究 | 同上 |

系统会在创建项目时自动检测题材，对需要事实查证的类型（历史、科幻、军事等）主动建议先做背景研究。

## 工作原理

### 卷制滚动工作流

网文采用「边写边想」模式，以卷（30-50 章）为单位滚动推进：

```
卷规划 → 日更续写（每章流水线） → 定期检查（每 10 章） → 卷末回顾 → 下一卷
```

每章经过完整流水线：

```
ChapterWriter(含润色) → Summarizer → QualityJudge(含读者评估)
      续写+去AI润色         摘要+状态       双轨验收+读者体验
```

### 5 Agent 协作体系

| Agent | 模型 | 职责 |
|-------|------|------|
| **WorldBuilder** | Opus | 世界观构建 + L1 硬规则 + 角色管理(L2 契约) + 风格提取 |
| **PlotArchitect** | Opus | 卷级大纲 + L3 章节契约 + 故事线调度 |
| **ChapterWriter** | Opus | 章节续写 + 多线叙事 + 去 AI 化润色（Phase 2） |
| **Summarizer** | Opus | 摘要 + 状态增量 + 串线检测 |
| **QualityJudge** | Opus | 双轨验收 + 8 维度评分 + 读者参与度评估 |

### Spec-Driven 四层规范

写小说如同写代码——规范先行，验收对齐规范：

| 层级 | 内容 | 约束强度 |
|------|------|---------|
| **L1** 世界规则 | `rules.json` — 不可违反的硬约束 | 铁律 |
| **L2** 角色契约 | `contracts/` — 能力/行为边界 | 可变更需走协议 |
| **L3** 章节契约 | `chapter-contracts/` — 前/后置条件 | 可协商须留痕 |
| **LS** 故事线 | `storylines.json` — 多线叙事约束 | 跨线泄漏为硬违规 |

### 质量门控

8 维度加权评分（1-5 分）：

```
情节逻辑(18%) + 角色塑造(18%) + 沉浸感(15%) + 风格自然度(15%)
+ 伏笔处理(10%) + 节奏(8%) + 情感冲击(8%) + 故事线连贯(8%)
```

五档门控决策：≥4.0 通过 → ≥3.5 二次润色 → ≥3.0 自动修订 → ≥2.0 人工审核 → <2.0 强制重写。关键章节启用 Sonnet + Opus 双裁判。

### 去 AI 化策略

四层流水线确保输出像人写的：

1. **风格锚定**：从用户样本提取风格指纹
2. **约束注入**：AI 黑名单 + 语癖 + 句式多样化
3. **后处理**：ChapterWriter Phase 2 替换 AI 用语 + 匹配风格
4. **检测度量**：黑名单命中 < 3 次/千字，相邻 5 句重复句式 < 2

## 项目结构

```
.claude-plugin/plugin.json     插件入口
agents/                        5 个 Agent 定义
  chapter-writer.md
  plot-architect.md
  quality-judge.md
  summarizer.md
  world-builder.md
skills/
  start/SKILL.md              /novel:start 冷启动
  continue/SKILL.md           /novel:continue 续写
  dashboard/SKILL.md          /novel:dashboard 状态
  novel-writing/               共享方法论知识库
    SKILL.md
    references/
      quality-rubric.md        8 维度评分标准
      style-guide.md           去 AI 化策略
templates/
  brief-template.md            创作纲领模板
  ai-blacklist.json            AI 高频用语黑名单（38 词）
  style-profile-template.json  风格指纹模板
hooks/hooks.json               SessionStart 自动注入 context
scripts/
  inject-context.sh            Context 注入（checkpoint + 摘要）
  audit-staging-path.sh        Staging 路径审计
  run-ner.sh                   中文 NER 命名实体识别
  query-foreshadow.sh          伏笔查询
  lint-blacklist.sh            AI 黑名单命中统计
  calibrate-quality-judge.sh   QualityJudge 校准（Pearson r + 阈值建议）
  run-regression.sh            回归运行（合规率 + 评分汇总）
  compare-regression-runs.sh   回归 run 对比
  lib/                         共享 Python 模块
eval/
  datasets/                    人工标注数据集（JSONL）
  schema/                      标注 schema（JSON Schema）
  fixtures/                    脚本冒烟测试 fixture
  labeling-guide.md            标注指南
docs/
  user/                        用户文档
    quick-start.md               30 分钟快速起步
    ops.md                       常用操作
    spec-system.md               四层规范体系
    storylines.md                多线叙事指南
  test/                        测试清单
  prd/                         产品需求文档（11 章）
  spec/                        技术规范（6 章 + 5 Agent 独立定义）
```

## 评估与回归

项目内置完整的评估基础设施，用于校准 QualityJudge 并跟踪质量回归：

```bash
# 校准：计算 judge vs 人工标注的 Pearson 相关系数 + 阈值建议
scripts/calibrate-quality-judge.sh \
  --project <novel_project_dir> \
  --labels eval/datasets/m2-30ch/v1/labels-*.jsonl

# 回归运行：统计合规率 + 评分分布
scripts/run-regression.sh \
  --project <novel_project_dir> \
  [--archive eval/runs/]

# 对比两次回归运行
scripts/compare-regression-runs.sh \
  eval/runs/<run_a>/summary.json \
  eval/runs/<run_b>/summary.json
```

## CI

PR 合入 `main` 自动触发：

- **Markdown lint** — `npx markdownlint-cli2 "docs/**/*.md"`
- **链接检查** — `lychee` 死链扫描
- **Manifest 校验** — `manifest.json` 结构完整性

## 开发进度

| 里程碑 | 描述 | 状态 |
|--------|------|------|
| **M1** | 续写引擎基础（5 Agent + 3 Entry Skill + 模板） | 已完成 |
| **M2** | Context 组装与状态机（Orchestrator + Spec 注入 + Hooks） | 已完成 |
| **M3** | 质量门控与分析（5 档门控 + 双裁判 + NER + 伏笔 + 回归） | 已完成 |
| **M4** | 端到端打磨（Quick Start + 跨卷 + E2E 基准） | 进行中 |

详见 [progress.md](progress.md)。

## 许可

本项目尚未选定开源许可证。如需使用请先联系作者。

## 作者

**DankerMu** — [mumzy@mail.ustc.edu.cn](mailto:mumzy@mail.ustc.edu.cn)
