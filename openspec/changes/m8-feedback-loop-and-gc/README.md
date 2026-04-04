# M8.2 反馈循环与垃圾回收

**来源**：博文《Harness Engineering 视角下的代码熵管理》§十二 Evaluation / Garbage Collection Layer

**核心问题**：管道只有前向循环，QJ 评分不回写影响后续写作（反馈断裂）；系统中的过期伏笔、角色漂移、summary 失真只会累积不会被回收（cleanup half-life = ∞）。

**交付物**：
- `feedback-constraints.json` — QJ 评分驱动的自动约束注入机制
- `scripts/gc-scan.sh` — 卷级垃圾回收扫描脚本
- `logs/gc/gc-report-vol-XX.json` — GC 报告
- Dashboard GC 状态板块
