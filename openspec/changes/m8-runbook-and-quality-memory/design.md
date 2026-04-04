## Context

当前管道在正常流程下运行稳定（CW→Sum→QJ→commit），但遇到异常时——QJ 低分、滑窗矛盾、checkpoint 损坏——agent 的处理路径依赖 skill/agent prompt 中的内联指令。这些指令分散在 5 个 agent 和 3 个 skill 中，无法被交叉验证，也无法作为独立文档被 agent 按需查阅。

博文的 Memory Layer 设计原则：
- 短索引（CLAUDE.md）+ 深事实（docs 树）
- 权威事实必须版本化、路径短、引用强
- agent 在长时间运行中反复回访 spec/plan/constraints/status 防止 drift

## Goals / Non-Goals

**Goals:**
- 建立 `docs/runbooks/` 目录，初始覆盖 5 个高频异常场景
- Runbook 格式标准化：触发条件、诊断步骤、修复动作、验收标准、回退方案
- 新增 `QUALITY.md` 聚合视图：按卷/按维度的评分趋势、连续低分预警、清扫队列
- Dashboard skill 能按需刷新 QUALITY.md
- Agent prompt 中的内联异常处理逐步迁移为 runbook 路径引用

**Non-Goals:**
- 不做自动化 runbook 执行（M8 仅提供查阅，不做自动触发）
- 不改变 QJ 评分 schema 或门控阈值
- QUALITY.md 不替代 evaluations/ 中的原始评分文件

## Decisions

1. **Runbook 格式**
   - 每个 runbook 一个 markdown 文件：`docs/runbooks/{scenario}.md`
   - 标准段落：Trigger / Diagnosis / Actions / Acceptance / Rollback
   - 最多 2 页，超出则拆分

2. **初始 Runbook 清单**
   - `quality-gate-handling.md`：QJ 各档位（pass/polish/revise/review/rewrite）的具体处理流程
   - `sliding-window-fix.md`：滑窗校验发现时间线/设定矛盾时的定位与修复流程
   - `checkpoint-recovery.md`：checkpoint 文件损坏或状态不一致时的恢复路径
   - `foreshadow-lifecycle.md`：伏笔埋设→追踪→回收的全生命周期操作指南
   - `cross-volume-handoff.md`：卷末回顾→下卷规划的数据流与检查清单

3. **QUALITY.md 结构**
   - 按卷分段，每卷包含：8 维评分均值/趋势、连续 ≥3 章低于 3.5 的维度预警、最近 5 章的 gate decision 分布
   - 尾部附清扫队列：待修复的 violations、待回收的伏笔、待更新的过期文档
   - 由 `scripts/aggregate-quality.sh`（新增）从 evaluations/ 聚合生成

4. **迁移策略**
   - Agent prompt 中的异常处理保留为摘要级指令（≤3 行），详细流程引用 runbook 路径
   - 不一次性重写所有 agent prompt，按实际触发频率渐进迁移

## Risks / Trade-offs

- [Risk] Runbook 本身会腐烂 → Mitigation：QUALITY.md 清扫队列中包含 "stale runbook" 检查项；滑窗校验和 QJ 如果发现 runbook 引用的路径/字段已失效则输出 WARNING
- [Risk] QUALITY.md 聚合脚本增加管道复杂度 → Mitigation：聚合仅在 dashboard 按需触发，不进入章节管道关键路径
- [Trade-off] Runbook 与 agent prompt 存在信息重复 → 接受短期冗余，以渐进迁移为原则

## References

- 博文 §七 Memory Layer
- 博文 §十四.2 运营层指标：Legibility Coverage
- `evaluations/` 评分产物格式
- `skills/dashboard/SKILL.md`
