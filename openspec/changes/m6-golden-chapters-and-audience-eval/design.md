# Design: 黄金三章正式化 + 受众视角评价

## Context

网文「黄金三章」是行业共识——读者在前 3 章决定是否追更。业界编辑经验数据估计：前 300 字跳出率约 78%，前 3 章留存率不足 5%。当前 Quick Start 的试写 pipeline 缺乏 L3 合约、excitement_type、platform_guide 等关键约束，产出物质量与正式章节存在代差。同时 QualityJudge 的通用等权评分无法反映不同平台读者的核心期待差异。

深度调研（`docs/dr-workflow/m6-golden-chapters-research/final/main.md`，91/100 评分）确认：
- 6 大类型黄金三章存在结构性差异（第一驱动力、金手指时机、慢热容忍度均不同）
- 3 大平台要求有结构性差异（番茄 200 字建冲突 / 起点 3 万字定签约 / 晋江人设好可慢热）
- 读者自发评价维度与 QJ 8 维度高度吻合，仅需按平台调整权重
- 某些 genre×platform 组合实际不存在（如起点无纯爱 BL、番茄无硬科幻）

## Goals / Non-Goals

**Goals:**
- 让前 3 章通过与正式章节相同的完整 pipeline，确保黄金三章为生产级质量
- QualityJudge 能感知目标平台，按受众期待加权评分
- 卷规划能从前 3 章的 summaries/contracts 无缝继承
- Step F0 规划考虑平台差异化参数（章节字数、钩子密度、主角登场时限）

**Non-Goals:**
- 不改变 Quick Start 的 Step A-E 流程
- 不改变 `/novel:continue` pipeline 本身
- 不改变 8 维度评分体系的维度定义（只改权重）
- 不为每个 platform×genre 组合创建独立权重（M6 为平台级粒度，genre 差异通过 L3 acceptance_criteria 处理）
- 不扩展 QJ 维度数量（M7+ 再考虑从 8 维扩展到 10 维）

## Decisions

### 1. 新增 Step F0 迷你卷规划 + 平台差异化参数

**备选方案：**
- A) 在 Quick Start 中插入迷你 PlotArchitect 调用，仅规划前 3 章，按平台参数差异化
- B) 手动构造简化版 L3 contracts（不调用 PlotArchitect）
- C) Quick Start 不写章节，留到卷规划后再写

**选择 A**：迷你卷规划 + 平台差异化。原因：
- PlotArchitect 生成的 L3 contracts 格式与正式 pipeline 完全兼容，无需适配层
- 前 3 章的 excitement_type 由 PlotArchitect 决定，比手动构造更智能
- 方案 C 破坏了 Quick Start 「30 分钟出成果」的核心体验

**迷你卷规划输入精简：**
- brief.md（来自 Step A/B.5）
- world/rules.json（来自 Step D）
- characters/active/（来自 Step D）
- platform_guide（来自 M5.2 convention）— 提供平台差异化参数
- 无 prev volume review（首卷无前卷）
- PlotArchitect 仅输出 3 章 outline + 3 个 L3 contracts + foreshadowing（初始化）+ storyline-schedule（简化）

**平台差异化 Step F0 参数**（来自调研 §3.4）：

| 参数 | 番茄小说 | 起点中文网 | 晋江文学城 | 无平台（默认） |
|------|---------|-----------|------------|---------------|
| 章节字数 | 2000-2300 字 | 3000-4000 字 | 3000-4000 字 | 2500-3500 字 |
| 前 3 章总字数 | 6000-7000 字 | 9000-12000 字 | 9000-12000 字 | 7500-10500 字 |
| 钩子密度 | 每 300 字 1 个 | 每 1000 字 1 个 | 每 1500 字 1 个 | 每 800 字 1 个 |
| 主角登场时限 | 200 字内（含冲突） | 1000 字内 | 第 1 章内 | 300 字内 |
| 金手指出场 | 第 1 章末 | 第 2-3 章 | 视类型 | 前 3 章内 |
| CP 首次互动 | 不强制 | 不强制 | 前 3 章内必须 | 视类型 |

这些参数写入 platform_guide 模板的 `## 黄金三章参数` section，PlotArchitect 在 Step F0 读取。

### 2. 试写章节直接进入 volumes/vol-01/

前 3 章归属 vol-01。Step F0 的输出写入 `volumes/vol-01/`：
- `outline.md`（仅含 3 章，后续卷规划 append 第 4 章起）
- `chapter-contracts/chapter-001.json` ~ `chapter-003.json`
- `foreshadowing.json`（初始）
- `storyline-schedule.json`（初始）

正式卷规划（Step G 确认后）PlotArchitect 接收前 3 章的 summaries + 现有 outline，从第 4 章开始**扩展**而非重建。

### 3. 第 1 章使用 Double-Judge

第 1 章是小说的门面，按「关键章节」标准处理：Sonnet 主评 + Opus 副评，取 min。

调研支撑：LitBench (2025) 发现零样本 LLM 评判准确率仅 73%，Double-Judge 设计可降低系统性偏差风险。

### 4. Quick Start 时间预算

| 阶段 | 原耗时 | 新耗时 | 差异 |
|------|--------|--------|------|
| Step A-E | ~15 min | ~15 min | 不变 |
| Step F0 | 不存在 | ~5 min | +5 min |
| Step F (3章) | ~12 min (弱pipeline) | ~25 min (完整pipeline) | +13 min |
| Step G | ~3 min | ~3 min | 不变 |
| **总计** | **~30 min** | **~48 min** | **+18 min** |

约 50 分钟，可接受。用户获得的是生产级黄金三章而非草稿。

### 5. 受众权重方案：研究驱动的平台权重

**备选方案：**
- A) 在 platform_guide markdown 中新增 `## 评估权重` section，使用乘数格式
- B) 创建独立的 `templates/platforms/{platform}-weights.json`
- C) 使用绝对权重（总和=1.0）而非乘数

**选择 A + 乘数格式**：内置。原因：
- 保持平台相关信息集中管理（一个文件描述一个平台的所有偏好）
- 乘数格式（默认 1.0）比绝对权重更直观：1.5 = 「比通用重要 50%」
- 用户可在同一文件中一目了然地看到写作指南与评估标准的对应关系

**调研驱动的权重值**（来自调研 §4.4，绝对权重→乘数换算：weight / 0.125）：

| QJ 维度 | 番茄乘数 | 起点乘数 | 晋江乘数 | 说明 |
|---------|---------|---------|---------|------|
| pacing | **1.5** | 1.0 | 0.8 | 番茄完读率由节奏决定 |
| character | 0.8 | 1.0 | **1.6** | 晋江核心卖点 |
| emotional_impact | **1.5** | 0.8 | **1.5** | 番茄爽感+晋江情感 |
| style_naturalness | 0.5 | 0.8 | 1.0 | 番茄对文笔容忍度高 |
| foreshadowing | 1.0 | 1.0 | 0.8 | 各平台接近 |
| plot_logic | 0.8 | **1.3** | 0.8 | 起点设定党需求 |
| immersion | **1.5** | 0.8 | 1.1 | 番茄代入感驱动留存 |
| storyline_coherence | 0.8 | **1.5** | 0.8 | 起点世界观一致性 |

权重默认 1.0（等权），范围 0.5-2.0。无权重 section 或无 platform_guide 时全部 1.0。

**维度映射说明**：调研发现受众维度与 QJ 维度高度吻合（6 个直接对应 + 2 个近似映射）。受众维度「创意」和「设定深度」在 QJ 中无直接对应，其权重已分摊到 foreshadowing（创意伏笔）、plot_logic（创意情节）、immersion（设定沉浸）和 storyline_coherence（设定一致性）。M7+ 可扩展 QJ 到 10 维消除分摊。

### 6. overall_final 加权计算



这样 overall_final 仍然在 1-5 分制内，与现有门控阈值兼容，不需要改 gate decision 逻辑。

输出双分：
- `overall_raw`：等权平均（向后兼容）
- `overall_weighted`：加权平均（平台感知）
- `overall_final` = 有 platform 时取 `overall_weighted`，无 platform 时取 `overall_raw`

### 7. excitement_type 按类型推荐默认组合

M5 已定义 8 种枚举。基于调研，为 6 大类型推荐默认 excitement_type 组合（PlotArchitect Step F0 参考）：

| 类型 | 推荐 M5 枚举 | 建议新增（M6+） |
|------|-------------|----------------|
| 玄幻/仙侠 | `power_up` + `confrontation` | — |
| 都市 | `reversal` + `emotional_peak` | `underdog_rise` |
| 科幻 | `worldbuilding_wow` + `mystery_reveal` | — |
| 历史 | `worldbuilding_wow` + `setup` | — |
| 悬疑/推理 | `cliffhanger` + `mystery_reveal` | `tension_build` |
| 言情/甜宠 | `emotional_peak` + `reversal` | `chemistry_spark` |

新增 3 种枚举（`underdog_rise`、`tension_build`、`chemistry_spark`）通过 openspec 流程扩展。在新增落地前使用 `excitement_note` 自由文本兜底。

### 8. Genre × Platform 交互处理

调研发现类型和平台存在强交互（某些组合实际不存在）：
- 番茄：主力玄幻/都市/悬疑/言情，少见科幻/历史
- 起点：主力玄幻/都市/科幻/历史/悬疑，极少言情
- 晋江：主力言情/纯爱，少见硬核玄幻/科幻

**M6 处理方式**：
- Step F0 中 PlotArchitect 检查 genre × platform 组合，无效组合给出 WARNING（不阻塞）
- L3 acceptance_criteria 同时考虑类型要求和平台约束（叠加而非互斥）
- 不为每个组合创建独立权重（复杂度过高），而是类型差异通过 L3 合约 acceptance_criteria 处理，平台差异通过 QJ 权重处理

## Risks / Trade-offs

| 风险 | 缓解 |
|------|------|
| Quick Start 耗时增加 ~18 分钟 | 用户获得生产级黄金三章，ROI 高；可在 Step A 提示预期时间 |
| 迷你卷规划质量不如正式卷规划（信息少） | PlotArchitect 仅规划 3 章，信息密度反而更高；后续正式规划可调整 |
| 卷规划继承前 3 章可能限制 PlotArchitect 发挥 | PlotArchitect 可以在正式规划时修改前 3 章的 outline（但不重写已提交章节） |
| 权重基于定性共识而非定量回归 | Phase 2 (M7+) 通过人工评分 Pearson 相关校准；用户可在 platform_guide 中覆盖 |
| QJ 8 维度不完美覆盖受众 8 维度（缺 originality/world_building） | M6 用分摊到近似维度；M7+ 扩展到 10 维 |
| 不同类型在同平台内权重不同 | 平台级粒度作为 MVP；类型差异通过 L3 acceptance_criteria 处理 |
| genre×platform 无效组合 | Step F0 WARNING + 文档标注 |
| 零样本 LLM 评判准确率仅 73% (LitBench) | Double-Judge + 人工校准集 |

## References

- `docs/dr-workflow/m6-golden-chapters-research/final/main.md` — 深度调研综合报告
- `skills/start/SKILL.md` — Quick Start Step F/G 定义
- `agents/quality-judge.md` — 8 维度评分逻辑
- `skills/novel-writing/references/quality-rubric.md` — 评分标准
- `skills/continue/references/context-contracts.md` — Manifest 字段契约
- `openspec/changes/m5-context-quality-enhancements/specs/context-quality-enhancements/spec.md` — M5 excitement_type 枚举定义
