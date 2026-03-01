# Tasks: 上下文质量增强

## 1. Canon Status（M5.1）

- [ ] 1.1 扩展 `world/rules.json` schema：增加 `canon_status` 字段（`established` / `planned`），默认 `established`
- [ ] 1.2 扩展 `characters/active/*.json` schema：在 `abilities`、`known_facts`、`relationships` 中支持 `canon_status`
- [ ] 1.3 修改 `/novel:continue` manifest 组装逻辑：`hard_rules_list` 过滤条件叠加 `canon_status == "established"`（AND 关系）
- [ ] 1.4 修改 `/novel:continue` Step 2.4 角色裁剪：预过滤 `planned` 子条目；chapter_contract 引入的 planned 条目标记 `introducing: true`
- [ ] 1.5 修改 `agents/summarizer.md`：输出增加 `canon_hints` 字段（本章可能确立的 planned 内容 ID 列表）
- [ ] 1.6 修改 `/novel:continue` Step 6 commit 阶段：基于 `canon_hints` + `state_ops` 确定性交叉验证，执行 canon_status 升级，记录到 `changelog.jsonl`
- [ ] 1.7 修改 `agents/chapter-writer.md`：明确指示仅引用 established 内容，`introducing: true` 条目可作为本章新设定使用
- [ ] 1.8 修改 `agents/quality-judge.md`：`l1_checks` status 枚举扩展 `"warning"`；增加 planned 引用 WARNING 逻辑；明确 warning 不触发修订门控
- [ ] 1.9 修改 `agents/world-builder.md`：创建 rule 时初始化 `canon_status: "planned"`；更新 schema 示例和约束声明
- [ ] 1.10 更新 `eval/schema/` 中 rules.json 和角色 JSON schema

## 2. Platform Guide（M5.2）

- [ ] 2.1 创建 `templates/platforms/fanqie.md`（番茄小说写作指南，覆盖 4 个必需维度 + 章节字数建议）
- [ ] 2.2 扩展 `templates/style-profile-template.json`：增加 `platform` 字段
- [ ] 2.3 修改 `/novel:continue` manifest 组装：约定式查找 `templates/platforms/{platform}.md`，条件加载 `paths.platform_guide`
- [ ] 2.4 修改 `agents/chapter-writer.md`：输入定义增加可选 `platform_guide`；明确 style-profile > platform_guide 优先级
- [ ] 2.5 修改 `/novel:start` 快速启动流程：Step B 中采集平台偏好（番茄/起点/晋江/其他/跳过）
- [ ] 2.6 创建占位模板 `templates/platforms/qidian.md`、`jinjiang.md`（标注 TODO）

## 3. Excitement Type（M5.3）

- [ ] 3.1 定义 `excitement_type` 枚举集合（8 种）+ `excitement_note` 自由文本字段；更新 L3 chapter contract schema（根级字段）
- [ ] 3.2 增加 schema 校验规则：`setup` 与其他类型互斥；空数组 `[]` 拒绝
- [ ] 3.3 修改 `agents/plot-architect.md`：生成 L3 contract 时自动填充 `excitement_type`
- [ ] 3.4 修改 `agents/quality-judge.md`：`pacing` 维度增加爽点落地评估；setup 章改用"铺垫有效性"标准；未知枚举值 WARNING 而非 crash
- [ ] 3.5 修改 `agents/chapter-writer.md`：读取 `excitement_type` 作为写作指引
- [ ] 3.6 更新 `skills/novel-writing/references/quality-rubric.md`：补充爽点评估标准和 setup 章替代标准
- [ ] 3.7 更新 `eval/schema/` 中 chapter contract JSON schema

## 4. 文档与测试

- [ ] 4.1 更新 `docs/user/spec-system.md`：补充 canon_status、platform、excitement_type 说明
- [ ] 4.2 更新 `skills/continue/references/context-contracts.md`：manifest 新增 `platform_guide` 路径 + `hard_rules_list` 注释更新（含 canon_status 过滤条件）+ Summarizer 输出增加 `canon_hints`
- [ ] 4.3 更新 `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md`：同步 context 组装伪代码
- [ ] 4.4 创建迁移指南：旧项目升级提示（canon_status 审查、platform 设置、excitement_type 回填）
- [ ] 4.5 补充 `eval/fixtures/` 中的 smoke test 用例

## References

- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` — 编排器 context 组装
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md` — 数据 schema 定义
- `skills/continue/references/context-contracts.md` — Manifest 字段契约
- `agents/quality-judge.md` — l1_checks status 枚举
