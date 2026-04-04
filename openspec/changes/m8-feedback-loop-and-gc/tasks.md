## 1. QJ 反馈循环

- [ ] 1.1 定义 `feedback-constraints.json` schema（dimension/trigger/constraint/expires_after_chapter）
- [ ] 1.2 `/novel:continue` 增加反馈约束检查逻辑：QJ 完成后扫描最近 N 章评分
- [ ] 1.3 反馈约束生成规则：维度均值 < 3.5 + 无活跃约束 → 新增约束（TTL=5 章）
- [ ] 1.4 PlotArchitect L3 生成时读取 feedback-constraints，合并未过期约束到 acceptance_criteria
- [ ] 1.5 约束过期清理：章节提交后清理 expires_after_chapter ≤ current 的约束

## 2. GC 扫描

- [ ] 2.1 新增 `scripts/gc-scan.sh`：卷级垃圾回收扫描脚本
- [ ] 2.2 伏笔过期检测：planted 且超期未 resolved 的伏笔
- [ ] 2.3 角色契约漂移检测：ability_bounds 与近 10 章正文关键词对比
- [ ] 2.4 Summary 一致性检测：summary 关键事件与章节正文交叉验证
- [ ] 2.5 Storyline 覆盖率检测：active 线 vs 最近章节 POV 覆盖
- [ ] 2.6 GC 报告输出格式：`logs/gc/gc-report-vol-XX.json`（severity 分级）

## 3. Dashboard 集成

- [ ] 3.1 Dashboard skill 增加 GC 状态板块
- [ ] 3.2 Dashboard 展示反馈约束当前状态（活跃/已过期/已生效）

## References

- 博文 §十二 Evaluation / Garbage Collection Layer
- `agents/quality-judge.md`
- `skills/continue/SKILL.md`
- `skills/dashboard/SKILL.md`
