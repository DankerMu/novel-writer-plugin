## 1. Runbook 体系

- [ ] 1.1 创建 `docs/runbooks/` 目录结构与 runbook 模板（Trigger/Diagnosis/Actions/Acceptance/Rollback）
- [ ] 1.2 编写 `quality-gate-handling.md`：各 gate 档位的处理流程（含 polish 循环上限）
- [ ] 1.3 编写 `sliding-window-fix.md`：滑窗校验矛盾的定位与修复流程
- [ ] 1.4 编写 `checkpoint-recovery.md`：checkpoint 损坏/状态不一致的恢复路径
- [ ] 1.5 编写 `foreshadow-lifecycle.md`：伏笔全生命周期操作指南
- [ ] 1.6 编写 `cross-volume-handoff.md`：跨卷衔接数据流与检查清单

## 2. 质量聚合

- [ ] 2.1 新增 `scripts/aggregate-quality.sh`：从 evaluations/ 聚合评分数据
- [ ] 2.2 定义 QUALITY.md 输出格式：按卷分段、8 维均值/趋势、低分预警、清扫队列
- [ ] 2.3 Dashboard skill 集成：`/novel:dashboard` 增加 QUALITY.md 刷新入口

## 3. 索引与迁移

- [ ] 3.1 `CLAUDE.md` 增加 runbook 索引条目
- [ ] 3.2 ChapterWriter agent prompt：异常处理摘要化 + runbook 路径引用
- [ ] 3.3 QualityJudge agent prompt：异常处理摘要化 + runbook 路径引用
- [ ] 3.4 `/novel:continue` skill：gate 处理流程引用 runbook

## References

- 博文 §七 Memory Layer
- 当前 agent prompt 中的内联异常处理段落
- `evaluations/` 目录结构
