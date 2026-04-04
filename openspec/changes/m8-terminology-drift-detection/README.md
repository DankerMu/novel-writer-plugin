# M8.3 术语漂移检测

**来源**：博文《Harness Engineering 视角下的代码熵管理》§三.2 语义熵 + §八 Invariant Layer

**核心问题**：角色名、地名、功法/能力名跨章漂移，当前完全依赖 agent 记忆，无确定性 lint 覆盖。随着章节增加和滑窗压缩，漂移风险递增。

**交付物**：
- `world/terminology.json` — 权威术语表（自动提取 + 手动补充）
- `scripts/extract-terminology.sh` — 术语表提取脚本
- `scripts/lint-terminology.sh` — 术语漂移检测脚本
- CW Phase 2 + QJ 管道集成
