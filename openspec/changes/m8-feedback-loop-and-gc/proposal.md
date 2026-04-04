## Why

博文 Evaluation / GC Layer 把系统闭环拆成三条循环：前向循环（功能送进系统）、反馈循环（经验回写成规则）、GC 循环（坏模式发现与回收）。当前管道只有前向循环（CW→Sum→QJ→commit），后两条缺失：

1. **反馈循环断裂**：QJ 的评分和 violation 记录是终点，不会回写影响后续 CW/PA 行为。同一类问题（如某维度连续低分）会反复出现，因为管道没有"从失败中学习"的机制。
2. **GC 循环缺失**：没有机制扫描和回收陈旧状态——过期伏笔（已回收但 plan 未更新）、角色契约与实际行文漂移、summaries 与章节正文不一致、orphaned storyline references。

博文用 **cleanup half-life**（坏模式从发现到回收的中位时间）来度量 GC 能力。当前仓库的 cleanup half-life 是 ∞：发现了问题但没有自动回收通道。

## What Changes

- QJ 评分反馈机制：连续低分维度自动生成 constraint 注入下一章 L3 契约
- 卷级 GC 扫描：检测过期伏笔、角色契约漂移、summary 失真、orphaned references
- GC 产物落盘为结构化报告，接入 dashboard 展示

## Capabilities

### New Capabilities

- `qj-feedback-loop`: QJ 评分 → L3 契约约束注入的自动反馈通道
- `gc-scan`: 卷级垃圾回收扫描（伏笔/角色/summary/storyline 一致性）

### Modified Capabilities

- PlotArchitect：L3 契约生成时读取反馈约束
- `/novel:continue`：章节提交后触发反馈约束检查
- `/novel:dashboard`：展示 GC 扫描结果

## Impact

- 影响范围：QJ 评分产物格式（增加 feedback_constraints 字段）、L3 契约模板（增加 feedback_section）、PlotArchitect agent prompt、dashboard skill
- 依赖关系：依赖 evaluations/ 评分产物、章节契约结构、伏笔计划文件
- 兼容性：评分产物增量字段，旧格式无 feedback_constraints 时跳过（向后兼容）

## Milestone Mapping

- M8.2: 反馈循环与垃圾回收

## References

- 博文 §十二 Evaluation / Garbage Collection Layer
- 博文 §十四 指标体系：Trace Grade / Cleanup Half-life
- 当前 QJ 评分流程（`agents/quality-judge.md`）
- 当前 L3 契约结构（`volumes/vol-XX/chapter-contracts/`）
