## 1. SKILL.md Context Assembly 提取

- [x] 1.1 新建 `skills/continue/references/context-assembly.md`，从 SKILL.md 迁移 Step 2.0-2.7
- [x] 1.2 SKILL.md Step 2 替换为摘要 + reference 引用（~10 行）
- [x] 1.3 验证 SKILL.md 行数降至 279 行（目标 ~280）
- [x] 1.4 context-assembly.md 内部链接检查

## 2. QJ Track 3 分档输出

- [x] 2.1 编排器 manifest 增加 `track3_mode` 字段（full/lite），基于章节类型判定（context-assembly.md 2.6）
- [x] 2.2 QJ agent prompt Track 3 段落增加模式分支：lite 模式仅输出 overall_engagement + reader_feedback
- [x] 2.3 QJ Format section JSON 示例增加 lite 模式样本
- [x] 2.4 engagement overlay 兼容验证（lite 模式 overall_engagement 始终存在，golden_chapter_flags 仅 full 模式产出）

## 3. 文档同步

- [x] 3.1 `skills/continue/references/context-contracts.md` 增加 track3_mode 字段说明
- [x] 3.2 CLAUDE.md Context Management 段更新（引用 context-assembly.md + Track 3 tiering）

## References

- `skills/continue/SKILL.md` Step 2
- `agents/quality-judge.md` Track 3
- `skills/continue/references/context-contracts.md`
