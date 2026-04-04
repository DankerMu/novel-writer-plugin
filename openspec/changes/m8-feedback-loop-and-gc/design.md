## Context

当前管道是严格的前向流水线：PlotArchitect 生成 L3 契约 → ChapterWriter 写章 → Summarizer 摘要 → QualityJudge 评分。QJ 的评分结果决定 gate decision（pass/polish/revise 等），但评分中暴露的系统性问题不会自动影响后续章节的写作约束。

博文将这个缺口定义为**反馈循环断裂**：review 反馈停留在评分文件里，不会回写成规则、约束或 skill 改进。同时，随着章节累积，系统中的过期状态（stale foreshadowing、drifted character contracts、inconsistent summaries）只会增长，没有回收通道。

## Goals / Non-Goals

**Goals:**
- QJ 连续 N 章（默认 N=3）在某维度评分 < 3.5 时，自动生成针对性约束，注入后续章节的 L3 契约
- 反馈约束格式标准化，PlotArchitect 在生成 L3 时读取并整合
- 卷级 GC 扫描脚本，检测 4 类陈旧状态：过期伏笔、角色契约漂移、summary 失真、orphaned storyline references
- GC 报告落盘为 JSON，dashboard 可展示

**Non-Goals:**
- 不做 agent prompt 的自动重写（反馈约束通过 L3 契约间接影响 CW，不直接改 agent 定义）
- 不做实时 GC（卷级扫描在 dashboard 或卷末回顾时按需触发）
- 不自动修复 GC 发现的问题（输出报告 + 修复建议，修复由人/agent 在下一轮决定）

## Decisions

1. **反馈约束格式**
   - 存储位置：`volumes/vol-XX/feedback-constraints.json`
   - 结构：`[{"dimension": "pacing", "trigger": "chapters 12-14 avg < 3.5", "constraint": "下一章需包含至少一个节奏转换点", "expires_after_chapter": 18}]`
   - PlotArchitect 生成 L3 时读取当前卷的 feedback-constraints，将未过期约束合并进契约的 acceptance_criteria

2. **反馈触发逻辑**
   - 由 `/novel:continue` 在 QJ 评分完成后检查：读取最近 N 章的评分，按维度计算均值
   - 维度均值 < 3.5 且此维度尚无未过期的反馈约束时，生成新约束
   - 约束有 TTL：默认 `expires_after_chapter = current + 5`，确保不无限累积

3. **GC 扫描范围**
   - `scripts/gc-scan.sh`（新增），接受卷号参数
   - 检测项：
     - 伏笔：plan 中标记为 planted 但超过预期回收章节仍未 resolved
     - 角色契约：active 角色的 ability_bounds 与最近 10 章正文的实际表现偏差
     - Summary：summary 中的关键事件与章节正文不一致（基于关键词匹配）
     - Storyline：storylines.json 中的 active 线与最近章节的 POV 覆盖率
   - 输出：`logs/gc/gc-report-vol-XX.json`

4. **GC 报告与 Dashboard 集成**
   - Dashboard 增加 "GC 状态" 板块：各类陈旧状态的数量、最严重的 3 项
   - GC 报告中的每项标记 severity（info/warn/action_required）

## Risks / Trade-offs

- [Risk] 反馈约束过多导致 L3 过载 → Mitigation：每个维度最多 1 条活跃约束 + TTL 自动过期
- [Risk] GC 扫描的角色漂移检测准确率不高 → Mitigation：M8 仅输出 warn 级别建议，不做硬门控；accuracy 在实际使用中迭代
- [Trade-off] GC 按需触发 vs 自动触发 → M8 选择按需，降低管道复杂度；M9 可考虑自动化

## References

- 博文 §十二 Evaluation / Garbage Collection Layer（三条循环）
- 博文 §十四.2 Cleanup Half-life 指标
- `agents/quality-judge.md`（评分维度定义）
- `volumes/vol-XX/chapter-contracts/`（L3 契约结构）
