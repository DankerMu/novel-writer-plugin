# M8.1 Runbook 体系与质量聚合

**来源**：博文《Harness Engineering 视角下的代码熵管理》§七 Memory Layer

**核心问题**：故障处理知识散落在 agent prompt 和 skill 中，agent 遇到异常时每次重新拼图（上下文熵）；质量趋势无聚合视图，无法识别系统性退化。

**交付物**：
- `docs/runbooks/` — 5 个标准化故障处理手册
- `QUALITY.md` — 质量趋势聚合视图
- `scripts/aggregate-quality.sh` — 评分聚合脚本
- Agent prompt 异常处理迁移为 runbook 引用
